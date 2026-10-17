import SwiftUI

/// Two-column grid of pest cards. Tap a card to target it, tap its sound to cycle + hear it.
struct PetGrid: View {
    @Binding var settings: SentrySettings
    var showSound = true
    var onPreview: (SoundPattern) -> Void = { _ in }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(Species.allCases) { sp in
                PetCard(
                    species: sp,
                    on: settings.enabled.contains(sp),
                    pattern: showSound ? settings.pattern(for: sp) : nil,
                    toggle: {
                        if settings.enabled.contains(sp) { settings.enabled.remove(sp) } else { settings.enabled.insert(sp) }
                    },
                    cycle: {
                        let next = settings.pattern(for: sp).next
                        settings.patterns[sp] = next
                        onPreview(next)
                    }
                )
            }
            if Theme.slasher {
                CrosshairTarget()
                    .frame(maxWidth: .infinity, minHeight: 150)
                    .panelStyle(cornerRadius: 22, seed: 40)
            }
        }
    }
}

struct PetCard: View {
    let species: Species
    let on: Bool
    let pattern: SoundPattern?
    let toggle: () -> Void
    let cycle: () -> Void

    var body: some View {
        Group {
            if Theme.slasher { engraved } else { dots }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .sensoryFeedback(.selection, trigger: on)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(species.code), \(on ? "targeted" : "ignored")")
        .accessibilityAddTraits(.isButton)
    }

    /// Slasher: etched illustration on a blood smear, red dot when targeted.
    private var engraved: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image("slasher_\(species.rawValue)")
                .resizable()
                .aspectRatio(359 / 135, contentMode: .fill)
                .saturation(on ? 1 : 0)
                .opacity(on ? 1 : 0.35)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(on ? Theme.red : .clear)
                        .overlay(Circle().strokeBorder(on ? .clear : Theme.ghost, lineWidth: 1.5))
                        .frame(width: 14, height: 14)
                        .padding(10)
                }
            VStack(alignment: .leading, spacing: 10) {
                Text(species.code)
                    .font(Theme.mono(17, .medium))
                    .tracking(1.5)
                    .foregroundStyle(on ? Theme.ink : Theme.ghost)
                if let pattern { soundChip(pattern) }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .panelStyle(cornerRadius: 22, seed: species.rawValue.count * 7)
    }

    private func soundChip(_ pattern: SoundPattern) -> some View {
        Button(action: cycle) {
            HStack(spacing: 8) {
                DotSprite(rows: Glyphs.wave, pitch: 1.5, color: on ? Theme.ink : Theme.ghost)
                Text(pattern.code)
                    .font(Theme.mono(11, .semibold))
                    .tracking(1.5)
            }
            .foregroundStyle(on ? Theme.ink : Theme.ghost)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .overlay(Capsule().strokeBorder(Theme.ink.opacity(on ? 0.8 : 0.25), lineWidth: 1.2))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: pattern)
        .accessibilityLabel("Sound \(pattern.code). Tap to change and preview.")
    }

    private var dots: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                DotSprite(rows: Pets.sprite(species), pitch: 4.4, dimmed: !on)
                Spacer()
                Circle()
                    .fill(on ? Theme.red : .clear)
                    .overlay(Circle().strokeBorder(on ? .clear : Theme.ghost, lineWidth: 1.5))
                    .frame(width: 10, height: 10)
            }
            DotText(species.code, pitch: 2.3, color: on ? Theme.ink : Theme.ghost)
            if let pattern {
                Button(action: cycle) {
                    HStack(spacing: 6) {
                        DotSprite(rows: Glyphs.play, pitch: 1.6, color: on ? Theme.ink : Theme.ghost)
                        Text(pattern.code)
                            .font(Theme.mono(10, .semibold))
                            .tracking(1.2)
                    }
                    .foregroundStyle(on ? Theme.ink : Theme.ghost)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .overlay(Capsule().strokeBorder(Theme.ghost))
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: pattern)
                .accessibilityLabel("Sound \(pattern.code). Tap to change and preview.")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(on ? Theme.panel : .clear))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(on ? Theme.ink.opacity(0.35) : Theme.line, lineWidth: 1)
        )
    }
}

/// Friends the sentry will never scare.
struct FriendsRow: View {
    var dimmed = false

    var body: some View {
        HStack {
            ForEach(Guarded.allCases, id: \.self) { g in
                VStack(spacing: 10) {
                    DotSprite(rows: Pets.sprite(g), pitch: 3.2, dimmed: dimmed)
                        .frame(height: 30, alignment: .bottom)
                    Caption(g.code)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

struct ModePicker: View {
    @Binding var settings: SentrySettings

    var body: some View {
        if Theme.slasher { segmented } else { stacked }
    }

    /// Slasher: one bar, three cells, the chosen one soaked red.
    private var segmented: some View {
        HStack(spacing: 0) {
            ForEach(Array(Mode.presets.enumerated()), id: \.element) { i, mode in
                let selected = settings.mode == mode
                if i > 0 { Rectangle().fill(Theme.ink.opacity(0.4)).frame(width: 1).padding(.vertical, 12) }
                Button { settings.mode = mode } label: {
                    HStack(spacing: 10) {
                        DotSprite(rows: Glyphs.wave, pitch: 1.6 + CGFloat(mode.level) * 0.35, color: Theme.ink)
                        Text(mode.code).font(Theme.mono(12, .medium)).tracking(1.2).foregroundStyle(Theme.ink)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 62)
                    .background(selected ? Theme.red : .clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: selected)
                .accessibilityLabel("\(mode.code). \(mode.blurb)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .panelStyle(cornerRadius: 18, seed: 33)
    }

    private var stacked: some View {
        VStack(spacing: 10) {
            ForEach(Mode.presets) { mode in
                let selected = settings.mode == mode
                Button { settings.mode = mode } label: {
                    HStack(spacing: 16) {
                        LevelDots(level: mode.level, color: selected ? .black : Theme.ink)
                        VStack(alignment: .leading, spacing: 8) {
                            DotText(mode.code, pitch: 3, color: selected ? .black : Theme.ink)
                            Text(mode.blurb)
                                .font(Theme.mono(12))
                                .foregroundStyle(selected ? .black.opacity(0.6) : Theme.dim)
                        }
                        Spacer()
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(selected ? Theme.ink : Theme.panel))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.line))
                }
                .buttonStyle(PressStyle())
                .sensoryFeedback(.selection, trigger: selected)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            if settings.mode == .custom {
                HStack {
                    Caption("Custom · fine-tuned")
                    Spacer()
                    DotSprite(rows: Glyphs.sliders, pitch: 2, color: Theme.dim)
                }
                .padding(.horizontal, 6)
            }
        }
    }
}

/// Three rising columns of dots, like signal bars.
struct LevelDots: View {
    let level: Int
    var color: Color = Theme.ink

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(1...3, id: \.self) { i in
                VStack(spacing: 3) {
                    ForEach(0..<i, id: \.self) { _ in
                        Circle()
                            .fill(i <= level ? color : color.opacity(0.18))
                            .frame(width: 5, height: 5)
                    }
                }
            }
        }
        .frame(width: 26, alignment: .bottom)
    }
}
