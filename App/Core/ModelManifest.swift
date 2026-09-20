import Foundation
import CryptoKit

struct ModelManifest: Codable, Sendable {
    let id: String
    let runtimeRevision: String
    let files: [ModelFile]
    var totalBytes: Int64 { files.reduce(0) { $0 + $1.bytes } }

    func validate() throws {
        guard !id.isEmpty, runtimeRevision.count == 40,
              Set(files.map(\.role)) == Set(["diffusion", "encoder", "vision", "vae"]), files.count == 4,
              Set(files.map(\.name)).count == files.count else {
            throw QwenError.message("Invalid model manifest")
        }
        for file in files {
            guard file.name == URL(fileURLWithPath: file.name).lastPathComponent,
                  !file.name.contains(".."), file.bytes > 0,
                  file.sha256.count == 64, file.sha256.allSatisfy({ $0.isHexDigit }),
                  file.revision.count == 40, file.url.scheme == "https",
                  file.url.host == "huggingface.co",
                  file.url.path.contains("/resolve/\(file.revision)/") else {
                throw QwenError.message("Invalid model file: \(file.name)")
            }
        }
    }
}

struct ModelFile: Codable, Identifiable, Sendable {
    let role: String
    let name: String
    let repository: String
    let revision: String
    let url: URL
    let bytes: Int64
    let sha256: String
    var id: String { role }
}

enum QwenError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

enum FileIntegrity {
    static func size(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? 0
    }

    static func verify(_ url: URL, file: ModelFile) throws {
        guard size(url) == file.bytes else { throw QwenError.message("Incorrect size: \(file.name)") }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        // FileHandle bridges through autoreleased NSData. On an actor worker,
        // the outer pool can outlive this entire multi-GB verification loop.
        // Drain after every chunk, keeping both the read and hashing in the pool.
        while try autoreleasepool(invoking: {
            try Task.checkCancellation()
            guard let data = try handle.read(upToCount: 4 * 1024 * 1024), !data.isEmpty else { return false }
            hash.update(data: data)
            return true
        }) {}
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == file.sha256 else { throw QwenError.message("Checksum mismatch: \(file.name). Download this file again.") }
    }
}
