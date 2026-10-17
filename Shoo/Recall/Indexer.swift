import Foundation
import SwiftData

/// Writes the searchable timeline: a Moment every ~4 s when quiet, every ~1 s when
/// something's happening, and a vision-model caption at most every 30 s while busy.
@MainActor
final class Indexer {
    var onCaption: ((String) -> Void)?

    private var context: ModelContext?
    private var lastMoment = Date.distantPast
    private var lastCaption = Date.distantPast
    private var lastPrune = Date.distantPast
    private var captioning = false

    func attach(_ context: ModelContext) {
        self.context = context
    }

    func ingest(_ f: DetectionFrame, threshold: Float, indexHours: Int, allowCaptions: Bool) {
        guard let context else { return }
        let busy = f.moving || f.confidence >= threshold * 0.6 || f.guardedConfidence >= 0.4
        guard f.timestamp.timeIntervalSince(lastMoment) >= (busy ? 1 : 4) else { return }
        lastMoment = f.timestamp

        let moment = Moment(
            date: f.timestamp,
            labels: f.topLabels.map { "\($0.0) \(String(format: "%.2f", $0.1))" }.joined(separator: " "),
            species: f.species,
            confidence: Double(f.confidence),
            guarded: f.guarded,
            guardedConfidence: Double(f.guardedConfidence),
            motion: f.moving,
            dark: f.luma < DetectionFrame.darkLuma,
            thumb: f.thumbnail.flatMap(MomentStore.save)
        )
        context.insert(moment)

        if busy, allowCaptions, !captioning, let jpeg = f.thumbnail,
           f.timestamp.timeIntervalSince(lastCaption) > 30, Intelligence.canSee {
            captioning = true
            lastCaption = f.timestamp
            Task {
                let caption = await Intelligence.caption(jpeg: jpeg)
                moment.caption = caption
                captioning = false
                if let caption { onCaption?(caption) }
            }
        }

        if f.timestamp.timeIntervalSince(lastPrune) > 600 {
            lastPrune = f.timestamp
            prune(olderThan: indexHours)
        }
    }

    private func prune(olderThan hours: Int) {
        guard let context else { return }
        let cutoff = Date().addingTimeInterval(-Double(hours) * 3600)
        let old = FetchDescriptor<Moment>(predicate: #Predicate { $0.date < cutoff })
        for m in (try? context.fetch(old)) ?? [] {
            MomentStore.delete(m.thumb)
            context.delete(m)
        }
        try? context.save()
    }
}
