import Foundation
import SwiftData

@Model
final class Sighting {
    var date: Date
    var speciesRaw: String
    var confidence: Double
    var outcomeRaw: String
    var patternRaw: String?
    var imageFile: String?
    var lowLight: Bool

    init(date: Date, species: Species, confidence: Double, outcome: Outcome,
         pattern: SoundPattern?, imageFile: String?, lowLight: Bool) {
        self.date = date
        self.speciesRaw = species.rawValue
        self.confidence = confidence
        self.outcomeRaw = outcome.rawValue
        self.patternRaw = pattern?.rawValue
        self.imageFile = imageFile
        self.lowLight = lowLight
    }

    var species: Species? { Species(rawValue: speciesRaw) }
    var outcome: Outcome { Outcome(rawValue: outcomeRaw) ?? .logged }
    var pattern: SoundPattern? { patternRaw.flatMap(SoundPattern.init) }
}

/// Snapshots live as JPEGs in Application Support, never in the cloud.
enum SightingStore {
    static let directory: URL = {
        let dir = URL.applicationSupportDirectory.appending(path: "Sightings", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func save(_ data: Data) -> String? {
        let name = UUID().uuidString + ".jpg"
        do {
            try data.write(to: url(for: name), options: .completeFileProtectionUntilFirstUserAuthentication)
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
