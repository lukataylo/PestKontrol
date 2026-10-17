import AVFoundation

/// Rolling on-device recording: 5-minute HEVC segments named by start time,
/// pruned past the retention window. ~0.5 GB per hour at 720p.
final class VideoRecorder {
    static let directory: URL = {
        let dir = URL.applicationSupportDirectory.appending(path: "Video", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private let segmentLength: Double = 300
    private let lock = NSLock()
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var segmentStart = CMTime.invalid
    private var _enabled = true
    private var _keepHours = 12

    var enabled: Bool {
        get { lock.withLock { _enabled } }
        set { lock.withLock { _enabled = newValue } }
    }
    var keepHours: Int {
        get { lock.withLock { _keepHours } }
        set { lock.withLock { _keepHours = newValue } }
    }

    /// Called on the camera queue for every frame.
    func append(_ buffer: CVPixelBuffer, at time: CMTime) {
        var finished: AVAssetWriter?
        lock.withLock {
            guard _enabled else {
                finished = takeWriter()
                return
            }
            if writer != nil, CMTimeGetSeconds(CMTimeSubtract(time, segmentStart)) >= segmentLength {
                finished = takeWriter()
            }
            if writer == nil {
                start(at: time, width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
            }
            if let input, let adaptor, input.isReadyForMoreMediaData {
                adaptor.append(buffer, withPresentationTime: time)
            }
        }
        if let finished {
            finished.finishWriting {}
            prune()
        }
    }

    /// Closes the segment being written so it can be played back.
    func flush() async {
        guard let w = lock.withLock({ takeWriter() }) else { return }
        await withCheckedContinuation { done in
            w.finishWriting { done.resume() }
        }
    }

    /// The segment file holding `date`, and how far into it `date` is.
    func locate(_ date: Date) async -> (URL, Double)? {
        if let current = lock.withLock({ writer?.outputURL }), let start = Self.start(of: current),
           date >= start.addingTimeInterval(-1) {
            await flush()
        }
        let segments = Self.segments()
        guard let seg = segments.last(where: { $0.start <= date.addingTimeInterval(1) }) else { return nil }
        let offset = max(0, date.timeIntervalSince(seg.start))
        guard offset < segmentLength + 30 else { return nil }
        return (seg.url, offset)
    }

    static func segments() -> [(start: Date, url: URL)] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { url in start(of: url).map { ($0, url) } }.sorted { $0.start < $1.start }
    }

    static func bytesUsed() -> Int64 {
        segments().reduce(0) { sum, seg in
            sum + Int64((try? seg.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    // MARK: - Private (call with lock held)

    private func start(at time: CMTime, width: Int, height: Int) {
        let url = Self.directory.appending(path: "seg_\(Int(Date().timeIntervalSince1970)).mov")
        guard let w = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return }
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 1_200_000,
                AVVideoExpectedSourceFrameRateKey: 15,
                AVVideoMaxKeyFrameIntervalKey: 30,
            ],
        ]
        let i = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        i.expectsMediaDataInRealTime = true
        guard w.canAdd(i) else { return }
        w.add(i)
        guard w.startWriting() else { return }
        w.startSession(atSourceTime: time)
        writer = w
        input = i
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: i, sourcePixelBufferAttributes: nil)
        segmentStart = time
    }

    private func takeWriter() -> AVAssetWriter? {
        let w = writer
        input?.markAsFinished()
        writer = nil
        input = nil
        adaptor = nil
        return w
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-Double(keepHours) * 3600 - segmentLength)
        for seg in Self.segments() where seg.start < cutoff {
            try? FileManager.default.removeItem(at: seg.url)
        }
    }

    private static func start(of url: URL) -> Date? {
        let name = url.deletingPathExtension().lastPathComponent
        guard name.hasPrefix("seg_"), let t = TimeInterval(name.dropFirst(4)) else { return nil }
        return Date(timeIntervalSince1970: t)
    }
}
