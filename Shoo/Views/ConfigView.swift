import SwiftUI

struct ConfigView: View {
    @Environment(Sentry.self) private var sentry
    @AppStorage("shoo.onboarded") private var onboarded = true
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .nothing
    @AppStorage("shoo.debug") private var debug = false
    @State private var fineTune = false

    var body: some View {
        @Bindable var sentry = sentry
        let tuning = sentry.settings.tuning
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenTitle(text: "CONFIG")
                    .padding(.bottom, 6)

                Caption("Pests")
                PetGrid(settings: $sentry.settings) { sentry.test($0) }

                Card(title: "Friends · never scared") {
                    FriendsRow(dimmed: !sentry.settings.protectLock)
                    toggleRow("Hold fire when a friend is in view", isOn: $sentry.settings.protectLock)
                }

                Caption("Mode").padding(.top, 6)
                ModePicker(settings: $sentry.settings)

                Caption("Theme").padding(.top, 6)
                HStack(spacing: 10) {
                    ForEach(AppTheme.allCases) { t in
                        Button {
                            Theme.current = t
                            theme = t
                        } label: {
                            ThemeSwatch(theme: t, selected: theme == t)
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("\(t.title) theme")
                        .accessibilityAddTraits(theme == t ? .isSelected : [])
                    }
                }

                Card {
                    HStack(spacing: 14) {
                        DotSprite(rows: Glyphs.moon, pitch: 3)
                        VStack(alignment: .leading, spacing: 6) {
                            DotText("QUIET NIGHTS", pitch: 2.4)
                            Caption("\(hour(sentry.settings.quietStart)) → \(hour(sentry.settings.quietEnd)) · log only")
                        }
                        Spacer()
                        NToggle(isOn: $sentry.settings.quietHours)
                    }
                }

                Card {
                    Button {
                        withAnimation(.snappy) { fineTune.toggle() }
                    } label: {
                        HStack {
                            DotText("FINE-TUNE", pitch: 2.4)
                            Spacer()
                            DotSprite(rows: Glyphs.chevron, pitch: 2.4, color: Theme.dim)
                                .rotationEffect(.degrees(fineTune ? 180 : 0))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if fineTune {
                        StepperRow(label: "Certainty", value: "\(Int((tuning.threshold * 100).rounded()))%") {
                            sentry.settings.tune { $0.threshold = max(0.2, $0.threshold - 0.05) }
                        } increment: {
                            sentry.settings.tune { $0.threshold = min(0.95, $0.threshold + 0.05) }
                        }
                        StepperRow(label: "Patience", value: "\(tuning.confirmFrames)") {
                            sentry.settings.tune { $0.confirmFrames = max(1, $0.confirmFrames - 1) }
                        } increment: {
                            sentry.settings.tune { $0.confirmFrames = min(8, $0.confirmFrames + 1) }
                        }
                        StepperRow(label: "Rest", value: "\(Int(tuning.cooldown))S") {
                            sentry.settings.tune { $0.cooldown = max(10, $0.cooldown - 15) }
                        } increment: {
                            sentry.settings.tune { $0.cooldown = min(600, $0.cooldown + 15) }
                        }
                        StepperRow(label: "Loudness", value: "\(Int((tuning.gain * 100).rounded()))%") {
                            sentry.settings.tune { $0.gain = max(0.1, $0.gain - 0.1) }
                        } increment: {
                            sentry.settings.tune { $0.gain = min(1, $0.gain + 0.1) }
                        }
                        StepperRow(label: "Quiet from", value: hour(sentry.settings.quietStart)) {
                            sentry.settings.quietStart = (sentry.settings.quietStart + 23) % 24
                        } increment: {
                            sentry.settings.quietStart = (sentry.settings.quietStart + 1) % 24
                        }
                        StepperRow(label: "Quiet until", value: hour(sentry.settings.quietEnd)) {
                            sentry.settings.quietEnd = (sentry.settings.quietEnd + 23) % 24
                        } increment: {
                            sentry.settings.quietEnd = (sentry.settings.quietEnd + 1) % 24
                        }
                        Caption("Certainty: how sure before acting. Patience: frames in a row (~¼ s each). Rest: pause after acting.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Card {
                    HStack(spacing: 14) {
                        DotSprite(rows: Glyphs.eye, pitch: 3)
                        VStack(alignment: .leading, spacing: 6) {
                            DotText("ON-DEVICE", pitch: 2.4)
                            Caption("\(sentry.engineName) · no network · snapshots only")
                        }
                    }
                    toggleRow("Show what I see — raw labels on the camera", isOn: $debug)
                    Button { onboarded = false } label: {
                        Chip(text: "Replay intro")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
    }

    private func toggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(Theme.mono(12))
                .foregroundStyle(Theme.ink.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            NToggle(isOn: isOn)
        }
    }

    private func hour(_ h: Int) -> String {
        String(format: "%02d:00", h)
    }
}

/// A fixed-palette preview of each theme, independent of the active one.
struct ThemeSwatch: View {
    let theme: AppTheme
    let selected: Bool

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                switch theme {
                case .nothing:
                    Color.black
                    DotGrid(spacing: 9)
                    HStack(spacing: 6) {
                        DotText("SHOO", pitch: 2.6, color: .white)
                        Circle().fill(Color(red: 215 / 255, green: 25 / 255, blue: 33 / 255)).frame(width: 6, height: 6)
                    }
                case .slasher:
                    Color(red: 0.035, green: 0.031, blue: 0.027)
                    Image(uiImage: Grunge.grain).resizable(resizingMode: .tile)
                    Image("slasher_logo_shoo").resizable().scaledToFit().padding(14)
                }
            }
            .frame(height: 86)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? Theme.red : Theme.line, lineWidth: selected ? 2 : 1)
            )
            Caption(theme.title, color: selected ? Theme.ink : Theme.dim)
        }
        .frame(maxWidth: .infinity)
    }
}
