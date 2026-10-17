import SwiftUI
import SwiftData

struct LogView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Sighting.date, order: .reverse) private var sightings: [Sighting]
    @State private var selected: Sighting?
    @State private var confirmClear = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom) {
                    ScreenTitle(text: "LOG")
                    Spacer()
                    Caption("\(sightings.count) events")
                }
                .padding(.bottom, 6)

                tallies

                Card(title: "Activity by hour") {
                    HourChart(hours: hourCounts)
                        .frame(height: 70)
                    HStack {
                        ForEach(["00", "06", "12", "18", "23"], id: \.self) { h in
                            Caption(h)
                            if h != "23" { Spacer() }
                        }
                    }
                }

                if sightings.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            DotText("NOTHING YET", pitch: 3)
                            Caption("Visits appear here with a snapshot")
                        }
                    }
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(sightings) { s in
                            SightingRow(sighting: s)
                                .onTapGesture { selected = s }
                                .contextMenu {
                                    Button("Delete", systemImage: "trash", role: .destructive) { delete(s) }
                                }
                        }
                    }
                    Button { confirmClear = true } label: {
                        Chip(text: "Clear log", stroke: Theme.red)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .sheet(item: $selected) { SightingDetail(sighting: $0) }
        .confirmationDialog("Delete every sighting and snapshot?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear log", role: .destructive) { sightings.forEach(delete) }
        }
    }

    private var tallies: some View {
        Card {
            HStack(spacing: 0) {
                ForEach(Species.allCases) { sp in
                    let n = sightings.filter { $0.species == sp }.count
                    VStack(spacing: 10) {
                        DotSprite(rows: Pets.sprite(sp), pitch: 2.4, dimmed: n == 0)
                            .frame(height: 27, alignment: .bottom)
                        DotText("\(n)", pitch: 3, color: n > 0 ? Theme.ink : Theme.ghost)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(n) \(sp.code)")
                }
            }
        }
    }

    private var hourCounts: [Int] {
        var counts = Array(repeating: 0, count: 24)
        for s in sightings { counts[Calendar.current.component(.hour, from: s.date)] += 1 }
        return counts
    }

    private func delete(_ s: Sighting) {
        SightingStore.delete(s.imageFile)
        context.delete(s)
        try? context.save()
    }
}

/// 24 columns of dots; current hour in red.
struct HourChart: View {
    let hours: [Int]
    var rows = 7

    var body: some View {
        Canvas { ctx, size in
            let pitch = size.width / 24
            let rowPitch = size.height / CGFloat(rows)
            let d = min(pitch, rowPitch) * 0.6
            let peak = max(hours.max() ?? 0, 1)
            let now = Calendar.current.component(.hour, from: .now)
            for h in 0..<24 {
                let lit = hours[h] == 0 ? 0 : max(1, Int((Double(hours[h]) / Double(peak) * Double(rows)).rounded()))
                for r in 0..<rows {
                    let rect = CGRect(x: CGFloat(h) * pitch + (pitch - d) / 2,
                                      y: size.height - CGFloat(r + 1) * rowPitch + (rowPitch - d) / 2,
                                      width: d, height: d)
                    let color = r < lit ? (h == now ? Theme.red : Theme.ink) : Theme.ghost.opacity(0.35)
                    ctx.fill(Path(ellipseIn: rect), with: .color(color))
                }
            }
        }
    }
}

struct SightingRow: View {
    let sighting: Sighting

    var body: some View {
        HStack(spacing: 14) {
            SnapshotImage(file: sighting.imageFile, species: sighting.species)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 9) {
                DotText(sighting.species?.code ?? "?", pitch: 2.6)
                Caption("\(Fmt.stamp.string(from: sighting.date)) · \(Int(sighting.confidence * 100))%")
            }
            Spacer(minLength: 4)
            OutcomeChip(sighting: sighting)
        }
        .padding(10)
        .panelStyle(seed: Int(sighting.date.timeIntervalSince1970) % 997)
        .contentShape(Rectangle())
    }
}

struct OutcomeChip: View {
    let sighting: Sighting

    var body: some View {
        switch sighting.outcome {
        case .fired: Chip(text: sighting.pattern?.code ?? "Fired", fill: Theme.red, fg: .white, stroke: .clear)
        case .logged: Chip(text: "Logged")
        case .quiet: Chip(text: "Quiet")
        }
    }
}

struct SnapshotImage: View {
    let file: String?
    var species: Species?

    var body: some View {
        if let file, let image = UIImage(contentsOfFile: SightingStore.url(for: file).path) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            ZStack {
                Theme.black
                if let species { DotSprite(rows: Pets.sprite(species), pitch: 3, dimmed: true) }
            }
        }
    }
}

struct SightingDetail: View {
    let sighting: Sighting
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    DotText(sighting.species?.code ?? "?", pitch: 6)
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
                SnapshotImage(file: sighting.imageFile, species: sighting.species)
                    .aspectRatio(videoAspect, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                Card {
                    fact("Time", Fmt.stamp.string(from: sighting.date))
                    fact("Confidence", "\(Int(sighting.confidence * 100))%")
                    fact("Outcome", sighting.outcome.rawValue)
                    fact("Sound", sighting.pattern?.code ?? "None")
                    fact("Light", sighting.lowLight ? "Night" : "Day")
                }
                Button {
                    SightingStore.delete(sighting.imageFile)
                    context.delete(sighting)
                    try? context.save()
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        DotSprite(rows: Glyphs.trash, pitch: 2.4, color: Theme.red)
                        DotText("DELETE", pitch: 2.6, color: Theme.red)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .overlay(Capsule().strokeBorder(Theme.red.opacity(0.6)))
                }
                .buttonStyle(PressStyle())
            }
            .padding(20)
        }
        .background(Theme.black)
        .presentationBackground(Theme.black)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack {
            Caption(label)
            Spacer()
            Text(value.uppercased())
                .font(Theme.mono(13, .medium))
                .foregroundStyle(Theme.ink)
        }
    }
}
