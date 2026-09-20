import Foundation
import Combine
import UIKit

struct RunDiagnostic: Codable, Identifiable {
    let id: UUID
    let suiteID: UUID?
    let started: Date
    let device: String
    let os: String
    let model: String
    let runtimeRevision: String
    let editing: Bool
    let seed: Int64
    var status: String
    var stage: String
    var duration: Double
    var peakFootprint: UInt64
    var minimumAvailableMemory: UInt64
    var thermalStates: [Int]
    var resultID: UUID?
    var lastHeartbeat: Date
}

@MainActor
final class Diagnostics: ObservableObject {
    @Published private(set) var runs: [RunDiagnostic] = []
    private let url: URL
    private var timer: Timer?
    private var activeID: UUID?
    var onPressure: (() -> Void)?

    init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("diagnostics.json")
        if FileManager.default.fileExists(atPath: url.path) {
            runs = try JSONDecoder().decode([RunDiagnostic].self, from: Data(contentsOf: url))
            for index in runs.indices where runs[index].status == "running" {
                runs[index].status = "interrupted: app exited; cause unknown (check device termination logs)"
            }
            try persist()
        }
    }
    func begin(editing: Bool, seed: Int64, manifest: ModelManifest, suiteID: UUID?) throws {
        var system = utsname()
        uname(&system)
        let machine = withUnsafePointer(to: &system.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        let id = UUID()
        runs.insert(.init(id: id, suiteID: suiteID, started: Date(), device: machine,
                          os: UIDevice.current.systemVersion, model: manifest.id, runtimeRevision: manifest.runtimeRevision,
                          editing: editing, seed: seed, status: "running", stage: "Preparing", duration: 0,
                          peakFootprint: qi_memory_bytes(), minimumAvailableMemory: qi_available_memory_bytes(),
                          thermalStates: [ProcessInfo.processInfo.thermalState.rawValue], resultID: nil, lastHeartbeat: Date()), at: 0)
        try persist()
        activeID = id
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
    }
    func stage(_ name: String) {
        guard let id = activeID, let index = runs.firstIndex(where: { $0.id == id }) else { return }
        runs[index].stage = name
    }
    private func sample() {
        guard let id = activeID, let index = runs.firstIndex(where: { $0.id == id }) else { return }
        let thermal = ProcessInfo.processInfo.thermalState
        let available = qi_available_memory_bytes()
        runs[index].peakFootprint = max(runs[index].peakFootprint, qi_memory_bytes())
        runs[index].minimumAvailableMemory = min(runs[index].minimumAvailableMemory, available)
        if !runs[index].thermalStates.contains(thermal.rawValue) { runs[index].thermalStates.append(thermal.rawValue) }
        runs[index].duration = Date().timeIntervalSince(runs[index].started)
        runs[index].lastHeartbeat = Date()
        do { try persist() } catch { onPressure?() }
        if thermal == .critical || (available > 0 && available < 256 * 1024 * 1024) { onPressure?() }
    }
    func finish(status: String, resultID: UUID? = nil) throws {
        sample()
        timer?.invalidate(); timer = nil
        guard let id = activeID, let index = runs.firstIndex(where: { $0.id == id }) else { return }
        activeID = nil
        runs[index].status = status
        runs[index].resultID = resultID
        try persist()
    }
    private func persist() throws { try JSONEncoder().encode(runs).write(to: url, options: .atomic) }
    var exportURL: URL { url }
}
