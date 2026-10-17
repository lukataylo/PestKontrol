import Vision
import CoreML
import QuartzCore

struct DetectionFrame {
    static let darkLuma: Float = 0.08

    var species: Species?
    var confidence: Float = 0
    var guarded: Guarded?
    var guardedConfidence: Float = 0
    /// Normalized, top-left origin.
    var box: CGRect?
    var moving = false
    /// Strongest raw labels this frame — shown by the "see what I see" overlay.
    var topLabels: [(String, Float)] = []
    var luma: Float = 0.5
    var snapshot: Data?
    /// Small frame for the search index — taken every ~10 s, or every second while busy.
    var thumbnail: Data?
    var timestamp = Date()
}

protocol PestDetector: AnyObject {
    var engineName: String { get }
    func detect(_ buffer: CVPixelBuffer) throws -> DetectionFrame
}

enum DetectorFactory {
    /// A bundled `PestDetector.mlmodel` wins; otherwise Apple's built-in classifier.
    static func make() -> PestDetector {
        CoreMLPestDetector() ?? VisionPestDetector()
    }
}

enum Scoring {
    static func species(_ s: [String: Float]) -> (Species?, Float) {
        var scores: [Species: Float] = [:]
        for sp in Species.allCases {
            scores[sp] = sp.labels.map { (s[$0.key] ?? 0) * $0.value }.max() ?? 0
        }
        // Apple's model usually says "bird", rarely "pigeon". Treat unnamed birds
        // as pigeons unless the gull signal is comparatively strong.
        let pigeon = scores[.pigeon] ?? 0, gull = scores[.gull] ?? 0
        let bird = max(s["bird"] ?? 0, pigeon, gull)
        if gull > 0, gull >= max(pigeon, bird * 0.3) {
            scores[.gull] = bird
        } else {
            scores[.pigeon] = max(pigeon, bird * 0.9)
        }
        guard let best = scores.max(by: { $0.value < $1.value }), best.value > 0 else { return (nil, 0) }
        return (best.key, best.value)
    }

    static func guarded(_ scores: [String: Float]) -> (Guarded?, Float) {
        var best: (Guarded?, Float) = (nil, 0)
        for g in Guarded.allCases {
            let v = g.labels.map { scores[$0] ?? 0 }.max() ?? 0
            if v > best.1 { best = (g, v) }
        }
        return best
    }

    private static let generic: Set<String> = ["animal", "mammal", "outdoor", "structure", "land", "grass", "sky", "material", "plant", "wood_processed", "textile"]

    static func top(_ scores: [String: Float], _ n: Int = 4) -> [(String, Float)] {
        scores.filter { !generic.contains($0.key) && $0.value >= 0.05 }
            .sorted { $0.value > $1.value }
            .prefix(n)
            .map { ($0.key, $0.value) }
    }
}

/// Apple's on-device classifier (1,300+ labels incl. pigeon, fox, rat, gull).
///
/// Whole-frame classification misses small animals: a fox filling a third of
/// the frame scores ~0.06 whole-frame but ~0.98 when cropped. So each tick
/// classifies several regions — full frame, what moved, what stands out, and a
/// rotating 3×3 tile grid — and keeps the best evidence from the last ~1 s.
final class VisionPestDetector: PestDetector {
    let engineName = "APPLE VISION"

    private struct Hit {
        var scores: [String: Float]
        var rect: CGRect
        var at: CFTimeInterval
    }

    private static let full = CGRect(x: 0, y: 0, width: 1, height: 1)
    private static let tiles: [CGRect] = (0..<3).flatMap { i in
        (0..<3).map { j in CGRect(x: Double(i) * 0.25, y: Double(j) * 0.25, width: 0.5, height: 0.5) }
    }

    private let saliency = VNGenerateObjectnessBasedSaliencyImageRequest()
    private let humans = VNDetectHumanRectanglesRequest()
    private let pets = VNRecognizeAnimalsRequest()
    private let motion = MotionDetector()
    private var tick = 0
    private var tileMemory: [Int: Hit] = [:]

    func detect(_ buffer: CVPixelBuffer) throws -> DetectionFrame {
        // Buffers should arrive portrait; if rotation wasn't applied, let Vision rotate.
        let landscape = CVPixelBufferGetWidth(buffer) > CVPixelBufferGetHeight(buffer)
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: landscape ? .right : .up)
        try handler.perform([saliency, humans, pets])

        // Regions are in Vision space: normalized, bottom-left origin.
        let moving = landscape ? nil : motion.update(buffer)
        let salient = (saliency.results?.first?.salientObjects ?? [])
            .sorted { $0.confidence > $1.confidence }
            .prefix(2)
            .map { Self.pad($0.boundingBox, by: 0.25) }
        var regions = [Self.full] + salient
        if let moving { regions.append(moving) }
        let tileIDs = (0..<3).map { (tick % 3) * 3 + $0 }
        tick += 1
        let firstTile = regions.count
        regions += tileIDs.map { Self.tiles[$0] }

        let requests = regions.map { region -> VNClassifyImageRequest in
            let r = VNClassifyImageRequest()
            r.regionOfInterest = region
            return r
        }
        try handler.perform(requests)

        let now = CACurrentMediaTime()
        var hits: [Hit] = []
        for (i, request) in requests.enumerated() {
            let scores = Dictionary((request.results ?? []).map { ($0.identifier, $0.confidence) }, uniquingKeysWith: max)
            let hit = Hit(scores: scores, rect: regions[i], at: now)
            if i >= firstTile { tileMemory[tileIDs[i - firstTile]] = hit } else { hits.append(hit) }
        }
        hits += tileMemory.values.filter { now - $0.at < 1.2 }

        var frame = DetectionFrame()
        frame.moving = moving != nil
        var merged: [String: Float] = [:]
        var winner: CGRect?
        for hit in hits {
            merged.merge(hit.scores, uniquingKeysWith: max)
            let (s, c) = Scoring.species(hit.scores)
            if let s, c > frame.confidence {
                frame.species = s
                frame.confidence = c
                winner = hit.rect
            }
            let (g, gc) = Scoring.guarded(hit.scores)
            if let g, gc > frame.guardedConfidence {
                frame.guarded = g
                frame.guardedConfidence = gc
            }
        }

        // Dedicated detectors are sharper for friends than the scene classifier.
        if let person = humans.results?.max(by: { $0.confidence < $1.confidence }), person.confidence > frame.guardedConfidence {
            frame.guarded = .person
            frame.guardedConfidence = person.confidence
        }
        for animal in pets.results ?? [] {
            for label in animal.labels {
                let g: Guarded? = label.identifier == "Cat" ? .cat : label.identifier == "Dog" ? .dog : nil
                if let g, label.confidence > frame.guardedConfidence {
                    frame.guarded = g
                    frame.guardedConfidence = label.confidence
                }
            }
        }

        // Tiles are coarse; draw the box around what moved or stood out inside the winning region.
        if let winner {
            let tight = ([moving].compactMap { $0 } + salient)
                .first { $0.intersects(winner) && $0.width * $0.height < winner.width * winner.height }
            frame.box = (tight ?? winner).flippedY
        }
        frame.topLabels = Scoring.top(merged)
        return frame
    }

    private static func pad(_ r: CGRect, by f: CGFloat) -> CGRect {
        r.insetBy(dx: -r.width * f, dy: -r.height * f).intersection(full)
    }
}

/// Cheap frame-differencing on the luma plane. Returns the moving area, padded,
/// in Vision coordinates — or nil when nothing (or everything) moved.
final class MotionDetector {
    private let cols = 18, rows = 32
    private var background: [Float] = []

    func update(_ buffer: CVPixelBuffer) -> CGRect? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard CVPixelBufferGetPlaneCount(buffer) > 0,
              let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)
        else { return nil }

        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        let cw = width / cols, ch = height / rows

        var cells = [Float](repeating: 0, count: cols * rows)
        for r in 0..<rows {
            for c in 0..<cols {
                var sum = 0, n = 0
                for y in stride(from: r * ch, to: (r + 1) * ch, by: 4) {
                    for x in stride(from: c * cw, to: (c + 1) * cw, by: 4) {
                        sum += Int(pixels[y * rowBytes + x])
                        n += 1
                    }
                }
                cells[r * cols + c] = n > 0 ? Float(sum) / Float(n) / 255 : 0
            }
        }
        guard background.count == cells.count else {
            background = cells
            return nil
        }

        var minC = cols, maxC = -1, minR = rows, maxR = -1, count = 0
        for i in cells.indices {
            if abs(cells[i] - background[i]) > 0.07 {
                let r = i / cols, c = i % cols
                minC = min(minC, c); maxC = max(maxC, c)
                minR = min(minR, r); maxR = max(maxR, r)
                count += 1
            }
            background[i] = background[i] * 0.9 + cells[i] * 0.1
        }
        // One cell is noise; half the frame is a lighting change or a bumped phone.
        guard count >= 2, count < cells.count / 2 else { return nil }

        let x = CGFloat(minC) / CGFloat(cols), w = CGFloat(maxC - minC + 1) / CGFloat(cols)
        let yTop = CGFloat(minR) / CGFloat(rows), h = CGFloat(maxR - minR + 1) / CGFloat(rows)
        let rect = CGRect(x: x, y: 1 - yTop - h, width: w, height: h)
        return rect.insetBy(dx: -w * 0.3, dy: -h * 0.3).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }
}

/// Custom object detector (e.g. Create ML or YOLO export) named `PestDetector`.
/// Labels should match species/guarded raw values: pigeon, fox, rat, cat, person…
final class CoreMLPestDetector: PestDetector {
    let engineName = "CUSTOM MODEL"
    private let request: VNCoreMLRequest

    init?() {
        guard let url = Bundle.main.url(forResource: "PestDetector", withExtension: "mlmodelc"),
              let model = try? MLModel(contentsOf: url),
              let vnModel = try? VNCoreMLModel(for: model)
        else { return nil }
        request = VNCoreMLRequest(model: vnModel)
        request.imageCropAndScaleOption = .scaleFill
    }

    func detect(_ buffer: CVPixelBuffer) throws -> DetectionFrame {
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up)
        try handler.perform([request])

        var scores: [String: Float] = [:]
        var boxes: [String: CGRect] = [:]
        for case let obs as VNRecognizedObjectObservation in request.results ?? [] {
            guard let top = obs.labels.first else { continue }
            let id = top.identifier.lowercased()
            if top.confidence > scores[id, default: 0] {
                scores[id] = top.confidence
                boxes[id] = obs.boundingBox.flippedY
            }
        }
        for case let obs as VNClassificationObservation in request.results ?? [] {
            scores[obs.identifier.lowercased()] = obs.confidence
        }

        var frame = DetectionFrame()
        (frame.species, frame.confidence) = Scoring.species(scores)
        (frame.guarded, frame.guardedConfidence) = Scoring.guarded(scores)
        if let s = frame.species {
            frame.box = s.labels.keys.compactMap { boxes[$0] }.first
        }
        frame.topLabels = Scoring.top(scores)
        return frame
    }
}

extension CGRect {
    /// Vision uses a bottom-left origin; SwiftUI uses top-left.
    var flippedY: CGRect { CGRect(x: minX, y: 1 - maxY, width: width, height: height) }
}
