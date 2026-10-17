import Foundation
import UserNotifications

/// "When <trigger> [between hours], then <actions>." Written in plain language,
/// stored as structure.
struct Rule: Codable, Identifiable, Equatable {
    enum Trigger: Codable, Equatable {
        case pest([Species])   // empty = any pest
        case person
        case friend
        case motion
        case keyword(String)
    }

    enum Action: String, Codable, CaseIterable {
        case deter, lamp, notify, webhook

        var code: String { rawValue.uppercased() }
        var icon: [String] {
            switch self {
            case .deter: Glyphs.speaker
            case .lamp: Glyphs.bulb
            case .notify: Glyphs.bolt
            case .webhook: Glyphs.arrow
            }
        }
    }

    var id = UUID()
    var enabled = true
    var text: String
    var trigger: Trigger
    var fromHour: Int?
    var toHour: Int?
    var actions: [Action]
    var webhook: String?
    var cooldown: Double = 60

    var whenText: String {
        let what: String
        switch trigger {
        case .pest(let s): what = s.isEmpty ? "ANY PEST" : s.map(\.code).joined(separator: " / ")
        case .person: what = "PERSON"
        case .friend: what = "CAT / DOG / HEDGEHOG"
        case .motion: what = "MOVEMENT"
        case .keyword(let k): what = "\"\(k.uppercased())\""
        }
        guard let f = fromHour, let t = toHour else { return what }
        return what + String(format: " · %02d–%02d", f, t)
    }

    func active(at date: Date) -> Bool {
        guard enabled else { return false }
        guard let f = fromHour, let t = toHour, f != t else { return true }
        let h = Calendar.current.component(.hour, from: date)
        return f < t ? (h >= f && h < t) : (h >= f || h < t)
    }
}

enum RuleStore {
    private static let key = "shoo.rules.v1"

    static func load() -> [Rule] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let rules = try? JSONDecoder().decode([Rule].self, from: data)
        else { return [] }
        return rules
    }

    static func save(_ rules: [Rule]) {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// Plain language → Rule. Uses the on-device model when present, else a keyword parser.
enum RuleParser {
    static func parse(_ text: String) async -> Rule {
        if let d = await Intelligence.rule(from: text) {
            let species = d.species.compactMap { Species(rawValue: $0.lowercased()) }
            let trigger: Rule.Trigger = switch d.trigger {
            case "person": .person
            case "friend": .friend
            case "motion": .motion
            case "keyword" where !d.keyword.isEmpty: .keyword(d.keyword.lowercased())
            default: .pest(species)
            }
            let actions = d.actions.compactMap { Rule.Action(rawValue: $0.lowercased()) }
            var rule = Rule(text: text, trigger: trigger,
                            fromHour: d.fromHour >= 0 ? d.fromHour : nil,
                            toHour: d.toHour >= 0 ? d.toHour : nil,
                            actions: actions.isEmpty ? [.notify] : actions)
            rule.webhook = url(in: text)
            if rule.webhook != nil, !rule.actions.contains(.webhook) { rule.actions.append(.webhook) }
            return rule
        }
        return keywords(text)
    }

    /// Deterministic fallback, good for the common phrasings.
    static func keywords(_ text: String) -> Rule {
        let s = text.lowercased()
        let has = { (words: [String]) in words.contains { s.contains($0) } }

        let species = Species.allCases.filter { sp in
            s.contains(sp.rawValue) || (sp == .gull && s.contains("seagull")) || (sp == .rat && (s.contains("mice") || s.contains("mouse")))
        }
        let trigger: Rule.Trigger
        if !species.isEmpty || has(["pest", "animal", "bird"]) {
            trigger = .pest(has(["bird"]) && species.isEmpty ? [.pigeon, .gull] : species)
        } else if has(["person", "someone", "somebody", "people", "human", "anyone"]) {
            trigger = .person
        } else if has(["cat", "dog", "hedgehog", "pet"]) {
            trigger = .friend
        } else {
            trigger = .motion
        }

        var actions: [Rule.Action] = []
        if has(["scare", "shoo", "sound", "noise", "deter", "chase"]) { actions.append(.deter) }
        if has(["light", "lamp", "flash", "torch", "strobe"]) { actions.append(.lamp) }
        if has(["notify", "alert", "tell me", "ping", "let me know", "message", "warn"]) { actions.append(.notify) }
        let hook = url(in: text)
        if hook != nil || has(["webhook", "home assistant"]) { actions.append(.webhook) }
        if actions.isEmpty { actions = [.notify] }

        var from: Int?, to: Int?
        if has(["at night", "overnight", "after dark"]) { (from, to) = (21, 6) }
        if let (f, t) = hours(in: s) { (from, to) = (f, t) }

        var rule = Rule(text: text, trigger: trigger, fromHour: from, toHour: to, actions: actions)
        rule.webhook = hook
        return rule
    }

    /// "after 10pm", "between 9pm and 6am", "from 22 to 7".
    private static func hours(in raw: String) -> (Int, Int)? {
        let s = raw.replacingOccurrences(of: "midnight", with: "0am").replacingOccurrences(of: "noon", with: "12pm")
        let pattern = #/(\d{1,2})\s*(am|pm)?/#
        let found = s.matches(of: pattern).compactMap { m -> Int? in
            guard var h = Int(m.output.1), h <= 24 else { return nil }
            if m.output.2 == "pm", h < 12 { h += 12 }
            if m.output.2 == "am", h == 12 { h = 0 }
            return h % 24
        }
        if found.count >= 2, s.contains("between") || s.contains("from") { return (found[0], found[1]) }
        if let h = found.first, s.contains("after") { return (h, 6) }
        if let h = found.first, s.contains("before") { return (6, h) }
        return nil
    }

    private static func url(in text: String) -> String? {
        text.split(separator: " ").map(String.init).first { $0.hasPrefix("http://") || $0.hasPrefix("https://") }
    }
}

/// What a rule did, for the Ask tab's recent list.
struct RuleFiring: Identifiable {
    let id = UUID()
    let date: Date
    let rule: String
    let what: String
}

enum Notifier {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func send(_ title: String, _ body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    /// POSTs a small JSON event. Only to URLs the user typed into a rule.
    static func webhook(_ urlString: String, payload: [String: Any]) {
        guard let url = URL(string: urlString), let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        URLSession.shared.dataTask(with: request).resume()
    }
}

/// Shows banners while the app is open (it usually is — it's the camera).
final class ForegroundNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ForegroundNotifications()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
