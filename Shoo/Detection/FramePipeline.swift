import CoreImage
import QuartzCore

/// Throttles camera frames into the detector (~4 fps), measures brightness,
/// grabs a JPEG when something interesting is in frame, and reports on main.
final class FramePipeline {
    var onResult: ((DetectionFrame) -> Void)?

    var interval: CFTimeInterval {
        get { lock.withLock { _interval } }
        set { lock.withLock { _interval = newValue } }
    }
    var snapshotThreshold: Float {
        get { lock.withLock { _snapshotThreshold } }
        set { lock.withLock { _snapshotThreshold = newValue } }
    }

    private let detector: PestDetector
    private let queue = DispatchQueue(label: "shoo.vision", qos: .userInitiated)
    private let ci = CIContext()
    private let lock = NSLock()
    private var _interval: CFTimeInterval = 0.25
    private var _snapshotThreshold: Float = 0.36
    private var busy = false
    private var lastRun: CFTimeInterval = 0
    private var lastThumb: CFTimeInterval = 0   // vision queue only

    init(detector: PestDetector) {
        self.detector = detector
    }

    /// Called on the camera queue.
    func handle(_ buffer: CVPixelBuffer) {
        let now = CACurrentMediaTime()
        let go = lock.withLock {
            guard !busy, now - lastRun >= _interval else { return false }
            busy = true
            lastRun = now
            return true
        }
        guard go else { return }

        queue.async { [self] in
            var frame = (try? detector.detect(buffer)) ?? DetectionFrame()
            frame.luma = Self.luma(buffer)
            if frame.confidence >= snapshotThreshold {
                frame.snapshot = jpeg(buffer)
            }
            let active = frame.moving || frame.confidence >= snapshotThreshold * 0.5 || frame.guardedConfidence >= 0.4
            if now - lastThumb >= (active ? 1 : 10) {
                frame.thumbnail = jpeg(buffer, scale: 0.45, quality: 0.5)
                lastThumb = now
            }
            lock.withLock { busy = false }
            DispatchQueue.main.async { self.onResult?(frame) }
        }
    }

    private func jpeg(_ buffer: CVPixelBuffer, scale: CGFloat = 0.5, quality: CGFloat = 0.6) -> Data? {
        let image = CIImage(cvPixelBuffer: buffer).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return ci.jpegRepresentation(
            of: image,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality]
        )
    }

    /// Mean of a sparse sample of the Y plane, 0…1.
    private static func luma(_ buffer: CVPixelBuffer) -> Float {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard CVPixelBufferGetPlaneCount(buffer) > 0,
              let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)
        else { return 0.5 }

        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        var sum = 0, count = 0
        for y in stride(from: 0, to: height, by: 16) {
            for x in stride(from: 0, to: width, by: 16) {
                sum += Int(pixels[y * rowBytes + x])
                count += 1
            }
        }
        return count > 0 ? Float(sum) / Float(count) / 255 : 0.5
    }
}
