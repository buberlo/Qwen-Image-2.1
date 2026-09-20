import Foundation
import CryptoKit


final class CoreTests {
    private var directories: [URL] = []
    deinit { for url in directories { try? FileManager.default.removeItem(at: url) } }
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        directories.append(url)
        return url
    }
    private func file(_ role: String = "diffusion", name: String = "test.gguf", content: Data = Data("valid model".utf8)) -> ModelFile {
        let revision = String(repeating: "a", count: 40)
        return .init(role: role, name: name, repository: "test/model", revision: revision,
                     url: URL(string: "https://huggingface.co/test/model/resolve/\(revision)/\(name)")!,
                     bytes: Int64(content.count), sha256: SHA256.hash(data: content).map { String(format: "%02x", $0) }.joined())
    }
    func testManifestRejectsPathTraversalAndMissingComponents() throws {
        let bad = ModelManifest(id: "test", runtimeRevision: String(repeating: "a", count: 40), files: [file(name: "../outside")])
        expectThrows(try bad.validate())
        let pathTraversal = ModelManifest(id: "test", runtimeRevision: String(repeating: "a", count: 40), files: [file(name: "../outside"), file("encoder", name: "encoder.gguf"), file("vision", name: "vision.gguf"), file("vae", name: "vae.gguf")])
        expectThrows(try pathTraversal.validate())
    }
    func testPinnedManifestHasAllRequiredComponents() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let manifest = try JSONDecoder().decode(ModelManifest.self, from: Data(contentsOf: root.appendingPathComponent("App/Resources/Models.json")))
        try manifest.validate()
        expectEqual(manifest.totalBytes, 11_059_819_128)
    }
    func testChecksumRejectsSameSizeCorruption() throws {
        let url = try temporaryDirectory().appendingPathComponent("model")
        let valid = Data("valid model".utf8)
        try valid.write(to: url)
        try FileIntegrity.verify(url, file: file())
        try Data("wrong model".utf8).write(to: url)
        expectThrows(try FileIntegrity.verify(url, file: file()))
    }
    func testInstallerVerifiesOfflineAndRemovesOnlyModels() async throws {
        let directory = try temporaryDirectory()
        let files = ["diffusion", "encoder", "vision", "vae"].map { file($0, name: "\($0).gguf") }
        let manifest = ModelManifest(id: "test", runtimeRevision: String(repeating: "a", count: 40), files: files)
        for f in files { try Data("valid model".utf8).write(to: directory.appendingPathComponent(f.name)) }
        let unrelated = directory.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: unrelated)
        let installer = try ModelInstaller(manifest: manifest, directory: directory)
        try await installer.install(downloadMissing: false) { _ in }
        let ready = await installer.ready()
        expectTrue(ready)
        try await installer.remove()
        let removed = await installer.ready()
        expectFalse(removed)
        expectTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }
    func testCorruptInstalledFileIsNeverReady() async throws {
        let directory = try temporaryDirectory()
        let files = ["diffusion", "encoder", "vision", "vae"].map { file($0, name: "\($0).gguf") }
        let manifest = ModelManifest(id: "test", runtimeRevision: String(repeating: "a", count: 40), files: files)
        try Data("wrong model".utf8).write(to: directory.appendingPathComponent(files[0].name))
        let installer = try ModelInstaller(manifest: manifest, directory: directory)
        do { try await installer.install(downloadMissing: false) { _ in }; fail("Corrupt model accepted") } catch {}
        let ready = await installer.ready()
        expectFalse(ready)
        expectFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(files[0].name).path))
    }
    func testHistorySurvivesRelaunchAndDelete() async throws {
        let directory = try temporaryDirectory()
        let store = try HistoryStore(directory: directory)
        let record = GenerationRecord(id: UUID(), created: Date(), prompt: "test", seed: 42, modelID: "qwen", editing: true, seconds: 12.5, width: 512, height: 512, steps: 40, guidance: 6, sampler: "Euler")
        try await store.save(png: Data([1, 2, 3]), record: record)
        let relaunched = try HistoryStore(directory: directory)
        let records = try await relaunched.list()
        expectEqual(records.first?.seed, 42)
        expectEqual(records.first?.editing, true)
        try await relaunched.delete(record.id)
        let empty = try await relaunched.list()
        expectTrue(empty.isEmpty)
    }
}

private final class RangeProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        let valid = path != "/full"
        let headers = ["Content-Range": path == "/wrong" ? "bytes 0-3/8" : "bytes 4-7/8"]
        let response = HTTPURLResponse(url: request.url!, statusCode: valid ? 206 : 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if path == "/slow" { return }
        client?.urlProtocol(self, didLoad: Data((path == "/short" ? "ab" : "abcd").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class RangeDownloadTests {
    private func request(_ path: String) -> ChunkRequest {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RangeProtocol.self]
        return ChunkRequest(url: URL(string: "https://example.invalid/\(path)")!, start: 4, end: 7, total: 8, configuration: config)
    }
    func testResumedChunkAcceptsExactRange() async throws {
        let bytes = try await request("valid").fetch()
        expectEqual(bytes, Data("abcd".utf8))
    }
    func testRejectsFullResponsesAndWrongOrIncompleteRanges() async {
        for path in ["full", "wrong", "short"] {
            do { _ = try await request(path).fetch(); fail("Accepted \(path)") } catch {}
        }
    }
    func testCancellationBeforeOrDuringTransfer() async {
        let task = Task { try await request("slow").fetch() }
        task.cancel()
        do { _ = try await task.value; fail("Cancellation ignored") }
        catch { expectTrue(error is CancellationError) }
    }
}

private var failures: [String] = []
private func fail(_ text: String, line: Int = #line) { failures.append("line \(line): \(text)") }
private func expectTrue(_ value: Bool, line: Int = #line) { if !value { fail("Expected true", line: line) } }
private func expectFalse(_ value: Bool, line: Int = #line) { if value { fail("Expected false", line: line) } }
private func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, line: Int = #line) { if lhs != rhs { fail("Values differ", line: line) } }
private func expectThrows<T>(_ expression: @autoclosure () throws -> T, line: Int = #line) {
    do { _ = try expression(); fail("Expected an error", line: line) } catch {}
}

@main struct CoreChecks {
    static func main() async throws {
        let core = CoreTests()
        try core.testManifestRejectsPathTraversalAndMissingComponents()
        try core.testPinnedManifestHasAllRequiredComponents()
        try core.testChecksumRejectsSameSizeCorruption()
        try await core.testInstallerVerifiesOfflineAndRemovesOnlyModels()
        try await core.testCorruptInstalledFileIsNeverReady()
        try await core.testHistorySurvivesRelaunchAndDelete()
        let ranges = RangeDownloadTests()
        try await ranges.testResumedChunkAcceptsExactRange()
        await ranges.testRejectsFullResponsesAndWrongOrIncompleteRanges()
        await ranges.testCancellationBeforeOrDuringTransfer()
        if !failures.isEmpty {
            for failure in failures { print("FAIL: \(failure)") }
            exit(1)
        }
        print("PASS: 9 core checks (manifest, checksums, offline verification, removal, corruption, history, HTTP ranges, cancellation)")
    }
}
