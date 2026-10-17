import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case nothing, slasher

    static let storageKey = "shoo.theme"

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }

    static var saved: AppTheme {
        UserDefaults.standard.string(forKey: storageKey).flatMap(AppTheme.init) ?? .nothing
    }
}

/// Palette for the active theme.
/// `current` is set before the theme's AppStorage changes, and RootView rebuilds its
/// tree with `.id(theme)`, so every view and Canvas reads the new values.
enum Theme {
    static var current: AppTheme = AppTheme.saved
    static var slasher: Bool { current == .slasher }

    /// Nothing: black, white, one red. Slasher: soot, bone, blood.
    static var black: Color { slasher ? Color(red: 0.035, green: 0.031, blue: 0.027) : .black }
    static var panel: Color { slasher ? Color(red: 0.055, green: 0.049, blue: 0.043) : Color(white: 0.065) }
    static var ink: Color { slasher ? Color(red: 0.93, green: 0.9, blue: 0.83) : .white }
    static var line: Color { ink.opacity(slasher ? 0.2 : 0.10) }
    static var dim: Color { ink.opacity(0.6) }
    static var ghost: Color { ink.opacity(0.22) }
    static var red: Color {
        slasher ? Color(red: 0.89, green: 0.235, blue: 0.19) : Color(red: 215 / 255, green: 25 / 255, blue: 33 / 255)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

enum Fmt {
    static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd MMM · HH:mm"
        return f
    }()
}
