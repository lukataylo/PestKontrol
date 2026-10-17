import SwiftUI

// Slasher theme: grain, distressed bone-white borders, blood splatter.
// Everything is drawn from a seed, so a given panel always gets the same scuffs.

struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(_ seed: Int) {
        state = UInt64(truncatingIfNeeded: seed) &* 0x9E37_79B9_7F4A_7C15 | 1
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func unit() -> CGFloat { CGFloat.random(in: 0...1, using: &self) }
    mutating func range(_ r: ClosedRange<CGFloat>) -> CGFloat { CGFloat.random(in: r, using: &self) }
}

enum Grunge {
    /// 256² tile of light and dark specks, generated once.
    static let grain: UIImage = {
        let size = 256
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            var rng = SeededRandom(7)
            for _ in 0..<5200 {
                let light = rng.unit() > 0.55
                let a = rng.range(0.03...(light ? 0.16 : 0.5))
                UIColor(white: light ? 1 : 0, alpha: a).setFill()
                let s = rng.range(0.6...1.8)
                ctx.fill(CGRect(x: rng.unit() * CGFloat(size), y: rng.unit() * CGFloat(size), width: s, height: s))
            }
        }
    }()

    /// Opaque with pitted holes, for eating into type.
    static let pits: UIImage = {
        let size = 256
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            var rng = SeededRandom(11)
            for _ in 0..<1400 {
                UIColor(white: 1, alpha: 1).setFill()
                let s = rng.range(0.6...2.6)
                ctx.cgContext.setBlendMode(.clear)
                ctx.cgContext.fillEllipse(in: CGRect(x: rng.unit() * CGFloat(size), y: rng.unit() * CGFloat(size), width: s, height: s * rng.range(0.5...1.4)))
            }
        }
    }()
}

/// Full-screen soot: grain, a few long scratches, vignette, corner crosshairs.
struct GrainBackground: View {
    var body: some View {
        ZStack {
            Theme.black
            Image(uiImage: Grunge.grain)
                .resizable(resizingMode: .tile)
                .opacity(0.9)
            Canvas { ctx, size in
                var rng = SeededRandom(3)
                for _ in 0..<14 {
                    let x = rng.unit() * size.width, y = rng.unit() * size.height
                    let len = rng.range(40...220), angle = rng.range(-0.9 ... -0.3)
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: y))
                    p.addLine(to: CGPoint(x: x + cos(angle) * len, y: y + sin(angle) * len))
                    ctx.stroke(p, with: .color(Theme.ink.opacity(rng.range(0.03...0.08))), lineWidth: rng.range(0.4...1))
                }
                let corners = [CGPoint(x: 22, y: 22), CGPoint(x: size.width - 22, y: 22)]
                for c in corners {
                    var plus = Path()
                    plus.move(to: CGPoint(x: c.x - 14, y: c.y)); plus.addLine(to: CGPoint(x: c.x + 14, y: c.y))
                    plus.move(to: CGPoint(x: c.x, y: c.y - 14)); plus.addLine(to: CGPoint(x: c.x, y: c.y + 14))
                    ctx.stroke(plus, with: .color(Theme.ink.opacity(0.7)), lineWidth: 1)
                }
            }
            RadialGradient(colors: [.clear, .black.opacity(0.55)], center: .center, startRadius: 200, endRadius: 700)
        }
        .allowsHitTesting(false)
    }
}

/// Bone-white border that's chipped, scuffed and uneven.
struct DistressedBorder: View {
    var cornerRadius: CGFloat = 24
    var seed = 1
    var color: Color = Theme.ink

    var body: some View {
        Canvas { ctx, size in
            var rng = SeededRandom(seed)
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1.5, dy: 1.5)
            let path = Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous)
            // Uneven stroke: short segments with varying weight, some missing.
            let segments = 140
            for i in 0..<segments {
                guard rng.unit() > 0.06 else { continue }
                let a = CGFloat(i) / CGFloat(segments), b = CGFloat(i + 1) / CGFloat(segments)
                ctx.stroke(path.trimmedPath(from: a, to: b),
                           with: .color(color.opacity(rng.range(0.55...0.95))),
                           lineWidth: rng.range(1.0...2.4))
            }
            // Flecks just inside the edge.
            for _ in 0..<Int((size.width + size.height) / 3) {
                let side = Int(rng.unit() * 4)
                let t = rng.unit(), d = rng.range(2...14) * rng.unit() + 2
                let p: CGPoint
                switch side {
                case 0: p = CGPoint(x: rect.minX + t * rect.width, y: rect.minY + d)
                case 1: p = CGPoint(x: rect.maxX - d, y: rect.minY + t * rect.height)
                case 2: p = CGPoint(x: rect.minX + t * rect.width, y: rect.maxY - d)
                default: p = CGPoint(x: rect.minX + d, y: rect.minY + t * rect.height)
                }
                let s = rng.range(0.6...1.9)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x, y: p.y, width: s, height: s)), with: .color(color.opacity(rng.range(0.15...0.6))))
            }
        }
        .allowsHitTesting(false)
    }
}

/// Blood splatter bleeding in from a corner or edge.
struct Splatter: View {
    enum Anchor { case bottomTrailing, bottomLeading, leading, topTrailing }
    var anchor: Anchor = .bottomTrailing
    var seed = 1
    var amount: CGFloat = 1

    var body: some View {
        Canvas { ctx, size in
            var rng = SeededRandom(seed)
            let red = Theme.red
            func origin() -> CGPoint {
                switch anchor {
                case .bottomTrailing: CGPoint(x: size.width - rng.range(0...size.width * 0.35), y: size.height - rng.range(0...size.height * 0.3))
                case .bottomLeading: CGPoint(x: rng.range(0...size.width * 0.35), y: size.height - rng.range(0...size.height * 0.25))
                case .leading: CGPoint(x: rng.range(0...14), y: rng.unit() * size.height)
                case .topTrailing: CGPoint(x: size.width - rng.range(0...size.width * 0.3), y: rng.range(0...size.height * 0.25))
                }
            }
            // Streaks.
            for _ in 0..<Int(28 * amount) {
                let o = origin()
                let angle = rng.range(-2.7 ... -2.2) + (anchor == .leading || anchor == .bottomLeading ? .pi * 0.85 : 0)
                let len = rng.range(8...70)
                var p = Path()
                p.move(to: o)
                p.addLine(to: CGPoint(x: o.x + cos(angle) * len, y: o.y + sin(angle) * len))
                ctx.stroke(p, with: .color(red.opacity(rng.range(0.4...0.95))), style: StrokeStyle(lineWidth: rng.range(0.5...3.2), lineCap: .round))
            }
            // Blobs and mist.
            for _ in 0..<Int(90 * amount) {
                let o = origin()
                let s = rng.unit() > 0.85 ? rng.range(4...11) : rng.range(0.8...3)
                ctx.fill(Path(ellipseIn: CGRect(x: o.x, y: o.y, width: s, height: s * rng.range(0.6...1.3))),
                         with: .color(red.opacity(rng.range(0.35...0.95))))
            }
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// The panel surface for the active theme.
    func panelStyle(cornerRadius: CGFloat = 24, seed: Int = 1, splatter: Splatter.Anchor? = nil, fill: Color = Theme.panel) -> some View {
        modifier(PanelStyle(cornerRadius: cornerRadius, seed: seed, splatter: splatter, fill: fill))
    }
}

private struct PanelStyle: ViewModifier {
    let cornerRadius: CGFloat
    let seed: Int
    let splatter: Splatter.Anchor?
    let fill: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if Theme.slasher {
            content
                .background {
                    ZStack {
                        shape.fill(fill)
                        if let splatter { Splatter(anchor: splatter, seed: seed).clipShape(shape) }
                    }
                }
                .overlay(DistressedBorder(cornerRadius: cornerRadius, seed: seed))
        } else {
            content
                .background(shape.fill(fill))
                .overlay(shape.strokeBorder(Theme.line, lineWidth: 1))
        }
    }
}

/// Screen headline. Nothing: dot type. Slasher: blood-red brush logo.
struct ScreenTitle: View {
    let text: String

    var body: some View {
        if Theme.slasher {
            switch text {
            case "SHOO": logo("slasher_logo_shoo", height: 104)
            case "CONFIG": logo("slasher_logo_config", height: 112)
            default: GrungeTitle(text: text)
            }
        } else {
            DotText(text, pitch: text == "SHOO" ? 4 : 6)
        }
    }

    private func logo(_ name: String, height: CGFloat) -> some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .accessibilityLabel(text)
    }
}

/// Fallback for titles without hand-made art: heavy condensed type, eaten by pits.
struct GrungeTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 92, weight: .black).width(.compressed))
            .foregroundStyle(Theme.red)
            .mask {
                Image(uiImage: Grunge.pits).resizable(resizingMode: .tile)
            }
            .rotationEffect(.degrees(-4))
            .padding(.vertical, -6)
    }
}

/// The decorative sixth card on Config.
struct CrosshairTarget: View {
    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) * 0.28
            var rng = SeededRandom(21)
            for i in 0..<60 {
                guard rng.unit() > 0.08 else { continue }
                let a = CGFloat(i) / 60 * .pi * 2, b = CGFloat(i + 1) / 60 * .pi * 2
                var arc = Path()
                arc.addArc(center: c, radius: r, startAngle: .radians(a), endAngle: .radians(b), clockwise: false)
                ctx.stroke(arc, with: .color(Theme.red.opacity(rng.range(0.7...1))), lineWidth: rng.range(2...3.4))
            }
            var cross = Path()
            cross.move(to: CGPoint(x: c.x - r * 1.9, y: c.y)); cross.addLine(to: CGPoint(x: c.x + r * 1.9, y: c.y))
            cross.move(to: CGPoint(x: c.x, y: c.y - r * 1.6)); cross.addLine(to: CGPoint(x: c.x, y: c.y + r * 1.6))
            ctx.stroke(cross, with: .color(Theme.red), lineWidth: 2)
        }
        .accessibilityHidden(true)
    }
}
