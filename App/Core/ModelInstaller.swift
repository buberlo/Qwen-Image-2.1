import Foundation

struct InstallProgress: Sendable {
    let label: String
    let completed: Int64
    let total: Int64
    var downloading = false
}

actor ModelInstaller {
    let manifest: ModelManifest
    let directory: URL
    private var operating = false
    private var verifiedThisSession = false

    init(manifest: ModelManifest, directory: URL) throws {
        try manifest.validate()
        self.manifest = manifest
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var mutable = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutable.setResourceValues(values)
    }

    func ready() -> Bool {
        verifiedThisSession && manifest.files.allSatisfy { FileIntegrity.size(directory.appendingPathComponent($0.name)) == $0.bytes }
    }

    func install(downloadMissing: Bool, progress: @escaping @Sendable (InstallProgress) -> Void) async throws {
        guard !operating else { throw QwenError.message("Model installation is already running") }
        operating = true
        verifiedThisSession = false
        defer { operating = false }
        var completed: Int64 = 0
        for file in manifest.files {
            try Task.checkCancellation()
            let target = directory.appendingPathComponent(file.name)
            let partial = directory.appendingPathComponent(file.name + ".partial")
            if FileManager.default.fileExists(atPath: target.path) {
                progress(.init(label: "Verifying \(file.role)", completed: completed, total: manifest.totalBytes))
                do { try FileIntegrity.verify(target, file: file) }
                catch is CancellationError { throw CancellationError() }
                catch {
                    try FileManager.default.removeItem(at: target)
                    throw error
                }
            } else {
                guard downloadMissing else { throw QwenError.message("Download the model before generating") }
                let existing = FileIntegrity.size(partial)
                let remaining = manifest.files.reduce(Int64(0)) { total, f in
                    let installed = FileIntegrity.size(directory.appendingPathComponent(f.name))
                    let pending = FileIntegrity.size(directory.appendingPathComponent(f.name + ".partial"))
                    return total + max(0, f.bytes - max(installed, pending))
                }
                let values = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                guard let available = values.volumeAvailableCapacityForImportantUsage,
                      available > remaining + 512 * 1024 * 1024 else {
                    throw QwenError.message("Not enough free storage. Keep at least \(ByteCountFormatter.string(fromByteCount: remaining + 512 * 1024 * 1024, countStyle: .file)) free.")
                }
                if existing > file.bytes { try FileManager.default.removeItem(at: partial) }
                if !FileManager.default.fileExists(atPath: partial.path) {
                    guard FileManager.default.createFile(atPath: partial.path, contents: nil) else { throw QwenError.message("Cannot create model file") }
                }
                let handle = try FileHandle(forWritingTo: partial)
                do {
                    var offset = try handle.seekToEnd()
                    progress(.init(label: "Connecting to model host…", completed: completed + Int64(offset), total: manifest.totalBytes, downloading: true))
                    while offset < file.bytes {
                        try Task.checkCancellation()
                        let end = min(Int64(offset) + 8 * 1024 * 1024, file.bytes) - 1
                        let base = completed + Int64(offset)
                        let total = manifest.totalBytes
                        let request = ChunkRequest(url: file.url, start: Int64(offset), end: end, total: file.bytes) { received in
                            progress(.init(label: "Downloading \(file.role)", completed: base + received, total: total, downloading: true))
                        }
                        let bytes = try await request.fetch()
                        try Task.checkCancellation()
                        try handle.write(contentsOf: bytes)
                        try handle.synchronize()
                        offset += UInt64(bytes.count)
                        progress(.init(label: "Downloading \(file.role)", completed: completed + Int64(offset), total: manifest.totalBytes, downloading: true))
                    }
                    try handle.close()
                } catch { try? handle.close(); throw error }
                progress(.init(label: "Verifying \(file.role)", completed: completed + file.bytes, total: manifest.totalBytes))
                do { try FileIntegrity.verify(partial, file: file) }
                catch is CancellationError { throw CancellationError() }
                catch { try? FileManager.default.removeItem(at: partial); throw error }
                try FileManager.default.moveItem(at: partial, to: target)
            }
            completed += file.bytes
        }
        verifiedThisSession = true
        progress(.init(label: "Model verified · ready offline", completed: completed, total: manifest.totalBytes))
    }

    func remove() throws {
        guard !operating else { throw QwenError.message("Pause installation first") }
        verifiedThisSession = false
        for file in manifest.files {
            for name in [file.name, file.name + ".partial"] {
                let url = directory.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            }
        }
    }
}

// Fixed-size HTTP ranges persist across app termination without opaque resume data.
// Reject full-file responses before receiving their bodies to bound memory use.
final class ChunkRequest: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let url: URL
    let start: Int64
    let end: Int64
    let total: Int64
    private let lock = NSLock()
    private var cancelled = false
    private var task: URLSessionDataTask?
    private var session: URLSession?
    private var continuation: CheckedContinuation<Data, Error>?
    private var data = Data()
    private var responseError: Error?
    private let onProgress: @Sendable (Int64) -> Void
    private var lastReport = ProcessInfo.processInfo.systemUptime
    private let configuration: URLSessionConfiguration

    init(url: URL, start: Int64, end: Int64, total: Int64, configuration: URLSessionConfiguration = .ephemeral, onProgress: @escaping @Sendable (Int64) -> Void = { _ in }) {
        self.url = url; self.start = start; self.end = end; self.total = total
        self.configuration = configuration
        self.onProgress = onProgress
    }
    func fetch() async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                defer { lock.unlock() }
                if cancelled { continuation.resume(throwing: CancellationError()); return }
                self.continuation = continuation
                let config = self.configuration
                config.timeoutIntervalForRequest = 60
                config.timeoutIntervalForResource = 300
                let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
                self.session = session
                var request = URLRequest(url: url)
                request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
                request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                let task = session.dataTask(with: request)
                self.task = task
                task.resume()
            }
        } onCancel: {
            self.lock.lock()
            self.cancelled = true
            self.task?.cancel()
            self.lock.unlock()
        }
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, http.statusCode == 206,
              http.value(forHTTPHeaderField: "Content-Range") == "bytes \(start)-\(end)/\(total)" else {
            responseError = QwenError.message("Model host returned an invalid download range. Retry when connected.")
            completionHandler(.cancel); return
        }
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive bytes: Data) {
        guard Int64(data.count + bytes.count) <= end - start + 1 else {
            responseError = QwenError.message("Download exceeded its expected size")
            dataTask.cancel(); return
        }
        data.append(bytes)
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastReport >= 0.25 || Int64(data.count) == end - start + 1 {
            lastReport = now
            onProgress(Int64(data.count))
        }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let completion = continuation
        continuation = nil
        let wasCancelled = cancelled
        self.task = nil
        self.session = nil
        lock.unlock()
        session.finishTasksAndInvalidate()
        if wasCancelled { completion?.resume(throwing: CancellationError()) }
        else if let error = responseError ?? error { completion?.resume(throwing: error) }
        else if Int64(data.count) != end - start + 1 { completion?.resume(throwing: QwenError.message("Incomplete download chunk")) }
        else { completion?.resume(returning: data) }
    }
}
