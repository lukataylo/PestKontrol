import SwiftUI

enum BotMood: Equatable {
    case idle, suspicious, angry, surprised, happy, smug, sleepy, dead
}

extension SentryStatus {
    func mood(armed: Bool) -> BotMood {
        switch self {
        case .offline: .dead
        // Slasher's bot is calm and content when armed and clear.
        case .idle: Theme.slasher && armed ? .happy : .idle
        case .lowLight: .sleepy
        case .tracking: .suspicious
        case .firing: .angry
        case .logged, .quiet: .surprised
        case .cooldown: .smug
        case .held: .happy
        }
    }

    func line(armed: Bool, volumeLow: Bool) -> String {
        Theme.slasher ? slasherLine(armed: armed, volumeLow: volumeLow) : nothingLine(armed: armed, volumeLow: volumeLow)
    }

    private func slasherLine(armed: Bool, volumeLow: Bool) -> String {
        switch self {
        case .offline: "Camera off"
        case .idle:
            if !armed { "Camera ready" }
            else if volumeLow { "Armed. Volume up." }
            else { "All clear" }
        case .lowLight: "Too dark. Lamp?"
        case .tracking(let s, _, _): "Target: \(s.code)?"
        case .firing: "Intruder detected"
        case .logged(let s): "\(s.code) spotted"
        case .quiet(let s): "\(s.code). Quiet hours."
        case .cooldown: "They'll be back"
        case .held(let g): g == .person ? "Human. Holding fire." : "\(g.code). Holding fire."
        }
    }

    private func nothingLine(armed: Bool, volumeLow: Bool) -> String {
        switch self {
        case .offline: "Camera off."
        case .idle:
            if !armed { "All clear. Tap arm to scare." }
            else if volumeLow { "Armed. Volume up please." }
            else { "All clear. Armed." }
        case .lowLight: "Too dark. Lamp?"
        case .tracking(let s, _, _): "Hmm... \(s.code)?"
        case .firing(let s, _): "Shoo, \(s.code)!"
        case .logged(let s): "\(s.code)! Logged it."
        case .quiet(let s): "\(s.code). Shh, quiet hours."
        case .cooldown: "That told 'em."
        case .held(let g): g == .person ? "Hi human. Staying quiet." : "Hi \(g.code). No noise."
        }
    }
}

/// The monitoring bot: face + typed speech on an LED panel.
struct BotPanel: View {
    let status: SentryStatus
    let armed: Bool
    let volumeLow: Bool
    var gaze: Double?

    var body: some View {
        let mood = status.mood(armed: armed)
        let angry = mood == .angry
        VStack(alignment: .leading, spacing: 16) {
            BotFace(mood: mood, gaze: gaze, tint: angry ? Theme.red : Theme.ink)
                .frame(maxWidth: .infinity)
            BotSpeech(text: status.line(armed: armed, volumeLow: volumeLow))
        }
        .padding(18)
        .panelStyle(cornerRadius: 28, seed: 5, splatter: Theme.slasher ? .bottomTrailing : nil)
        .overlay {
            if angry && !Theme.slasher {
                RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Theme.red, lineWidth: 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.line(armed: armed, volumeLow: volumeLow))
    }
}

/// 29×13 dot face, rendered procedurally so moods can blink, scan and shout.
struct BotFace: View {
    var mood: BotMood
    /// -1…1: where the target is horizontally. nil = look around.
    var gaze: Double?
    var tint: Color = Theme.ink
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1 / 30)) { tl in
            let face = BotRenderer(mood: mood, t: reduceMotion ? 1 : tl.date.timeIntervalSinceReferenceDate, gaze: gaze, hollow: Theme.slasher)
            Canvas { ctx, size in
                let cols = BotRenderer.cols, rows = BotRenderer.rows
                let pitch = min(size.width / CGFloat(cols), size.height / CGFloat(rows))
                let d = pitch * 0.74
                let ox = (size.width - pitch * CGFloat(cols)) / 2 + (pitch - d) / 2
                let oy = (size.height - pitch * CGFloat(rows)) / 2 + (pitch - d) / 2
                var on = Path(), red = Path(), off = Path()
                for y in 0..<rows {
                    for x in 0..<cols {
                        let rect = CGRect(x: ox + CGFloat(x) * pitch, y: oy + CGFloat(y) * pitch, width: d, height: d)
                        switch face.pixel(x, y) {
                        case .on: on.addEllipse(in: rect)
                        case .accent: red.addEllipse(in: rect)
                        case .off: off.addEllipse(in: rect)
                        }
                    }
                }
                ctx.fill(off, with: .color(Theme.ink.opacity(0.07)))
                ctx.fill(on, with: .color(tint))
                // Slasher pupils are bone against the blood.
                ctx.fill(red, with: .color(Theme.slasher ? Theme.ink : Theme.red))
            }
            .shadow(color: Theme.slasher && mood == .angry ? Theme.red.opacity(0.8) : .clear, radius: 10)
        }
        .aspectRatio(CGFloat(BotRenderer.cols) / CGFloat(BotRenderer.rows), contentMode: .fit)
        .accessibilityHidden(true)
    }
}

private struct BotRenderer {
    enum Px { case off, on, accent }

    static let cols = 29, rows = 13

    let mood: BotMood
    let t: Double
    let gaze: Double?
    /// Ring eyes instead of solid blobs.
    var hollow = false

    private let eyeY = 6.0
    private let eyeXs = [8.0, 20.0]
    private let mouthX = 14.0, mouthY = 11.0

    /// 1 = open. Quick blink every ~4 s.
    private var open: Double {
        let p = t.truncatingRemainder(dividingBy: 4.2)
        return p < 0.16 ? max(0.08, abs(p - 0.08) / 0.08) : 1
    }

    private var look: (x: Double, y: Double) {
        if let gaze { return (max(-1.6, min(1.6, gaze * 2)), 0) }
        switch mood {
        case .idle: return (1.5 * sin(t * 0.7), 0.6 * sin(t * 0.45))
        case .smug: return (1.4, 0.8)
        default: return (0, 0)
        }
    }

    func pixel(_ x: Int, _ y: Int) -> Px {
        let px = Double(x), py = Double(y)
        for (i, cx) in eyeXs.enumerated() {
            let dx = px - cx, dy = py - eyeY
            if abs(dx) <= 4, abs(dy) <= 5.5, let p = eye(dx, dy, left: i == 0) { return p }
        }
        return mouth(px - mouthX, py - mouthY) ?? zzz(x, y) ?? .off
    }

    // MARK: Shapes

    /// Rounded-square blob, the classic LED eye.
    private func blob(_ dx: Double, _ dy: Double, rx: Double = 3.5, ry: Double) -> Bool {
        if ry < 0.7 { return abs(dy) < 0.5 && abs(dx) <= 3 }
        return pow(abs(dx / rx), 4) + pow(abs(dy / ry), 4) <= 1
    }

    private func pupil(_ dx: Double, _ dy: Double, r: Double = 1.05) -> Bool {
        pow(dx - look.x, 2) + pow(dy - look.y, 2) <= r * r
    }

    private func arc(_ dx: Double, _ dy: Double, base: Double, curve: Double, half: Double = 3, weight: Double = 0.55) -> Bool {
        abs(dy - (base + curve * dx * dx)) < weight && abs(dx) <= half
    }

    private func eye(_ dx: Double, _ dy: Double, left: Bool) -> Px? {
        switch mood {
        case .idle:
            let ry = 3.5 * open
            guard blob(dx, dy, ry: ry) else { return nil }
            if hollow && ry > 1.5 {
                return blob(dx - look.x * 0.4, dy - look.y * 0.4, rx: 2.4, ry: ry - 1.1) ? .off : .on
            }
            return ry > 1.5 && pupil(dx, dy) ? .off : .on

        case .suspicious:
            let ry = (left ? 1.6 : 3.2) * open
            if !left, abs(dy + 5) < 0.5, abs(dx) <= 2.5 { return .on }
            guard blob(dx, dy, ry: ry) else { return nil }
            return ry > 1.5 && pupil(dx, dy, r: 0.9) ? .accent : .on

        case .angry:
            let inner = left ? dx : -dx
            let brow = -4.4 + 0.38 * (inner + 3)
            if abs(dy - brow) < 0.55, abs(dx) <= 3.2 { return .on }
            guard blob(dx, dy, ry: 3.3), dy > brow + 0.7 else { return nil }
            return pupil(dx, dy, r: 0.9) ? .accent : .on

        case .surprised:
            if abs(dy + 5) < 0.5, abs(dx) <= 2 { return .on }
            guard blob(dx, dy, ry: 3.6) else { return nil }
            return pupil(dx, dy, r: 0.6) ? .off : .on

        case .happy:
            return arc(dx, dy, base: -1.2, curve: 0.32, weight: 0.8) ? .on : nil

        case .smug:
            guard blob(dx, dy, ry: 3.3), dy >= -0.5 else { return nil }
            return pupil(dx, dy, r: 0.9) ? .off : .on

        case .sleepy:
            return arc(dx, dy, base: 1, curve: -0.14) ? .on : nil

        case .dead:
            return abs(abs(dx) - abs(dy)) < 0.5 && abs(dx) <= 2.5 && abs(dy) <= 2.5 ? .on : nil
        }
    }

    private func mouth(_ dx: Double, _ dy: Double) -> Px? {
        switch mood {
        case .idle, .dead:
            return abs(dy) < 0.5 && abs(dx) <= 2 ? .on : nil
        case .suspicious:
            return abs(dy - 0.3 * dx) < 0.5 && abs(dx) <= 2.5 ? .on : nil
        case .angry:
            let ry = 0.6 + 1.2 * abs(sin(t * 9))
            guard pow(abs(dx / 3.2), 4) + pow(abs(dy / ry), 4) <= 1 else { return nil }
            return abs(dy) < ry - 0.9 && abs(dx) < 2.2 ? .off : .on
        case .surprised:
            let r = (dx * dx + dy * dy).squareRoot()
            return r > 0.6 && r < 1.6 ? .on : nil
        case .happy, .smug:
            return arc(dx, dy, base: 0.6, curve: -0.09, half: 3.5) ? .on : nil
        case .sleepy:
            return abs(dy) < 0.5 && abs(dx) <= 1 ? .on : nil
        }
    }

    private func zzz(_ x: Int, _ y: Int) -> Px? {
        guard mood == .sleepy else { return nil }
        let z = ["####", "..#.", ".#..", "####"]
        let rise = Int(t.truncatingRemainder(dividingBy: 2.4) / 0.8)
        let lx = x - 25, ly = y - (2 - rise)
        guard (0..<4).contains(lx), (0..<4).contains(ly) else { return nil }
        return Array(z[ly])[lx] == "#" ? .accent : nil
    }
}

/// Typewriter speech in dot type, two lines, blinking cursor.
struct BotSpeech: View {
    let text: String
    var pitch: CGFloat = 2.5
    var maxChars = 20
    var color: Color = Theme.ink
    @State private var shown = ""
    @State private var since = Date.distantPast

    var body: some View {
        let lines = Self.wrap(shown.uppercased(), maxChars)
        TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
            let typed = Int(tl.date.timeIntervalSince(since) / 0.03)
            let visible = Self.reveal(lines, typed)
            let total = lines.reduce(0) { $0 + $1.count }
            let cursorLine = lines.indices.first { visible[$0].count < lines[$0].count } ?? max(lines.count - 1, 0)
            let cursor = typed < total || Int(tl.date.timeIntervalSinceReferenceDate * 2.5) % 2 == 0
            VStack(alignment: .leading, spacing: pitch * 3) {
                ForEach(0..<2, id: \.self) { i in
                    let body = i < visible.count ? visible[i] : ""
                    DotText(body + (cursor && i == cursorLine ? "_" : ""), pitch: pitch, color: color)
                        .frame(height: 7 * pitch, alignment: .leading)
                }
            }
        }
        .onAppear { shown = text; since = .now }
        .onChange(of: text) { _, new in shown = new; since = .now }
    }

    static func wrap(_ text: String, _ maxChars: Int) -> [String] {
        var lines: [String] = []
        var current = ""
        for word in text.split(separator: " ") {
            if current.isEmpty {
                current = String(word)
            } else if current.count + 1 + word.count <= maxChars {
                current += " " + word
            } else {
                lines.append(current)
                current = String(word)
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    static func reveal(_ lines: [String], _ count: Int) -> [String] {
        var left = count
        return lines.map { line in
            defer { left -= line.count }
            return String(line.prefix(max(0, left)))
        }
    }
}
