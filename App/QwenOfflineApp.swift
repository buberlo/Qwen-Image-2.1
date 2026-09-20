import SwiftUI

@main
struct QwenOfflineApp: App {
    private let startup: Result<AppModel, Error>
    init() { startup = Result { try AppModel() } }
    var body: some Scene {
        WindowGroup {
            switch startup {
            case .success(let model): RootView(model: model)
            case .failure(let error): ContentUnavailableView("Unable to start", systemImage: "exclamationmark.triangle", description: Text(error.localizedDescription))
            }
        }
    }
}

struct RootView: View {
    @StateObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        TabView(selection: $model.selectedTab) {
            CreateView(model: model).tabItem { Label("Create", systemImage: "sparkles") }.tag(0)
            HistoryView(model: model).tabItem { Label("History", systemImage: "photo.stack") }.tag(1)
            ModelView(model: model).tabItem { Label("Model", systemImage: "internaldrive") }.tag(2)
            DiagnosticsView(model: model, diagnostics: model.diagnostics).tabItem { Label("Device test", systemImage: "waveform.path.ecg") }.tag(3)
        }
        .tint(.indigo)
        .task { await model.refreshHistory(); model.verifyModels() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.backgrounded() }
            if phase == .active { model.foregrounded() }
        }
        .alert("Qwen Offline", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}
