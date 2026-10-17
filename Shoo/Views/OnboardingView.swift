import SwiftUI

/// Five beats: meet the bot, pick pests, pick a mode, placement tips, then camera.
/// The camera prompt only appears once the user knows why.
struct OnboardingView: View {
    @Environment(Sentry.self) private var sentry
    let finish: () -> Void
    @State private var page = 0
    private let pages = 5

    var body: some View {
        @Bindable var sentry = sentry
        VStack(spacing: 0) {
            progress
                .padding(.horizontal, 24)
                .padding(.top, 14)

            Group {
                switch page {
                case 0: hello
                case 1: pests(settings: $sentry.settings)
                case 2: mode(settings: $sentry.settings)
                case 3: tips
                default: camera
                }
            }
            .id(page)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
            .frame(maxHeight: .infinity)

            PrimaryButton(title: page == pages - 1 ? "Allow camera" : "Next") {
                if page < pages - 1 {
                    page += 1
                } else {
                    Task {
                        await sentry.start()
                        finish()
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .animation(.snappy(duration: 0.35), value: page)
    }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(0..<pages, id: \.self) { i in
                Capsule()
                    .fill(i == page ? Theme.red : (i < page ? Theme.ink : Theme.ghost))
                    .frame(width: i == page ? 20 : 6, height: 6)
                    .onTapGesture { if i < page { page = i } }
            }
            Spacer()
        }
    }

    // MARK: Pages

    private var hello: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer()
            BotFace(mood: .happy)
                .frame(maxWidth: .infinity)
            BotSpeech(text: "Hi. I'm Shoo.", pitch: 4.4, maxChars: 13)
            body("I watch for pests and scare them off with sound. Everything I see stays on this phone.")
            Spacer()
        }
        .padding(24)
    }

    private func pests(settings: Binding<SentrySettings>) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DotText("WHO BUGS YOU?", pitch: 3.6)
                body("Tap to pick. I'll ignore the rest.")
                PetGrid(settings: settings, showSound: false)
                Caption("I never scare these").padding(.top, 6)
                FriendsRow()
            }
            .padding(24)
        }
        .scrollIndicators(.hidden)
    }

    private func mode(settings: Binding<SentrySettings>) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            DotText("HOW HARD?", pitch: 4)
            body("You can change this any time in Config.")
            ModePicker(settings: settings)
            Spacer()
        }
        .padding(24)
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 22) {
            DotText("SET ME UP", pitch: 4)
            tip(Glyphs.bolt, "PLUG IN", "I run all day. Keep me on power.")
            tip(Glyphs.speaker, "VOLUME UP", "iOS won't let me turn myself up.")
            tip(Glyphs.eye, "AIM", "Point me at the spot they visit.")
            tip(Glyphs.moon, "DON'T LOCK", "Locked = blind. Tap the moon to dim instead.")
            Spacer()
        }
        .padding(24)
    }

    private var camera: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer()
            BotFace(mood: .surprised)
                .frame(maxWidth: .infinity)
            DotText("LET ME SEE", pitch: 4.4)
            body("The camera never leaves this phone. No video is saved — just one snapshot per visit.")
            Spacer()
        }
        .padding(24)
    }

    // MARK: Pieces

    private func body(_ text: String) -> some View {
        Text(text)
            .font(Theme.mono(14))
            .foregroundStyle(Theme.dim)
            .lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func tip(_ icon: [String], _ title: String, _ detail: String) -> some View {
        HStack(spacing: 16) {
            DotSprite(rows: icon, pitch: 2.8)
                .frame(width: 52, height: 52)
                .background(Circle().fill(Theme.panel))
                .overlay(Circle().strokeBorder(Theme.line))
            VStack(alignment: .leading, spacing: 8) {
                DotText(title, pitch: 2.6)
                Text(detail)
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
