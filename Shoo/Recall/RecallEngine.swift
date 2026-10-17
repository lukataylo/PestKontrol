import Foundation
import SwiftData

/// A stretch of footage worth showing: a search hit or a spotted event.
struct Clip: Identifiable, Hashable {
    enum Kind: Hashable {
        case pest(Species), person, friend(Guarded), movement, lightsDown, lightsUp, match
    }

    var id: String { "\(title)-\(start.timeIntervalSince1970)" }
    var kind: Kind
    var start: Date
    var end: Date
    var score: Double
    var thumb: String?
    var caption: String?
    var note: String?

    var title: String {
        switch kind {
        case .pest(let s): s.code
        case .person: "PERSON"
        case .friend(let g): g.code
        case .movement: "MOVEMENT"
        case .lightsDown: "LIGHTS DOWN"
        case .lightsUp: "LIGHTS UP"
        case .match: "MATCH"
        }
    }

    var timeRange: String {
        let a = Fmt.clock.string(from: start), b = Fmt.clock.string(from: end)
        return a == b ? a : "\(a)–\(b)"
    }

    var sprite: [String] {
        switch kind {
        case .pest(let s): Pets.sprite(s)
        case .person: Pets.sprite(.person)
        case .friend(let g): Pets.sprite(g)
        case .movement, .match: Glyphs.eye
        case .lightsDown: Glyphs.moon
        case .lightsUp: Glyphs.bulb
        }
    }
}

/// Search, ask and spot over the moment index. Pure functions over a context.
enum RecallEngine {
    // MARK: Search

    struct Query {
        var keywords: [String]
        var window: DateInterval
        var motionOnly: Bool
        /// No subject named ("what happened?") — rank by how much was going on.
        var anything: Bool
    }

    static func parse(_ text: String, now: Date = .now, horizonHours: Int) async -> Query {
        let lower = text.lowercased()
        var words = Set(tokens(lower).flatMap { synonyms[$0] ?? [$0] }).subtracting(stopwords)
        if let more = await Intelligence.keywords(for: text) {
            words.formUnion(more.flatMap { synonyms[$0] ?? [$0] })
        }
        let motion = words.contains("motion")
        words.remove("motion")
        let window = TimePhrase.window(in: lower, now: now)
            ?? DateInterval(start: now.addingTimeInterval(-Double(horizonHours) * 3600), end: now)
        return Query(keywords: Array(words).sorted(), window: window, motionOnly: motion,
                     anything: words.isEmpty || words.isSubset(of: ["happened", "anything", "activity", "everything", "see", "saw"]))
    }

    static func search(_ q: Query, in context: ModelContext, limit: Int = 24) -> [Clip] {
        let moments = fetch(q.window, context)
        var hits: [(Moment, Double)] = []
        for m in moments {
            let s = score(m, q)
            if s > 0 { hits.append((m, s)) }
        }
        return group(hits, gap: 15).sorted { $0.score > $1.score }.prefix(limit).sorted { $0.start > $1.start }
    }

    private static func score(_ m: Moment, _ q: Query) -> Double {
        if q.motionOnly && !m.motion { return 0 }
        if q.anything {
            return max(m.confidence, m.guardedConfidence * 0.8, m.motion ? 0.3 : 0, m.caption == nil ? 0 : 0.2)
        }
        let labels = parsedLabels(m.labels)
        let caption = m.caption?.lowercased() ?? ""
        var total = 0.0
        for k in q.keywords {
            var best = labels[k] ?? 0
            if m.speciesRaw == k { best = max(best, m.confidence) }
            if m.guardedRaw == k { best = max(best, m.guardedConfidence) }
            if !caption.isEmpty, caption.contains(k) { best = max(best, 0.7) }
            total += best
        }
        return total >= 0.15 ? total : 0
    }

    // MARK: Spot

    /// Turns the raw index into the handful of things a person would call "events".
    static func spot(_ window: DateInterval, in context: ModelContext, pestThreshold: Double) -> [Clip] {
        let moments = fetch(window, context)
        var clips: [Clip] = []

        func runs(_ kind: Clip.Kind, where test: (Moment) -> Double?) {
            var current: Clip?
            var bestScore = 0.0
            for m in moments {
                guard let s = test(m) else { continue }
                if var c = current, m.date.timeIntervalSince(c.end) <= 20 {
                    c.end = m.date
                    if s >= bestScore, m.thumb != nil {
                        bestScore = s
                        c.thumb = m.thumb
                        c.caption = m.caption ?? c.caption
                    }
                    c.score = max(c.score, s)
                    current = c
                } else {
                    if let c = current { clips.append(c) }
                    bestScore = s
                    current = Clip(kind: kind, start: m.date, end: m.date, score: s, thumb: m.thumb, caption: m.caption)
                }
            }
            if let c = current { clips.append(c) }
        }

        for s in Species.allCases {
            runs(.pest(s)) { $0.speciesRaw == s.rawValue && $0.confidence >= pestThreshold ? $0.confidence : nil }
        }
        runs(.person) { $0.guardedRaw == Guarded.person.rawValue && $0.guardedConfidence >= 0.5 ? $0.guardedConfidence : nil }
        for g in [Guarded.cat, .dog, .hedgehog] {
            runs(.friend(g)) { $0.guardedRaw == g.rawValue && $0.guardedConfidence >= 0.5 ? $0.guardedConfidence : nil }
        }
        // Movement nobody explained — only if it lasted a moment or two.
        runs(.movement) { m in
            m.motion && m.confidence < pestThreshold && m.guardedConfidence < 0.5 ? 0.3 : nil
        }
        clips.removeAll { $0.kind == .movement && $0.end.timeIntervalSince($0.start) < 2 }

        // Light changes that stick for at least half a minute.
        var lastDark: Bool?
        var since = Date.distantPast
        for m in moments {
            if lastDark == nil { lastDark = m.dark; since = m.date; continue }
            if m.dark != lastDark, m.date.timeIntervalSince(since) > 30 {
                clips.append(Clip(kind: m.dark ? .lightsDown : .lightsUp, start: m.date, end: m.date, score: 0.2, thumb: m.thumb))
                lastDark = m.dark
                since = m.date
            }
        }
        return clips.sorted { $0.start > $1.start }
    }

    // MARK: Ask

    struct Answer {
        var text: String
        var clips: [Clip]
        var usedAI: Bool
    }

    static func ask(_ question: String, in context: ModelContext, sightings: [Sighting], horizonHours: Int, pestThreshold: Double) async -> Answer {
        let q = await parse(question, horizonHours: horizonHours)
        let events = spot(q.window, in: context, pestThreshold: pestThreshold)
        let relevant = q.anything ? events : events.filter { clip in
            q.keywords.contains { k in clip.title.lowercased().contains(k) || (clip.caption?.lowercased().contains(k) ?? false) }
        }
        let shown = relevant.isEmpty && !q.anything ? search(q, in: context, limit: 8) : Array(relevant.prefix(8))

        let log = activityLog(events: events, sightings: sightings.filter { q.window.contains($0.date) }, window: q.window)
        let frames = shown.prefix(2).compactMap { $0.thumb }.compactMap { try? Data(contentsOf: MomentStore.url(for: $0)) }
        if let text = await Intelligence.answer(question, log: log, frames: frames) {
            return Answer(text: text, clips: shown, usedAI: true)
        }
        return Answer(text: summary(relevant.isEmpty ? events : relevant, sightings: sightings, window: q.window, anything: q.anything),
                      clips: shown, usedAI: false)
    }

    /// Compact, time-ordered log the language model reasons over. Kept short for its context window.
    static func activityLog(events: [Clip], sightings: [Sighting], window: DateInterval) -> String {
        var lines = ["Window: \(Fmt.stamp.string(from: window.start)) to \(Fmt.stamp.string(from: window.end))"]
        for e in events.sorted(by: { $0.start < $1.start }).suffix(40) {
            var line = "\(e.timeRange) \(e.title.lowercased())"
            if e.score > 0.3, case .pest = e.kind { line += " (\(Int(e.score * 100))%)" }
            if let c = e.caption { line += " — \(c)" }
            lines.append(line)
        }
        for s in sightings.sorted(by: { $0.date < $1.date }).suffix(20) where s.outcome == .fired {
            lines.append("\(Fmt.clock.string(from: s.date)) scared off \(s.species?.code.lowercased() ?? "pest") with \(s.pattern?.code.lowercased() ?? "sound")")
        }
        if lines.count == 1 { lines.append("Nothing detected.") }
        return lines.joined(separator: "\n")
    }

    /// Fallback answer when no language model is available.
    static func summary(_ events: [Clip], sightings: [Sighting], window: DateInterval, anything: Bool) -> String {
        let real = events.filter { if case .lightsDown = $0.kind { return false }; if case .lightsUp = $0.kind { return false }; return true }
        guard !real.isEmpty else { return "Nothing seen between \(Fmt.clock.string(from: window.start)) and \(Fmt.clock.string(from: window.end))." }
        var counts: [String: [Clip]] = [:]
        for e in real { counts[e.title, default: []].append(e) }
        let parts = counts.sorted { $0.value.count > $1.value.count }.prefix(4).map { title, clips in
            let times = clips.sorted { $0.start < $1.start }.prefix(3).map { Fmt.clock.string(from: $0.start) }.joined(separator: ", ")
            return "\(title.lowercased()) ×\(clips.count) (\(times))"
        }
        let scared = sightings.filter { window.contains($0.date) && $0.outcome == .fired }.count
        return "Saw " + parts.joined(separator: "; ") + "." + (scared > 0 ? " Scared off \(scared)." : "")
    }

    // MARK: Helpers

    static func fetch(_ window: DateInterval, _ context: ModelContext) -> [Moment] {
        let start = window.start, end = window.end
        let d = FetchDescriptor<Moment>(predicate: #Predicate { $0.date >= start && $0.date <= end },
                                        sortBy: [SortDescriptor(\.date)])
        return (try? context.fetch(d)) ?? []
    }

    private static func group(_ hits: [(Moment, Double)], gap: TimeInterval) -> [Clip] {
        var clips: [Clip] = []
        for (m, s) in hits.sorted(by: { $0.0.date < $1.0.date }) {
            if var last = clips.last, m.date.timeIntervalSince(last.end) <= gap {
                last.end = m.date
                if s > last.score || last.thumb == nil, m.thumb != nil { last.thumb = m.thumb; last.caption = m.caption ?? last.caption }
                last.score = max(last.score, s)
                clips[clips.count - 1] = last
            } else {
                let kind: Clip.Kind = m.species.map { m.confidence >= 0.3 ? .pest($0) : .match } ?? .match
                clips.append(Clip(kind: kind, start: m.date, end: m.date, score: s, thumb: m.thumb, caption: m.caption))
            }
        }
        return clips
    }

    static func parsedLabels(_ s: String) -> [String: Double] {
        var out: [String: Double] = [:]
        let parts = s.split(separator: " ")
        var i = 0
        while i + 1 < parts.count {
            if let v = Double(parts[i + 1]) { out[String(parts[i])] = v }
            i += 2
        }
        return out
    }

    private static func tokens(_ s: String) -> [String] {
        s.split { !$0.isLetter }.map { w in
            var w = String(w)
            if w.count > 4, w.hasSuffix("es"), !w.hasSuffix("ses") { w.removeLast(2) } else if w.count > 3, w.hasSuffix("s") { w.removeLast() }
            return w
        }
    }

    private static let stopwords: Set<String> = [
        "the", "a", "an", "any", "did", "do", "was", "were", "is", "are", "there", "what", "when", "where", "who",
        "show", "me", "find", "all", "every", "of", "on", "in", "at", "to", "by", "near", "around", "from", "my",
        "last", "night", "today", "yesterday", "morning", "afternoon", "evening", "hour", "minute", "this", "since",
        "come", "came", "visit", "visited", "time", "times", "it", "i", "you", "and", "or", "with", "how", "many",
        "overnight", "tonight", "ago", "past", "recent", "recently",
    ]

    private static let synonyms: [String: [String]] = [
        "bird": ["bird", "pigeon", "gull"], "pigeon": ["pigeon", "dove", "bird"], "dove": ["pigeon", "dove"],
        "seagull": ["gull"], "gull": ["gull"], "fox": ["fox"], "rat": ["rat", "rodent"], "mice": ["rat", "rodent"],
        "mouse": ["rat", "rodent"], "rodent": ["rat", "rodent"], "vermin": ["rat", "rodent"], "squirrel": ["squirrel"],
        "person": ["person", "people"], "people": ["person", "people"], "someone": ["person", "people"],
        "somebody": ["person", "people"], "human": ["person", "people"], "man": ["person", "people"],
        "woman": ["person", "people"], "kid": ["person", "people", "child"], "cat": ["cat", "feline"],
        "dog": ["dog", "canine"], "hedgehog": ["hedgehog"], "pest": ["pigeon", "gull", "fox", "rat", "squirrel"],
        "animal": ["pigeon", "gull", "fox", "rat", "squirrel", "cat", "dog", "hedgehog"],
        "movement": ["motion"], "moving": ["motion"], "move": ["motion"], "motion": ["motion"],
    ]
}

/// "last night", "this morning", "last 3 hours", "yesterday"… → a window.
enum TimePhrase {
    static func window(in s: String, now: Date) -> DateInterval? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        func at(_ day: Date, _ hour: Int) -> Date { cal.date(byAdding: .hour, value: hour, to: day)! }
        func clamp(_ i: DateInterval) -> DateInterval { DateInterval(start: i.start, end: min(i.end, now)) }

        if let n = number(before: "hour", in: s) { return DateInterval(start: now.addingTimeInterval(-n * 3600), end: now) }
        if let n = number(before: "minute", in: s) { return DateInterval(start: now.addingTimeInterval(-n * 60), end: now) }
        if s.contains("last hour") || s.contains("past hour") { return DateInterval(start: now.addingTimeInterval(-3600), end: now) }
        if s.contains("last night") || s.contains("overnight") || s.contains("tonight") {
            let hour = cal.component(.hour, from: now)
            let nightStart = hour >= 20 ? at(today, 20) : at(cal.date(byAdding: .day, value: -1, to: today)!, 20)
            return clamp(DateInterval(start: nightStart, end: at(cal.startOfDay(for: nightStart.addingTimeInterval(86400)), 7)))
        }
        if s.contains("yesterday") {
            let y = cal.date(byAdding: .day, value: -1, to: today)!
            return DateInterval(start: y, end: today)
        }
        if s.contains("this morning") { return clamp(DateInterval(start: at(today, 5), end: at(today, 12))) }
        if s.contains("this afternoon") { return clamp(DateInterval(start: at(today, 12), end: at(today, 18))) }
        if s.contains("this evening") { return clamp(DateInterval(start: at(today, 18), end: at(today, 24))) }
        if s.contains("today") { return DateInterval(start: today, end: now) }
        return nil
    }

    private static func number(before unit: String, in s: String) -> Double? {
        let words = s.split(separator: " ").map(String.init)
        for (i, w) in words.enumerated() where w.hasPrefix(unit) && i > 0 {
            if let n = Double(words[i - 1]) { return n }
            let spelled = ["one": 1.0, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "ten": 10, "twelve": 12, "a": 1, "an": 1]
            if let n = spelled[words[i - 1]] { return n }
        }
        return nil
    }
}
