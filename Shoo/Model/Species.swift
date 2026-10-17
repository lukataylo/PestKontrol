import Foundation

/// Pests SHOO can target. Label weights map classifier identifiers to a species.
enum Species: String, CaseIterable, Codable, Identifiable, Hashable {
    case pigeon, gull, fox, rat, squirrel

    var id: String { rawValue }
    var code: String { rawValue.uppercased() }

    var short: String {
        switch self {
        case .pigeon: "PGN"
        case .gull: "GUL"
        case .fox: "FOX"
        case .rat: "RAT"
        case .squirrel: "SQR"
        }
    }

    var labels: [String: Float] {
        switch self {
        case .pigeon: ["pigeon": 1, "dove": 1]
        case .gull: ["gull": 1, "seagull": 1]
        case .fox: ["fox": 1]
        case .rat: ["rat": 1, "rodent": 0.85]
        case .squirrel: ["squirrel": 1]
        }
    }

    var note: String {
        switch self {
        case .pigeon: "Pigeon, dove"
        case .gull: "Herring gull, seagull"
        case .fox: "Red fox · mostly night"
        case .rat: "Rat, rodent · mostly night"
        case .squirrel: "Grey squirrel"
        }
    }

    var defaultPattern: SoundPattern {
        switch self {
        case .pigeon, .gull: .hawk
        case .fox: .clap
        case .rat: .sweep
        case .squirrel: .pulse
        }
    }
}

/// Never fire while one of these is in frame.
enum Guarded: String, CaseIterable, Codable {
    case person, cat, dog, hedgehog

    var code: String { rawValue.uppercased() }

    var labels: [String] {
        switch self {
        case .person: ["person", "people", "adult", "child", "baby"]
        case .cat: ["cat", "adult_cat", "kitten"]
        case .dog: ["dog", "puppy", "bulldog", "sheepdog"]
        case .hedgehog: ["hedgehog"]
        }
    }
}

enum SoundPattern: String, Codable, CaseIterable, Identifiable {
    case hawk, clap, sweep, pulse, mix

    static let voices: [SoundPattern] = [.hawk, .clap, .sweep, .pulse]

    var id: String { rawValue }
    var code: String { rawValue.uppercased() }

    var next: SoundPattern {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

enum Outcome: String, Codable {
    case fired, logged, quiet
}
