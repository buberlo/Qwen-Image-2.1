import SwiftUI
import Photos

@MainActor
final class AppModel: ObservableObject {
    @Published var prompt = "A red ceramic teapot on a wooden table, soft window light, realistic photograph"
    @Published var reference: UIImage?
    private var referenceRGB: Data?
    @Published var result: UIImage?
    @Published var resultURL: URL?
    @Published var records: [GenerationRecord] = []
    @Published var busy = false
    @Published var installing = false
    @Published var ready = false
    @Published var status = "Install the model to begin"
    @Published var step = 0
    @Published var totalSteps = 0
    @Published var installFraction = 0.0
    @Published var installBytes: Int64 = 0
    @Published var downloadSpeed = 0.0
    @Published var lastDownloadActivity = Date()
    @Published var downloading = false
    private var speedSamples: [(time: TimeInterval, bytes: Int64)] = []
    private var installToken: UUID?
    @Published var error: String?
    @Published var suiteStatus = "Not tested on this device"
    @Published var selectedTab = 0
    let manifest: ModelManifest
    let diagnostics: Diagnostics
    let history: HistoryStore
    private let installer: ModelInstaller
    private let engine = InferenceEngine()
    private let modelDirectory: URL
    private var installation: Task<Void, Never>?
    private var cancelled = false
    private var activeRunToken: UUID?
    private var cancellationReason = "Cancelled"
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var memoryObserver: NSObjectProtocol?

    init() throws {
        guard let resource = Bundle.main.url(forResource: "Models", withExtension: "json") else { throw QwenError.message("Missing model manifest") }
        manifest = try JSONDecoder().decode(ModelManifest.self, from: Data(contentsOf: resource))
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("QwenOffline")
        modelDirectory = root.appendingPathComponent("Models")
        installer = try ModelInstaller(manifest: manifest, directory: modelDirectory)
        history = try HistoryStore(directory: root.appendingPathComponent("History"))
        diagnostics = try Diagnostics(directory: root.appendingPathComponent("Diagnostics"))
        diagnostics.onPressure = { [weak self] in self?.cancel(reason: "Stopped for memory or thermal pressure; allow the phone to cool and retry.") }
        memoryObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.cancel(reason: "Stopped because iOS reported memory pressure.") }
        }
    }
    func refreshHistory() async {
        do { records = try await history.list() } catch { self.error = error.localizedDescription }
    }
    func verifyModels() {
        guard !busy, !installing else { return }
        startInstall(downloadMissing: false)
    }
    func startInstall(downloadMissing: Bool = true) {
        guard !busy, !installing else { return }
        installing = true; ready = false; error = nil
        let token = UUID()
        installToken = token
        speedSamples = []; downloadSpeed = 0; downloading = downloadMissing
        lastDownloadActivity = Date()
        status = downloadMissing ? "Connecting to model host…" : "Checking model files…"
        installation = Task { [self] in
            defer { installing = false; installation = nil; installToken = nil; downloading = false }
            do {
                try await installer.install(downloadMissing: downloadMissing) { [weak self] progress in
                    Task { @MainActor in
                        guard let self, self.installToken == token else { return }
                        self.status = progress.label
                        self.installFraction = Double(progress.completed) / Double(progress.total)
                        self.installBytes = progress.completed
                        self.downloading = progress.downloading
                        let now = ProcessInfo.processInfo.systemUptime
                        if progress.downloading {
                            if let previous = self.speedSamples.last, progress.completed > previous.bytes {
                                self.lastDownloadActivity = Date()
                            }
                            self.speedSamples.append((now, progress.completed))
                            while self.speedSamples.count > 2 && now - self.speedSamples[1].time > 3 {
                                self.speedSamples.removeFirst()
                            }
                            if let first = self.speedSamples.first, now - first.time > 0.1 {
                                self.downloadSpeed = Double(max(0, progress.completed - first.bytes)) / (now - first.time)
                            }
                        } else { self.speedSamples = []; self.downloadSpeed = 0 }
                    }
                }
                ready = true
                status = "Ready · all inference stays on this iPhone"
            } catch is CancellationError { status = "Download paused. Tap download to resume." }
            catch { status = error.localizedDescription }
        }
    }
    func pauseInstall() { installation?.cancel() }
    func removeModels() async {
        guard !busy, !installing else { return }
        ready = false
        status = "Removing model files…"
        do { try await installer.remove(); installFraction = 0; status = "Model removed" }
        catch { self.error = error.localizedDescription }
    }
    func setReference(data: Data) async {
        guard !busy else { return }
        do {
            let normalized = try await Task.detached(priority: .userInitiated) { try ReferenceImage.normalize(data) }.value
            guard !busy else { return }
            reference = normalized.preview; referenceRGB = normalized.rgb
        } catch { self.error = error.localizedDescription }
    }
    func clearReference() { reference = nil; referenceRGB = nil }
    func cancel(reason: String = "Cancelled") {
        guard busy else { return }
        cancelled = true; cancellationReason = reason
        status = "Stopping after the current native operation…"
        engine.cancel()
    }
    func backgrounded() {
        pauseInstall()
        guard busy else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Finish Qwen operation") { [weak self] in
            Task { @MainActor in
                self?.cancel(reason: "Stopped because background execution expired.")
                self?.endBackgroundTask()
            }
        }
        if backgroundTask == .invalid { cancel(reason: "iOS did not grant background execution time.") }
    }
    func foregrounded() { endBackgroundTask() }
    private func endBackgroundTask() {
        if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid }
    }
    private func beginJob() -> Bool {
        guard !busy, !installing, ready else { return false }
        guard ProcessInfo.processInfo.thermalState.rawValue < ProcessInfo.ThermalState.serious.rawValue else {
            error = "The phone is warm. Allow it to cool before generating."; return false
        }
        busy = true; cancelled = false; cancellationReason = "Cancelled"; error = nil
        return true
    }
    func generate() async {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, beginJob() else { return }
        defer { busy = false; endBackgroundTask() }
        do { try await run(prompt: text, seed: Int64.random(in: 0...Int64(Int32.max)), reference: referenceRGB) }
        catch is CancellationError { status = cancellationReason }
        catch { self.error = error.localizedDescription; status = "Generation failed" }
    }
    private func run(prompt: String, seed: Int64, reference: Data?, suite: UUID? = nil, cancelAtStep: Int? = nil) async throws {
        guard !cancelled else { throw CancellationError() }
        guard await installer.ready() else { ready = false; throw QwenError.message("Model files are missing; verify installation again") }
        guard !cancelled else { throw CancellationError() }
        guard ProcessInfo.processInfo.thermalState.rawValue < ProcessInfo.ThermalState.serious.rawValue else {
            throw QwenError.message("Phone too warm to start the next generation. Let it cool and retry.")
        }
        let token = UUID()
        activeRunToken = token
        defer { activeRunToken = nil }
        engine.prepare()
        step = 0; totalSteps = 0
        try diagnostics.begin(editing: reference != nil, seed: seed, manifest: manifest, suiteID: suite)
        do {
            let output = try await engine.generate(prompt: prompt, seed: seed, reference: reference, manifest: manifest, directory: modelDirectory) { [weak self] stage, step, total in
                Task { @MainActor in
                    guard let self, self.activeRunToken == token, !self.cancelled else { return }
                    self.status = stage; self.step = step; self.totalSteps = total
                    self.diagnostics.stage(stage)
                    if let cancelAtStep, step >= cancelAtStep { self.engine.cancel() }
                }
            }
            guard !cancelled, cancelAtStep == nil else {
                if cancelAtStep != nil { throw QwenError.message("Cancellation test failed: generation completed") }
                throw CancellationError()
            }
            let record = GenerationRecord(id: UUID(), created: Date(), prompt: prompt, seed: seed, modelID: manifest.id,
                                          editing: reference != nil, seconds: output.seconds, width: 512, height: 512, steps: 40, guidance: 6, sampler: "Euler / model default schedule")
            try await history.save(png: output.png, record: record)
            result = UIImage(data: output.png); resultURL = history.imageURL(record.id)
            try diagnostics.finish(status: "completed; visual review required", resultID: record.id)
            await refreshHistory()
            status = "Finished in \(Int(output.seconds)) seconds"
        } catch {
            try diagnostics.finish(status: error is CancellationError ? "cancelled" : "failed: \(error.localizedDescription)")
            throw error
        }
    }
    func runSuite() async {
        guard let referenceRGB else { error = "Choose a reference photo in Create first."; return }
        guard beginJob() else { return }
        defer { busy = false; endBackgroundTask() }
        let suite = UUID()
        do {
            for index in 0..<3 {
                suiteStatus = "Text generation \(index + 1) of 3"
                try await run(prompt: "A red ceramic teapot on a wooden table, realistic photograph", seed: Int64(42 + index), reference: nil, suite: suite)
            }
            for index in 0..<3 {
                suiteStatus = "Photo edit \(index + 1) of 3"
                try await run(prompt: "Turn this image into a watercolor painting, preserving the subject and composition", seed: Int64(45 + index), reference: referenceRGB, suite: suite)
            }
            suiteStatus = "Testing cancellation at step 2"
            do {
                try await run(prompt: "A blue ceramic cup", seed: 48, reference: nil, suite: suite, cancelAtStep: 2)
                throw QwenError.message("Cancellation was not observed")
            } catch is CancellationError { if cancelled { throw CancellationError() } }
            suiteStatus = "Testing restart after cancellation"
            try await run(prompt: "A blue ceramic cup", seed: 49, reference: nil, suite: suite)
            suiteStatus = "Runtime checks completed. Inspect the seven outputs for prompt-following and visible edits, then repeat in airplane mode."
        } catch is CancellationError { suiteStatus = "Suite cancelled · \(cancellationReason)" }
        catch { suiteStatus = "Suite stopped: \(error.localizedDescription)"; self.error = error.localizedDescription }
    }
    func open(_ record: GenerationRecord) {
        prompt = record.prompt
        resultURL = history.imageURL(record.id)
        result = UIImage(contentsOfFile: resultURL!.path)
        clearReference(); selectedTab = 0
    }
    func reuse(_ record: GenerationRecord) async {
        do { try await setReference(data: Data(contentsOf: history.imageURL(record.id))); selectedTab = 0 }
        catch { self.error = error.localizedDescription }
    }
    func delete(_ record: GenerationRecord) async {
        do {
            try await history.delete(record.id)
            if resultURL == history.imageURL(record.id) { resultURL = nil; result = nil }
            await refreshHistory()
        } catch { self.error = error.localizedDescription }
    }
    func saveToPhotos() async {
        guard let resultURL else { return }
        let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard authorization == .authorized || authorization == .limited else { error = "Allow photo additions in Settings to save images."; return }
        do {
            try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: resultURL) }
            status = "Saved to Photos"
        } catch { self.error = error.localizedDescription }
    }
}
