import SwiftUI

struct Caption: View {
    let text: String
    var color: Color = Theme.dim

    init(_ text: String, color: Color = Theme.dim) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(Theme.mono(10, .medium))
            .tracking(1.4)
            .foregroundStyle(color)
    }
}

/// The faint dot field behind everything.
struct DotGrid: View {
    var spacing: CGFloat = 14

    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            var y = spacing / 2
            while y < size.height {
                var x = spacing / 2
                while x < size.width {
                    path.addEllipse(in: CGRect(x: x - 0.75, y: y - 0.75, width: 1.5, height: 1.5))
                    x += spacing
                }
                y += spacing
            }
            ctx.fill(path, with: .color(.white.opacity(0.07)))
        }
        .allowsHitTesting(false)
    }
}

/// Horizontal meter made of dots.
struct DotBar: View {
    var value: Double
    var count = 30
    var color: Color = Theme.ink

    var body: some View {
        Canvas { ctx, size in
            let pitch = size.width / CGFloat(count)
            let d = min(pitch * 0.6, size.height)
            let lit = Int((min(max(value, 0), 1) * Double(count)).rounded())
            for i in 0..<count {
                let rect = CGRect(x: CGFloat(i) * pitch + (pitch - d) / 2, y: (size.height - d) / 2, width: d, height: d)
                ctx.fill(Path(ellipseIn: rect), with: .color(i < lit ? color : Theme.ghost.opacity(0.45)))
            }
        }
        .frame(height: 8)
    }
}

struct Card<Content: View>: View {
    var title: String?
    var seed = 1
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let title { Caption(title) }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelStyle(seed: seed + (title?.count ?? 0))
    }
}

struct Chip: View {
    let text: String
    var fill: Color = .clear
    var fg: Color = Theme.ink
    var stroke: Color = Theme.ghost

    var body: some View {
        Text(text.uppercased())
            .font(Theme.mono(10, .semibold))
            .tracking(1.2)
            .foregroundStyle(fg)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(stroke, lineWidth: 1))
    }
}

struct NToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.18)) { isOn.toggle() }
        } label: {
            let track = Theme.slasher ? Theme.red : Theme.ink
            let knob = Theme.slasher ? Theme.ink : Theme.black
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? track : .clear)
                    .overlay(Capsule().strokeBorder(isOn ? .clear : Theme.ghost, lineWidth: 1.5))
                Circle()
                    .fill(isOn ? knob : Theme.dim)
                    .frame(width: Theme.slasher ? 20 : 12, height: Theme.slasher ? 20 : 12)
                    .padding(.horizontal, Theme.slasher ? 3 : 7)
            }
            .frame(width: Theme.slasher ? 52 : 46, height: 26)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn)
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// Icon-only round button. The label is for VoiceOver, not the screen.
struct DotIconButton: View {
    let icon: [String]
    let label: String
    var fill: Color = Theme.panel
    var fg: Color = Theme.ink
    var size: CGFloat = 56
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            DotSprite(rows: icon, pitch: size / 21, color: fg)
                .frame(width: size, height: size)
                .background(Circle().fill(fill))
                .overlay(Circle().strokeBorder(Theme.line))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }
}

/// Wide primary action: white capsule, dot type.
struct PrimaryButton: View {
    let title: String
    var icon: [String]? = Glyphs.arrow
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                DotText(title, pitch: 3.2, color: .black)
                if let icon { DotSprite(rows: icon, pitch: 3.2, color: .black) }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(Capsule().fill(Theme.ink))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(title)
    }
}

struct PulseDot: View {
    var active = true
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(active ? Theme.red : Theme.ghost)
            .frame(width: size, height: size)
            .phaseAnimator(active ? [1.0, 0.2] : [1.0]) { view, opacity in
                view.opacity(opacity)
            } animation: { _ in
                .easeInOut(duration: 0.9)
            }
    }
}

struct StepperRow: View {
    let label: String
    let value: String
    let decrement: () -> Void
    let increment: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Caption(label, color: Theme.ink.opacity(0.85))
            Spacer()
            step("minus", decrement)
            DotText(value, pitch: 3)
                .frame(minWidth: 70)
            step("plus", increment)
        }
    }

    private func step(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 32, height: 32)
                .overlay(Circle().strokeBorder(Theme.ghost))
        }
        .buttonStyle(PressStyle())
        .sensoryFeedback(.increase, trigger: value)
    }
}

/// Viewfinder corner brackets.
struct Brackets: Shape {
    var length: CGFloat = 16

    func path(in r: CGRect) -> Path {
        let l = min(length, r.width / 3, r.height / 3)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + l))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + l, y: r.minY))
        p.move(to: CGPoint(x: r.maxX - l, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + l))
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - l))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - l, y: r.maxY))
        p.move(to: CGPoint(x: r.minX + l, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - l))
        return p
    }
}
