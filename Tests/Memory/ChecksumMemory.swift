import Foundation
import CryptoKit

// Standalone process so the shell runner can enforce peak-memory bounds.
@main struct ChecksumMemory {
    static func main() throws {
        let size: Int64 = 5 * 1024 * 1024 * 1024
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { fatalError("Cannot create test file") }
        defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(size)) // Sparse file, no model download.
        try handle.close()
        let zeroChunk = Data(count: 1024 * 1024)
        var expected = SHA256()
        for _ in 0..<(size / Int64(zeroChunk.count)) { expected.update(data: zeroChunk) }
        let digest = expected.finalize().map { String(format: "%02x", $0) }.joined()
        let file = ModelFile(role: "test", name: url.lastPathComponent, repository: "test",
                             revision: "", url: url, bytes: size, sha256: digest)
        try FileIntegrity.verify(url, file: file)
        print("PASS: 5 GiB file checksum verified")
    }
}
