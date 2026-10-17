import SwiftUI
import SwiftData
import AVFoundation
import Observation
import UserNotifications

/// What the sentry is doing right now. Drives the bot's face and voice.
enum SentryStatus: Equatable {
    case offline
    case idle
    case lowLight
    case tracking(Species, Int, Int)
    case firing(Species, SoundPattern)
    case logged(Species)
    case quiet(Species)
    case cooldown(Int)
    case held(Guarded)
}

/// The brain: takes detections, confirms them over several frames,
/// respects safety + cooldown rules, fires the deterrent and logs the visit.
@Observable @MainActor
final class Sentry {
    var settings = SentrySettings.load() {
        didSet {
            settings.save()
            pipeline.snapshotThreshold = Float(settings.tuning.threshold) * 0.8
        }
    }
    var armed = false
    var torch = false { didSet { camera.setTorch(torch) } }
    var stealth = false
    var running = false
    var cameraDenied = false
    var frame = DetectionFrame()
    var status: SentryStatus = .offline
    var thermal: ProcessInfo.ThermalState = .nominal
    var volumeLow = false
    var recall = RecallSettings.load() {
        didSet {
            recall.save()
            recorder.enabled = recall.record
            recorder.keepHours = recall.keepHours
        }
    }
    var rules = RuleStore.load() { didSet { RuleStore.save(rules) } }
    var firings: [RuleFiring] = []
    let engineName: String

    let camera = CameraService()
    let previewTap = PreviewTap()
    let recorder = VideoRecorder()
    private let indexer = Indexer()
    private let pipeline: FramePipeline
    private let sound = SoundEngine()
    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var streak = 0
    @ObservationIgnored private var streakSpecies: Species?
    @ObservationIgnored private var cooldownUntil = Date.distantPast
    @ObservationIgnored private var holdStatusUntil = Date.distantPast
    @ObservationIgnored private var thermalObserver: NSObjectProtocol?
    @ObservationIgnored private var volumeObserver: NSKeyValueObservation?
    @ObservationIgnored private var ruleLastFired: [UUID: Date] = [:]

    init() {
        let detector = DetectorFactory.make()
        engineName = detector.engineName
        pipeline = FramePipeline(detector: detector)
        pipeline.snapshotThreshold = Float(settings.tuning.threshold) * 0.8
        pipeline.onResult = { [weak self] frame in self?.ingest(frame) }
        recorder.enabled = recall.record
        recorder.keepHours = recall.keepHours
        Self.wire(camera, to: pipeline, tap: previewTap, recorder: recorder)
        indexer.onCaption = { [weak self] caption in
            self?.runRules(subject: "Scene", detail: caption) { trigger in
                if case .keyword(let k) = trigger { return caption.lowercased().contains(k) }
                return false
            }
        }
        UNUserNotificationCenter.current().delegate = ForegroundNotifications.shared
    }

    // Built outside the main actor: frames arrive on the camera queue.
    nonisolated private static func wire(_ camera: CameraService, to pipeline: FramePipeline, tap: PreviewTap, recorder: VideoRecorder) {
        camera.onBuffer = { buffer, time in
            pipeline.handle(buffer)
            tap.push(buffer)
            recorder.append(buffer, at: time)
        }
    }

    func attach(_ context: ModelContext) {
        self.context = context
        indexer.attach(context)
    }

    func start() async {
        guard !running else { return }
        let granted = await CameraService.requestAccess()
        cameraDenied = !granted
        guard granted else { return }
        camera.start()
        sound.prepare()
        running = true
        status = .idle
        UIApplication.shared.isIdleTimerDisabled = true
        UIDevice.current.isBatteryMonitoringEnabled = true
        observeThermal()
        observeVolume()
    }

    func test(_ pattern: SoundPattern) {
        sound.play(pattern, gain: Float(settings.tuning.gain))
    }

    // MARK: - Decision loop

    private func ingest(_ f: DetectionFrame) {
        frame = f
        let now = Date()
        let tuning = settings.tuning
        let threshold = Float(tuning.threshold)

        indexer.ingest(f, threshold: threshold, indexHours: recall.indexHours,
                       allowCaptions: thermal == .nominal || thermal == .fair)
        triggerRules(for: f)

        // A clear person always wins. Anything else only wins if it outranks the pest —
        // Apple's pet detector calls foxes "Dog" (0.67 on a clear fox photo), and the
        // scene classifier sees faint "people" (~0.3) in busy balconies.
        if settings.protectLock, let g = f.guarded,
           (g == .person && f.guardedConfidence >= 0.5)
            || (f.guardedConfidence >= 0.3 && (f.species == nil || f.guardedConfidence >= f.confidence)) {
            streak = 0
            if now >= holdStatusUntil { status = .held(g) }
            return
        }

        guard let species = f.species, f.confidence >= threshold, settings.enabled.contains(species) else {
            streak = max(0, streak - 1)
            if now >= holdStatusUntil { status = restingStatus(now, f) }
            return
        }

        streak = species == streakSpecies ? streak + 1 : 1
        streakSpecies = species

        if now < cooldownUntil {
            if now >= holdStatusUntil { status = restingStatus(now, f) }
            return
        }
        if streak < tuning.confirmFrames {
            status = .tracking(species, streak, tuning.confirmFrames)
            return
        }

        streak = 0
        cooldownUntil = now.addingTimeInterval(tuning.cooldown)
        holdStatusUntil = now.addingTimeInterval(3)

        var played: SoundPattern?
        let outcome: Outcome
        if !armed {
            outcome = .logged
            status = .logged(species)
        } else if settings.isQuiet(at: now) {
            outcome = .quiet
            status = .quiet(species)
        } else {
            let voice = sound.play(settings.pattern(for: species), gain: Float(tuning.gain))
            played = voice
            outcome = .fired
            status = .firing(species, voice)
        }
        record(species, f, outcome, played)
        runRules(subject: species.code.capitalized, detail: "\(Int(f.confidence * 100))%", species: species, confidence: f.confidence) { trigger in
            if case .pest(let list) = trigger { return list.isEmpty || list.contains(species) }
            return false
        }
    }

    // MARK: - Rules

    /// Frame-level triggers. Pest rules fire from the confirmed-visit path above.
    private func triggerRules(for f: DetectionFrame) {
        if f.guarded == .person, f.guardedConfidence >= 0.5 {
            runRules(subject: "Person", detail: "\(Int(f.guardedConfidence * 100))%") { $0 == .person }
        } else if let g = f.guarded, g != .person, f.guardedConfidence >= 0.5, f.guardedConfidence >= f.confidence {
            runRules(subject: g.code.capitalized, detail: "friend") { $0 == .friend }
        }
        if f.moving {
            runRules(subject: "Movement", detail: "") { $0 == .motion }
        }
    }

    private func runRules(subject: String, detail: String, species: Species? = nil, confidence: Float = 0,
                          matching: (Rule.Trigger) -> Bool) {
        let now = Date()
        for rule in rules where rule.active(at: now) && matching(rule.trigger) {
            if let last = ruleLastFired[rule.id], now.timeIntervalSince(last) < rule.cooldown { continue }
            ruleLastFired[rule.id] = now
            var did: [String] = []
            for action in rule.actions {
                switch action {
                case .deter:
                    let voice = sound.play(species.map { settings.pattern(for: $0) } ?? .mix, gain: Float(settings.tuning.gain))
                    did.append(voice.code)
                case .lamp:
                    strobe()
                    did.append("LAMP")
                case .notify:
                    Notifier.send("SHOO · \(subject)", detail.isEmpty ? rule.text : "\(detail) — \(rule.text)")
                    did.append("NOTIFY")
                case .webhook:
                    guard let url = rule.webhook else { continue }
                    Notifier.webhook(url, payload: [
                        "event": subject.lowercased(), "detail": detail, "rule": rule.text,
                        "confidence": Double(confidence), "time": ISO8601DateFormatter().string(from: now),
                    ])
                    did.append("WEBHOOK")
                }
            }
            firings.insert(RuleFiring(date: now, rule: rule.text, what: "\(subject) → \(did.joined(separator: " · "))"), at: 0)
            if firings.count > 30 { firings.removeLast() }
        }
    }

    /// Flash the torch a few times, then put it back how it was.
    private func strobe() {
        let restore = torch
        Task {
            for i in 0..<8 {
                camera.setTorch(i.isMultiple(of: 2))
                try? await Task.sleep(for: .milliseconds(220))
            }
            camera.setTorch(restore)
        }
    }

    private func restingStatus(_ now: Date, _ f: DetectionFrame) -> SentryStatus {
        if now < cooldownUntil {
            return .cooldown(Int(cooldownUntil.timeIntervalSince(now).rounded(.up)))
        }
        return f.luma < DetectionFrame.darkLuma ? .lowLight : .idle
    }

    private func record(_ species: Species, _ f: DetectionFrame, _ outcome: Outcome, _ pattern: SoundPattern?) {
        guard let context else { return }
        let sighting = Sighting(
            date: f.timestamp,
            species: species,
            confidence: Double(f.confidence),
            outcome: outcome,
            pattern: pattern,
            imageFile: f.snapshot.flatMap(SightingStore.save),
            lowLight: f.luma < DetectionFrame.darkLuma
        )
        context.insert(sighting)
        try? context.save()
    }

    // MARK: - Device health

    /// Live, not just at arm time — someone may turn the volume down later.
    private func observeVolume() {
        guard volumeObserver == nil else { return }
        volumeObserver = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.initial, .new]) { [weak self] session, _ in
            let low = session.outputVolume < 0.5
            Task { @MainActor in self?.volumeLow = low }
        }
    }

    private func observeThermal() {
        guard thermalObserver == nil else { return }
        updateThermal()
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateThermal() }
        }
    }

    /// A phone left on a windowsill all day gets hot. Back off the frame rate as it does.
    private func updateThermal() {
        thermal = ProcessInfo.processInfo.thermalState
        switch thermal {
        case .serious:
            pipeline.interval = 0.6
        case .critical:
            pipeline.interval = 1.5
            torch = false
        default:
            pipeline.interval = 0.25
        }
    }
}
