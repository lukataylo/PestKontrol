import Foundation

/// The four numbers that actually drive detection. Users pick a Mode;
/// only Fine-tune exposes these directly.
struct Tuning: Codable, Equatable {
    var threshold: Double
    var confirmFrames: Int
    var cooldown: Double
    var gain: Double
}

enum Mode: String, Codable, CaseIterable, Identifiable {
    case gentle, steady, fierce, custom

    static let presets: [Mode] = [.gentle, .steady, .fierce]

    var id: String { rawValue }
    var code: String { self == .steady ? "NORMAL" : rawValue.uppercased() }

    var level: Int {
        switch self {
        case .gentle: 1
        case .steady: 2
        case .fierce: 3
        case .custom: 0
        }
    }

    var blurb: String {
        switch self {
        case .gentle: "Waits until sure. Softer, rarer."
        case .steady: "Balanced. The good default."
        case .fierce: "Acts fast. Loud and often."
        case .custom: "Fine-tuned by you."
        }
    }

    var preset: Tuning? {
        switch self {
        // Calibrated against Apple Vision: across 180 animal-free crops no pest label
        // passed 0.05, while real birds often score only 0.25–0.6.
        case .gentle: Tuning(threshold: 0.45, confirmFrames: 4, cooldown: 120, gain: 0.7)
        case .steady: Tuning(threshold: 0.3, confirmFrames: 3, cooldown: 45, gain: 0.9)
        case .fierce: Tuning(threshold: 0.2, confirmFrames: 2, cooldown: 20, gain: 1.0)
        case .custom: nil
        }
    }
}

struct SentrySettings: Codable, Equatable {
    var enabled: Set<Species> = Set(Species.allCases)
    var patterns: [Species: SoundPattern] = [:]
    var mode: Mode = .steady
    var custom: Tuning = Mode.steady.preset!
    var protectLock = true
    var quietHours = false
    var quietStart = 22
    var quietEnd = 7

    var tuning: Tuning { mode.preset ?? custom }

    /// Edit the live tuning. Snaps back to a preset if the result matches one.
    mutating func tune(_ change: (inout Tuning) -> Void) {
        var t = tuning
        change(&t)
        custom = t
        mode = Mode.presets.first { $0.preset == t } ?? .custom
    }

    func pattern(for species: Species) -> SoundPattern {
        patterns[species] ?? species.defaultPattern
    }

    func isQuiet(at date: Date) -> Bool {
        guard quietHours else { return false }
        let h = Calendar.current.component(.hour, from: date)
        return quietStart <= quietEnd
            ? (h >= quietStart && h < quietEnd)
            : (h >= quietStart || h < quietEnd)
    }

    private static let key = "shoo.settings.v2"

    static func load() -> SentrySettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(SentrySettings.self, from: data)
        else { return SentrySettings() }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
