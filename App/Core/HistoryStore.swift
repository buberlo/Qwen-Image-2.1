import Foundation

struct GenerationRecord: Codable, Identifiable, Sendable {
    let id: UUID
    let created: Date
    let prompt: String
    let seed: Int64
    let modelID: String
    let editing: Bool
    let seconds: Double
    let width: Int
    let height: Int
    let steps: Int
    let guidance: Double
    let sampler: String
}

actor HistoryStore {
    let directory: URL
    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    func save(png: Data, record: GenerationRecord) throws {
        let folder = directory.appendingPathComponent(record.id.uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            try png.write(to: folder.appendingPathComponent("image.png"), options: .atomic)
            try JSONEncoder().encode(record).write(to: folder.appendingPathComponent("record.json"), options: .atomic)
        } catch { try? FileManager.default.removeItem(at: folder); throw error }
    }
    func list() throws -> [GenerationRecord] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .compactMap { folder in
                guard FileManager.default.fileExists(atPath: folder.appendingPathComponent("image.png").path),
                      let data = try? Data(contentsOf: folder.appendingPathComponent("record.json")) else { return nil }
                return try? JSONDecoder().decode(GenerationRecord.self, from: data)
            }.sorted { $0.created > $1.created }
    }
    func delete(_ id: UUID) throws { try FileManager.default.removeItem(at: directory.appendingPathComponent(id.uuidString)) }
    nonisolated func imageURL(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString).appendingPathComponent("image.png") }
}
