import SwiftUI
import SwiftData
import AVKit

/// Search hours of footage in plain language, ask what happened,
/// see what was spotted, and set "when… then…" rules.
struct AskView: View {
    @Environment(Sentry.self) private var sentry
    @Environment(\.modelContext) private var context
    @Query(sort: \Sighting.date, order: .reverse) private var sightings: [Sighting]

    @State private var question = ""
    @State private var thinking = false
    @State private var asked = ""
    @State private var answer: RecallEngine.Answer?
    @State private var spotted: [Clip] = []
    @State private var playing: Clip?
    @State private var ruleText = ""
    @State private var draft: Rule?
    @State private var parsing = false
    @State private var storage = ""
    @FocusState private var focus: Field?

    private enum Field { case ask, rule, hook }

    private let suggestions = [
        "What happened overnight?",
        "Show me every pigeon today",
        "Was anyone here this morning?",
        "Any movement in the last hour?",
        "When did the fox come?",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom) {
                    ScreenTitle(text: "ASK")
                    Spacer()
                    Caption(Intelligence.status)
                }
                .padding(.bottom, 4)

                askBar
                suggestionRow

                if thinking {
                    thinkingCard
                } else if let answer {
                    answerCard(answer)
                }

                Caption("Spotted · last 24h").padding(.top, 8)
                spottedList

                Caption("When · then").padding(.top, 8)
                rules

                Caption("Footage").padding(.top, 8)
                footage
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .sheet(item: $playing) { ClipPlayer(clip: $0) }
        .task {
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    // MARK: Ask / search

    private var askBar: some View {
        HStack(spacing: 12) {
            DotSprite(rows: Glyphs.search, pitch: 2.4, color: Theme.dim)
            TextField("", text: $question, prompt: Text("Search or ask about your footage").foregroundStyle(Theme.dim))
                .font(Theme.mono(14))
                .foregroundStyle(Theme.ink)
                .tint(Theme.red)
                .submitLabel(.search)
                .focused($focus, equals: .ask)
                .onSubmit(run)
            if !question.isEmpty {
                DotIconButton(icon: Glyphs.arrow, label: "Ask", fill: Theme.ink, fg: .black, size: 38, action: run)
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 9)
        .frame(height: 56)
        .panelStyle(cornerRadius: 28, seed: 71)
    }

    private var suggestionRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { s in
                    Button {
                        question = s
                        run()
                    } label: {
                        Chip(text: s)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var thinkingCard: some View {
        HStack(spacing: 16) {
            BotFace(mood: .suspicious).frame(width: 96)
            BotSpeech(text: "Searching footage...", pitch: 2.2, maxChars: 16)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelStyle(seed: 72)
    }

    private func answerCard(_ a: RecallEngine.Answer) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                BotFace(mood: a.clips.isEmpty ? .idle : .surprised).frame(width: 72)
                VStack(alignment: .leading, spacing: 8) {
                    Caption(asked)
                    Text(a.text)
                        .font(Theme.mono(14))
                        .foregroundStyle(Theme.ink)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !a.clips.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(a.clips) { clip in
                        ClipTile(clip: clip).onTapGesture { playing = clip }
                    }
                }
            }
            Caption(a.usedAI ? "Answered on this phone" : "Keyword match · on this phone")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelStyle(seed: 73, splatter: Theme.slasher ? .topTrailing : nil)
    }

    private func run() {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !thinking else { return }
        focus = nil
        asked = q
        thinking = true
        Task {
            if Self.isQuestion(q) {
                answer = await RecallEngine.ask(q, in: context, sightings: sightings,
                                                horizonHours: sentry.recall.indexHours,
                                                pestThreshold: sentry.settings.tuning.threshold)
            } else {
                let parsed = await RecallEngine.parse(q, horizonHours: sentry.recall.indexHours)
                let clips = RecallEngine.search(parsed, in: context)
                answer = RecallEngine.Answer(
                    text: clips.isEmpty ? "Nothing matched “\(q)”." : "\(clips.count) moment\(clips.count == 1 ? "" : "s") matched.",
                    clips: clips, usedAI: false)
            }
            thinking = false
        }
    }

    private static func isQuestion(_ q: String) -> Bool {
        let first = q.lowercased().split(separator: " ").first.map(String.init) ?? ""
        return q.hasSuffix("?") || ["what", "when", "was", "were", "did", "how", "who", "why", "is", "are", "any", "has", "tell"].contains(first)
    }

    // MARK: Spotted

    @ViewBuilder
    private var spottedList: some View {
        if spotted.isEmpty {
            Card {
                Text("Nothing spotted yet. Events appear here as the camera sees them.")
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.dim)
            }
        } else {
            LazyVStack(spacing: 8) {
                ForEach(spotted.prefix(20)) { clip in
                    HStack(spacing: 14) {
                        DotSprite(rows: clip.sprite, pitch: 2.2)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 6) {
                            DotText(clip.title, pitch: 2.2)
                            Caption(clip.caption.map { "\(clip.timeRange) · \($0)" } ?? clip.timeRange)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        ClipThumb(name: clip.thumb)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .padding(10)
                    .panelStyle(cornerRadius: 18, seed: Int(clip.start.timeIntervalSince1970) % 991)
                    .contentShape(Rectangle())
                    .onTapGesture { playing = clip }
                }
            }
        }
    }

    private func refresh() {
        let now = Date()
        spotted = RecallEngine.spot(DateInterval(start: now.addingTimeInterval(-86400), end: now), in: context,
                                    pestThreshold: sentry.settings.tuning.threshold)
        let gb = Double(VideoRecorder.bytesUsed()) / 1_000_000_000
        storage = String(format: "%.1f GB", gb)
    }

    // MARK: Rules

    @ViewBuilder
    private var rules: some View {
        @Bindable var sentry = sentry
        ForEach($sentry.rules) { $rule in
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(rule.text)
                        .font(Theme.mono(13))
                        .foregroundStyle(rule.enabled ? Theme.ink : Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                    RuleSummary(rule: rule)
                }
                Spacer()
                NToggle(isOn: $rule.enabled)
            }
            .padding(16)
            .panelStyle(seed: rule.text.count)
            .contextMenu {
                Button("Delete rule", systemImage: "trash", role: .destructive) {
                    sentry.rules.removeAll { $0.id == rule.id }
                }
            }
        }

        if let draft {
            draftCard(draft)
        } else {
            HStack(spacing: 10) {
                TextField("", text: $ruleText,
                          prompt: Text("If a fox comes at night, flash the lamp and tell me").foregroundStyle(Theme.dim),
                          axis: .vertical)
                    .font(Theme.mono(13))
                    .foregroundStyle(Theme.ink)
                    .tint(Theme.red)
                    .lineLimit(1...3)
                    .focused($focus, equals: .rule)
                    .submitLabel(.done)
                    .onSubmit(parseRule)
                if parsing {
                    ProgressView().tint(Theme.ink)
                } else if !ruleText.isEmpty {
                    DotIconButton(icon: Glyphs.arrow, label: "Make rule", fill: Theme.ink, fg: .black, size: 38, action: parseRule)
                }
            }
            .padding(14)
            .panelStyle(seed: 74)
        }

        if !sentry.firings.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(sentry.firings.prefix(5)) { f in
                    Caption("\(Fmt.clock.string(from: f.date)) · \(f.what)")
                }
            }
            .padding(.horizontal, 6)
        }
    }

    private func draftCard(_ rule: Rule) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Caption("New rule · check it")
            RuleSummary(rule: rule)
            if rule.actions.contains(.webhook) {
                TextField("", text: Binding(get: { draft?.webhook ?? "" }, set: { draft?.webhook = $0.isEmpty ? nil : $0 }),
                          prompt: Text("https://… webhook URL").foregroundStyle(Theme.dim))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.ink)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .hook)
                    .padding(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.ghost))
            }
            HStack(spacing: 10) {
                Button {
                    if let d = draft {
                        sentry.rules.append(d)
                        if d.actions.contains(.notify) { Notifier.requestPermission() }
                    }
                    draft = nil
                    ruleText = ""
                } label: {
                    Chip(text: "Save rule", fill: Theme.red, fg: .white, stroke: .clear)
                }
                Button { draft = nil } label: { Chip(text: "Edit") }
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelStyle(seed: 75)
    }

    private func parseRule() {
        let text = ruleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !parsing else { return }
        focus = nil
        parsing = true
        Task {
            draft = await RuleParser.parse(text)
            parsing = false
        }
    }

    // MARK: Footage

    private var footage: some View {
        @Bindable var sentry = sentry
        return Card(seed: 76) {
            HStack(spacing: 12) {
                Text("Record footage")
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.ink.opacity(0.85))
                Spacer()
                NToggle(isOn: $sentry.recall.record)
            }
            StepperRow(label: "Keep", value: "\(sentry.recall.keepHours)H") {
                sentry.recall.keepHours = max(2, sentry.recall.keepHours - (sentry.recall.keepHours > 12 ? 6 : 2))
            } increment: {
                sentry.recall.keepHours = min(72, sentry.recall.keepHours + (sentry.recall.keepHours >= 12 ? 6 : 2))
            }
            Caption("\(storage) on this phone · ~0.5 GB per hour · never uploaded")
        }
    }
}

/// WHEN … THEN … chips.
struct RuleSummary: View {
    let rule: Rule

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { content }
            VStack(alignment: .leading, spacing: 6) { content }
        }
    }

    @ViewBuilder
    private var content: some View {
        Chip(text: "When \(rule.whenText)")
        HStack(spacing: 6) {
            ForEach(rule.actions, id: \.self) { a in
                Chip(text: a.code, fill: Theme.red.opacity(0.9), fg: .white, stroke: .clear)
            }
        }
    }
}

struct ClipTile: View {
    let clip: Clip

    var body: some View {
        ClipThumb(name: clip.thumb)
            .frame(height: 150)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 5) {
                    DotText(clip.title, pitch: 1.9, color: .white)
                    Text(clip.timeRange).font(Theme.mono(10, .medium)).foregroundStyle(.white.opacity(0.8))
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
            }
            .overlay(alignment: .topTrailing) {
                DotSprite(rows: Glyphs.play, pitch: 1.8, color: .white).padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
    }
}

struct ClipThumb: View {
    let name: String?

    var body: some View {
        if let name, let image = UIImage(contentsOfFile: MomentStore.url(for: name).path) {
            Image(uiImage: image).resizable().scaledToFill()
                .grayscale(Theme.slasher ? 1 : 0)
                .contrast(Theme.slasher ? 1.3 : 1)
        } else {
            ZStack {
                Theme.panel
                DotGrid(spacing: 7)
            }
        }
    }
}

/// Plays recorded footage from a few seconds before the moment.
struct ClipPlayer: View {
    let clip: Clip
    @Environment(Sentry.self) private var sentry
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var missing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                DotText(clip.title, pitch: 4)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 36, height: 36)
                        .overlay(Circle().strokeBorder(Theme.ghost))
                }
                .buttonStyle(PressStyle())
            }
            Caption("\(Fmt.stamp.string(from: clip.start))\(clip.caption.map { " · \($0)" } ?? "")")
                .fixedSize(horizontal: false, vertical: true)
            ZStack {
                Theme.panel
                if let player {
                    VideoPlayer(player: player)
                } else if missing {
                    ClipThumb(name: clip.thumb)
                    VStack {
                        Spacer()
                        Chip(text: "No footage kept for this moment", fill: .black.opacity(0.6))
                            .padding(14)
                    }
                } else {
                    ProgressView().tint(Theme.ink)
                }
            }
            .aspectRatio(videoAspect, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Theme.black)
        .presentationBackground(Theme.black)
        .task {
            guard let (url, offset) = await sentry.recorder.locate(clip.start) else {
                missing = true
                return
            }
            let p = AVPlayer(url: url)
            await p.seek(to: CMTime(seconds: max(0, offset - 3), preferredTimescale: 600))
            p.play()
            player = p
        }
        .onDisappear { player?.pause() }
    }
}
