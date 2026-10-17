import AVFoundation

/// Synthesises every deterrent on the fly, randomised each time so animals
/// don't learn a fixed pattern. Nothing is downloaded or streamed.
final class SoundEngine {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: Synth.rate, channels: 1)!
    private var attached = false

    func prepare() {
        if attached {
            if !engine.isRunning { try? engine.start() }
            return
        }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        try? engine.start()
        attached = true
    }

    /// Returns the voice actually played (resolves `.mix`).
    @discardableResult
    func play(_ pattern: SoundPattern, gain: Float) -> SoundPattern {
        prepare()
        let voice = pattern == .mix ? SoundPattern.voices.randomElement()! : pattern
        let samples = Synth.render(voice)
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))
        else { return voice }
        buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        player.stop()
        player.volume = gain
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()
        return voice
    }
}

enum Synth {
    static let rate: Double = 48_000

    static func render(_ pattern: SoundPattern) -> [Float] {
        var s: [Float]
        switch pattern {
        case .hawk: s = hawk()
        case .clap: s = clap()
        case .sweep: s = sweep()
        case .pulse: s = pulse()
        case .mix: s = render(SoundPattern.voices.randomElement()!)
        }
        normalize(&s)
        return s
    }

    /// Descending raptor screech with vibrato. Birds hear 1–4 kHz best.
    private static func hawk() -> [Float] {
        var out: [Float] = []
        for _ in 0..<Int.random(in: 2...4) {
            let dur = Double.random(in: 0.45...0.8), n = Int(dur * rate)
            let f0 = Double.random(in: 2600...3400)
            let drop = Double.random(in: 700...1300)
            let vib = Double.random(in: 22...34)
            var phase = 0.0
            for i in 0..<n {
                let t = Double(i) / rate
                let f = f0 - drop * (t / dur) + 140 * sin(2 * .pi * vib * t)
                phase += 2 * .pi * f / rate
                let env = min(1, t / 0.02) * pow(1 - t / dur, 1.5)
                let v = sin(phase) + 0.35 * sin(2 * phase) + 0.15 * sin(3 * phase) + 0.12 * Double.random(in: -1...1)
                out.append(Float(v * env))
            }
            out += silence(.random(in: 0.12...0.35))
        }
        return out
    }

    /// Sharp broadband transients at irregular intervals — startles foxes.
    private static func clap() -> [Float] {
        var out: [Float] = []
        for _ in 0..<Int.random(in: 8...16) {
            let n = Int(0.05 * rate), tau = Double.random(in: 0.006...0.012)
            for i in 0..<n {
                out.append(Float(Double.random(in: -1...1) * exp(-Double(i) / rate / tau)))
            }
            out += silence(.random(in: 0.05...0.3))
        }
        return out
    }

    /// Fast chirps at the top of the speaker's range (15–19.8 kHz).
    private static func sweep() -> [Float] {
        var out: [Float] = []
        for _ in 0..<Int.random(in: 12...24) {
            let dur = Double.random(in: 0.04...0.12), n = Int(dur * rate)
            let lo = Double.random(in: 15_000...16_500), hi = Double.random(in: 18_500...19_800)
            let up = Bool.random()
            var phase = 0.0
            for i in 0..<n {
                let x = Double(i) / Double(n)
                let f = up ? lo + (hi - lo) * x : hi - (hi - lo) * x
                phase += 2 * .pi * f / rate
                out.append(Float(sin(phase) * sin(.pi * x)))
            }
            out += silence(.random(in: 0.02...0.12))
        }
        return out
    }

    /// Alternating high beeps.
    private static func pulse() -> [Float] {
        var out: [Float] = []
        for k in 0..<Int.random(in: 10...18) {
            let f = (k.isMultiple(of: 2) ? 17_500.0 : 19_000.0) + .random(in: -300...300)
            let n = Int(Double.random(in: 0.06...0.1) * rate)
            let ramp = 0.003 * rate
            for i in 0..<n {
                let env = min(1, Double(i) / ramp, Double(n - i) / ramp)
                out.append(Float(sin(2 * .pi * f * Double(i) / rate) * env))
            }
            out += silence(.random(in: 0.04...0.09))
        }
        return out
    }

    private static func silence(_ seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * rate))
    }

    private static func normalize(_ s: inout [Float]) {
        let peak = s.map(abs).max() ?? 0
        guard peak > 0 else { return }
        let k = 0.95 / peak
        for i in s.indices { s[i] *= k }
    }
}
