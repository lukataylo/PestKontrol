import Foundation
import SwiftData

/// One index entry: what the sentry saw at a moment. Written every ~1–4 s
/// (denser when something is happening) and searched by the Ask tab.
@Model
final class Moment {
    var date: Date
    /// Lowercase "label score" pairs, e.g. "fox 0.98 canine 0.97".
    var labels: String
    var speciesRaw: String?
    var confidence: Double
    var guardedRaw: String?
    var guardedConfidence: Double
    var motion: Bool
    var dark: Bool
    var thumb: String?
    /// One-line description from the on-device vision model, when available.
    var caption: String?

    init(date: Date, labels: String, species: Species?, confidence: Double, guarded: Guarded?,
         guardedConfidence: Double, motion: Bool, dark: Bool, thumb: String?) {
        self.date = date
        self.labels = labels
        self.speciesRaw = species?.rawValue
        self.confidence = confidence
        self.guardedRaw = guarded?.rawValue
        self.guardedConfidence = guardedConfidence
        self.motion = motion
        self.dark = dark
        self.thumb = thumb
    }

    var species: Species? { speciesRaw.flatMap(Species.init) }
    var guarded: Guarded? { guardedRaw.flatMap(Guarded.init) }
}

enum MomentStore {
    static let directory: URL = {
        let dir = URL.applicationSupportDirectory.appending(path: "Moments", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func save(_ data: Data) -> String? {
        let name = UUID().uuidString + ".jpg"
        do {
            try data.write(to: url(for: name))
            return name
        } catch {
            return nil
        }
    }

    static func url(for name: String) -> URL {
        directory.appending(path: name)
    }

    static func delete(_ name: String?) {
        guard let name else { return }
        try? FileManager.default.removeItem(at: url(for: name))
    }
}

/// Footage and index settings, kept apart from detection settings.
struct RecallSettings: Codable, Equatable {
    var record = true
    var keepHours = 12

    /// The index is tiny next to video, so it outlives the footage.
    var indexHours: Int { max(keepHours, 48) }

    private static let key = "shoo.recall.v1"

    static func load() -> RecallSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(RecallSettings.self, from: data)
        else { return RecallSettings() }
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
