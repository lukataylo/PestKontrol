import SwiftUI
import SwiftData
import AVFoundation
import Observation

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
    let engineName: String

    let camera = CameraService()
    let previewTap = PreviewTap()
    private let pipeline: FramePipeline
    private let sound = SoundEngine()
    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var streak = 0
    @ObservationIgnored private var streakSpecies: Species?
    @ObservationIgnored private var cooldownUntil = Date.distantPast
    @ObservationIgnored private var holdStatusUntil = Date.distantPast
    @ObservationIgnored private var thermalObserver: NSObjectProtocol?
    @ObservationIgnored private var volumeObserver: NSKeyValueObservation?

    init() {
        let detector = DetectorFactory.make()
        engineName = detector.engineName
        pipeline = FramePipeline(detector: detector)
        pipeline.snapshotThreshold = Float(settings.tuning.threshold) * 0.8
        pipeline.onResult = { [weak self] frame in self?.ingest(frame) }
        Self.wire(camera, to: pipeline, tap: previewTap)
    }

    // Built outside the main actor: frames arrive on the camera queue.
    nonisolated private static func wire(_ camera: CameraService, to pipeline: FramePipeline, tap: PreviewTap) {
        camera.onBuffer = { buffer in
            pipeline.handle(buffer)
            tap.push(buffer)
        }
    }

    func attach(_ context: ModelContext) {
        self.context = context
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
