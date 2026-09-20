import SwiftUI
import PhotosUI

struct CreateView: View {
    @ObservedObject var model: AppModel
    @State private var photo: PhotosPickerItem?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label("ON YOUR IPHONE", systemImage: "iphone")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text("Imagine something.").font(.largeTitle.bold())
                    Text("Create from words, or bring a photo and describe a change.").foregroundStyle(.secondary)
                    TextField("Describe your image or edit…", text: $model.prompt, axis: .vertical)
                        .lineLimit(4...8).padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 18))
                        .disabled(model.busy)
                        .accessibilityLabel("Image prompt")
                    if let reference = model.reference {
                        HStack(alignment: .top) {
                            Image(uiImage: reference).resizable().scaledToFit().frame(width: 110, height: 110).clipShape(RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Reference photo").font(.headline)
                                Text("Your prompt describes the edit.").font(.caption).foregroundStyle(.secondary)
                                Button("Remove", role: .destructive) { model.clearReference(); photo = nil }.disabled(model.busy)
                            }
                        }
                    }
                    PhotosPicker("Add or replace photo", selection: $photo, matching: .images, photoLibrary: .shared())
                        .disabled(model.busy)
                    HStack {
                        Label("512 × 512", systemImage: "square")
                        Spacer()
                        Text("Qwen-Image-2.1")
                    }.font(.caption).foregroundStyle(.secondary)
                    if model.busy {
                        if model.totalSteps > 0 { ProgressView(value: Double(model.step), total: Double(model.totalSteps)) }
                        else { ProgressView() }
                        Button("Cancel", role: .destructive) { model.cancel() }.buttonStyle(.bordered)
                    } else {
                        Button { Task { await model.generate() } } label: {
                            Label(model.reference == nil ? "Generate image" : "Edit photo", systemImage: "sparkles")
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                        }.buttonStyle(.borderedProminent)
                            .disabled(!model.ready || model.installing || model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Text(model.status).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("generationStatus")
                    if !model.ready && !model.installing { Button("Set up model") { model.selectedTab = 2 } }
                    if let result = model.result {
                        Image(uiImage: result).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 18))
                            .accessibilityLabel("Generated image")
                        HStack {
                            Button { Task { await model.saveToPhotos() } } label: { Label("Save", systemImage: "square.and.arrow.down") }
                            Spacer()
                            if let url = model.resultURL { ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") } }
                        }.buttonStyle(.bordered)
                    }
                    Text("Experimental · device feasibility has not been established. Generation may take several minutes.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(24)
            }
            .navigationTitle("Pocket Canvas").navigationBarTitleDisplayMode(.inline)
            .onChange(of: photo) { _, item in
                Task {
                    do { if let data = try await item?.loadTransferable(type: Data.self) { await model.setReference(data: data) } }
                    catch { model.error = error.localizedDescription }
                }
            }
        }
    }
}

struct HistoryView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        NavigationStack {
            Group {
                if model.records.isEmpty {
                    ContentUnavailableView("Your images live here", systemImage: "photo.stack", description: Text("Generated images and their prompts are saved locally."))
                } else {
                    List(model.records) { record in
                        HStack(alignment: .top) {
                            if let image = UIImage(contentsOfFile: model.history.imageURL(record.id).path) {
                                Image(uiImage: image).resizable().scaledToFill().frame(width: 76, height: 76).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text(record.prompt).lineLimit(3)
                                Text("\(record.editing ? "Edit" : "Generation") · \(Int(record.seconds))s · seed \(record.seed)").font(.caption).foregroundStyle(.secondary)
                                Text(record.created, style: .date).font(.caption2).foregroundStyle(.secondary)
                                HStack {
                                    Button("Open") { model.open(record) }
                                    Button("Use as input") { Task { await model.reuse(record) } }
                                }.buttonStyle(.borderless).disabled(model.busy)
                            }
                        }.swipeActions {
                            Button("Delete", role: .destructive) { Task { await model.delete(record) } }.disabled(model.busy)
                        }
                    }
                }
            }.navigationTitle("History")
        }
    }
}

struct ModelView: View {
    @ObservedObject var model: AppModel
    @State private var confirmRemoval = false
    @State private var notices = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Qwen-Image-2.1", systemImage: "cpu").font(.headline)
                    Text("One initial download. Prompts and photos stay on your iPhone during inference.")
                    LabeledContent("Download size", value: ByteCountFormatter.string(fromByteCount: model.manifest.totalBytes, countStyle: .file))
                    Text("Keep the app open during setup. Downloads pause in the background and resume from saved chunks.").font(.footnote).foregroundStyle(.secondary)
                    if model.installing {
                        ProgressView(value: model.installFraction)
                        LabeledContent("Received", value: "\(ByteCountFormatter.string(fromByteCount: model.installBytes, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: model.manifest.totalBytes, countStyle: .file))")
                            .monospacedDigit()
                        if model.downloading {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                let idle = context.date.timeIntervalSince(model.lastDownloadActivity)
                                let speed = idle > 3 ? 0 : model.downloadSpeed
                                LabeledContent("Download speed", value: "\(ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file))/s")
                                    .monospacedDigit()
                                if idle > 3 {
                                    Text("Waiting for data · \(Int(idle)) seconds since last activity")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            HStack { ProgressView(); Text("Checking file integrity…").font(.caption) }
                        }
                        Button("Pause") { model.pauseInstall() }
                    } else if model.ready {
                        Label("Verified · available offline", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Button("Verify files again") { model.verifyModels() }.disabled(model.busy)
                    } else {
                        Button("Download / resume model") { model.startInstall() }.disabled(model.busy)
                    }
                    Text(model.status).font(.caption)
                } header: { Text("Local model") }
                Section("Components") {
                    ForEach(model.manifest.files) { file in
                        VStack(alignment: .leading) {
                            Text(file.role.capitalized)
                            Text(file.name).font(.caption).foregroundStyle(.secondary)
                            Text(ByteCountFormatter.string(fromByteCount: file.bytes, countStyle: .file)).font(.caption2)
                        }
                    }
                }
                Section {
                    Button("Licenses and sources") { notices = true }
                    Button("Remove model files", role: .destructive) { confirmRemoval = true }.disabled(model.busy || model.installing)
                    Text("Removing model files preserves your generated images.").font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("Model")
                .confirmationDialog("Remove all downloaded model files?", isPresented: $confirmRemoval, titleVisibility: .visible) {
                    Button("Remove model", role: .destructive) { Task { await model.removeModels() } }
                }
                .sheet(isPresented: $notices) {
                    NavigationStack {
                        ScrollView {
                            Text((Bundle.main.url(forResource: "NOTICES", withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) }) ?? "Notices unavailable")
                                .font(.footnote).textSelection(.enabled).padding()
                        }.navigationTitle("Licenses").toolbar { Button("Done") { notices = false } }
                    }
                }
        }
    }
}

struct DiagnosticsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var diagnostics: Diagnostics
    var body: some View {
        NavigationStack {
            List {
                Section("Physical-device feasibility") {
                    Text("Run three generations, three photo edits, cancellation, then a restart. Add a reference photo in Create first. Keep the phone unlocked and the app in the foreground.")
                    Text("This test can take a long time. Memory is sampled every second; operating-system termination still requires device logs to diagnose.").font(.footnote).foregroundStyle(.secondary)
                    Button("Run device test suite") { Task { await model.runSuite() } }.disabled(!model.ready || model.busy || model.installing)
                    if model.busy { Button("Cancel", role: .destructive) { model.cancel() } }
                    Text(model.suiteStatus).font(.caption)
                    if !diagnostics.runs.isEmpty { ShareLink("Export diagnostics", item: diagnostics.exportURL) }
                }
                Section("Runs · newest first") {
                    ForEach(diagnostics.runs) { run in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(run.editing ? "Photo edit" : "Text generation").font(.headline)
                            Text(run.status)
                            Text("\(Int(run.duration))s · peak \(ByteCountFormatter.string(fromByteCount: Int64(run.peakFootprint), countStyle: .memory))").font(.caption)
                            Text("\(run.device) · iOS \(run.os) · \(run.stage)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }.navigationTitle("Device test")
        }
    }
}
