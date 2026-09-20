import Foundation
import UIKit
import ImageIO

struct InferenceOutput: Sendable {
    let png: Data
    let seconds: Double
}

private final class ProgressRelay {
    let emit: @Sendable (Int, Int, Float) -> Void
    init(_ emit: @escaping @Sendable (Int, Int, Float) -> Void) { self.emit = emit }
}

// Ownership of native state is confined to worker; cancellation uses the bridge's lifetime lock.
final class InferenceEngine: @unchecked Sendable {
    private let worker = DispatchQueue(label: "qwen.inference", qos: .userInitiated)
    private let handle = qi_create()!
    private let stateLock = NSLock()
    private var running = false

    deinit { qi_destroy(handle) }
    func cancel() { qi_cancel(handle) }
    func prepare() { qi_prepare(handle) }

    func generate(prompt: String, seed: Int64, reference: Data?, manifest: ModelManifest, directory: URL,
                  progress: @escaping @Sendable (String, Int, Int) -> Void) async throws -> InferenceOutput {
        try await withCheckedThrowingContinuation { continuation in
            stateLock.lock()
            guard !running else {
                stateLock.unlock()
                continuation.resume(throwing: QwenError.message("Another generation is running")); return
            }
            running = true
            stateLock.unlock()
            worker.async { [self] in
                let outcome: Result<InferenceOutput, Error> = Result {
                    if let reference, reference.count != 512 * 512 * 3 {
                        throw QwenError.message("Invalid reference image buffer")
                    }
                    let started = Date()
                    var strings: [UnsafeMutablePointer<CChar>] = []
                    defer { strings.forEach { free($0) } }
                    for role in ["diffusion", "encoder", "vision", "vae"] {
                        guard let file = manifest.files.first(where: { $0.role == role }),
                              let value = strdup(directory.appendingPathComponent(file.name).path) else {
                            throw QwenError.message("Missing model path")
                        }
                        strings.append(value)
                    }
                    let paths = qi_model_paths(diffusion: UnsafePointer(strings[0]), encoder: UnsafePointer(strings[1]),
                                               vision: UnsafePointer(strings[2]), vae: UnsafePointer(strings[3]))
                    progress("Loading model", 0, 0)
                    guard qi_load(handle, paths, reference != nil) else { throw nativeError() }
                    progress("Encoding prompt and reference", 0, 0)
                    let relay = ProgressRelay { step, total, _ in
                        progress(step == total ? "Finishing sampling and decoding" : "Generating", step, total)
                    }
                    let pointer = Unmanaged.passUnretained(relay).toOpaque()
                    let callback: qi_progress = { step, total, seconds, user in
                        guard let user else { return }
                        Unmanaged<ProgressRelay>.fromOpaque(user).takeUnretainedValue().emit(Int(step), Int(total), seconds)
                    }
                    var output = qi_image()
                    let ok = withExtendedLifetime(relay) {
                        prompt.withCString { prompt in
                            if let reference {
                                return reference.withUnsafeBytes { bytes in
                                    qi_generate(handle, prompt, seed, bytes.bindMemory(to: UInt8.self).baseAddress, callback, pointer, &output)
                                }
                            }
                            return qi_generate(handle, prompt, seed, nil, callback, pointer, &output)
                        }
                    }
                    defer { qi_free_image(&output) }
                    guard ok else { throw nativeError() }
                    guard let pixels = output.pixels else { throw QwenError.message("No output pixels") }
                    let width = Int(output.width), height = Int(output.height), channels = Int(output.channels)
                    let data = Data(bytes: pixels, count: width * height * channels)
                    guard let provider = CGDataProvider(data: data as CFData),
                          let cgImage = CGImage(width: width, height: height, bitsPerComponent: 8,
                                              bitsPerPixel: channels * 8, bytesPerRow: width * channels,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGBitmapInfo(rawValue: channels == 4 ? CGImageAlphaInfo.last.rawValue : CGImageAlphaInfo.none.rawValue),
                                              provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
                          let png = UIImage(cgImage: cgImage).pngData() else { throw QwenError.message("Unable to encode output PNG") }
                    return InferenceOutput(png: png, seconds: Date().timeIntervalSince(started))
                }
                qi_unload(handle)
                stateLock.lock(); running = false; stateLock.unlock()
                continuation.resume(with: outcome)
            }
        }
    }
    private func nativeError() -> Error {
        let message = String(cString: qi_error(handle))
        return message.lowercased().contains("cancel") ? CancellationError() : QwenError.message(message)
    }
}

// Downsample while decoding to avoid allocating the full camera image.
enum ReferenceImage {
    static func normalize(_ data: Data) throws -> (preview: UIImage, rgb: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 512
              ] as CFDictionary) else { throw QwenError.message("Unable to read this photo") }
        let image = UIImage(cgImage: thumbnail)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = true
        let preview = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
            let scale = min(512 / image.size.width, 512 / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: (512 - size.width) / 2, y: (512 - size.height) / 2, width: size.width, height: size.height))
        }
        var rgba = [UInt8](repeating: 0, count: 512 * 512 * 4)
        let drawn = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 512, height: 512,
                                          bitsPerComponent: 8, bytesPerRow: 512 * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                  let cg = preview.cgImage else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: 512, height: 512))
            return true
        }
        guard drawn else { throw QwenError.message("Unable to prepare reference image") }
        var rgb = Data(capacity: 512 * 512 * 3)
        for index in stride(from: 0, to: rgba.count, by: 4) { rgb.append(contentsOf: rgba[index..<(index + 3)]) }
        return (preview, rgb)
    }
}
