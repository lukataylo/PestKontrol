import SwiftUI
import SwiftData

enum AppTab: String, CaseIterable, Identifiable {
    case watch, ask, log, config
    var id: String { rawValue }

    var icon: [String] {
        switch self {
        case .watch: Glyphs.eye
        case .ask: Glyphs.search
        case .log: Glyphs.list
        case .config: Glyphs.sliders
        }
    }
}

struct RootView: View {
    @Environment(Sentry.self) private var sentry
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @AppStorage("shoo.onboarded") private var onboarded = false
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .nothing
    @State private var tab: AppTab = .watch

    var body: some View {
        ZStack {
            Theme.black.ignoresSafeArea()
            if Theme.slasher {
                GrainBackground().ignoresSafeArea()
            } else {
                DotGrid().ignoresSafeArea()
            }

            if onboarded {
                VStack(spacing: 12) {
                    Group {
                        switch tab {
                        case .watch: WatchView()
                        case .ask: AskView()
                        case .log: LogView()
                        case .config: ConfigView()
                        }
                    }
                    .frame(maxHeight: .infinity)
                    TabBar(tab: $tab)
                }
                .transition(.opacity)
            } else {
                OnboardingView { onboarded = true }
                    .transition(.opacity)
            }

            if sentry.stealth {
                StealthOverlay()
                    .transition(.opacity)
            }
        }
        // Palette is static; rebuilding the tree is what repaints every view.
        .id(theme)
        .animation(.easeInOut(duration: 0.25), value: sentry.stealth)
        .animation(.easeInOut(duration: 0.3), value: onboarded)
        .task(id: onboarded) {
            sentry.attach(context)
            if onboarded {
                tab = .watch
                await sentry.start()
            }
        }
        .onChange(of: phase) { _, newPhase in
            if newPhase == .active, onboarded { Task { await sentry.start() } }
            // Never leave the screen stuck at 2% brightness.
            if newPhase != .active { sentry.stealth = false }
        }
    }
}

struct TabBar: View {
    @Binding var tab: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { t in
                Button { tab = t } label: {
                    VStack(spacing: 7) {
                        DotSprite(rows: t.icon, pitch: 2.6, color: tab == t ? (Theme.slasher ? Theme.red : Theme.ink) : Theme.ghost)
                        Circle()
                            .fill(tab == t ? Theme.red : .clear)
                            .frame(width: 4, height: 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)
                    .padding(.bottom, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.rawValue.capitalized)
                .accessibilityAddTraits(tab == t ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8)
        .background(Capsule().fill(Theme.panel))
        .overlay(Capsule().strokeBorder(Theme.line))
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .sensoryFeedback(.selection, trigger: tab)
    }
}

/// Screen near-off for long sessions. The bot dozes on, drifting so OLED doesn't burn.
struct StealthOverlay: View {
    @Environment(Sentry.self) private var sentry
    @State private var savedBrightness: CGFloat = 0.5

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                let minute = Calendar.current.component(.minute, from: ctx.date)
                VStack(spacing: 22) {
                    BotFace(mood: sentry.status.mood(armed: sentry.armed), tint: sentry.status.mood(armed: sentry.armed) == .angry ? Theme.red : Theme.ink)
                        .frame(width: 200)
                        .opacity(0.35)
                    HStack(spacing: 8) {
                        PulseDot(active: sentry.armed, size: 6)
                        DotText(Fmt.clock.string(from: ctx.date), pitch: 2.4, color: .white.opacity(0.3))
                    }
                }
                .offset(x: CGFloat(minute % 5 - 2) * 8, y: CGFloat(minute % 7 - 3) * 10)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { sentry.stealth = false }
        .accessibilityLabel("Screen dimmed. Tap to wake.")
        .onAppear {
            guard let screen else { return }
            savedBrightness = screen.brightness
            screen.brightness = 0.02
        }
        .onDisappear { screen?.brightness = savedBrightness }
    }

    private var screen: UIScreen? {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen
    }
}
