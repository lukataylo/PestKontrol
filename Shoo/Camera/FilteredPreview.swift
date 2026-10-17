import SwiftUI
import MetalKit
import CoreImage

/// Holds the newest camera frame for views that draw it themselves.
final class PreviewTap {
    private let lock = NSLock()
    private var buffer: CVPixelBuffer?

    func push(_ b: CVPixelBuffer) { lock.withLock { buffer = b } }
    var latest: CVPixelBuffer? { lock.withLock { buffer } }
}

/// Slasher camera: black-and-white, crushed contrast, bone-tinted highlights, moving grain.
struct FilteredCameraView: UIViewRepresentable {
    let tap: PreviewTap

    func makeUIView(context: Context) -> GradedView {
        GradedView(tap: tap)
    }

    func updateUIView(_ uiView: GradedView, context: Context) {}

    final class GradedView: MTKView, MTKViewDelegate {
        private let tap: PreviewTap
        private let queue: MTLCommandQueue?
        private let ci: CIContext?
        private var tick = 0

        init(tap: PreviewTap) {
            self.tap = tap
            let device = MTLCreateSystemDefaultDevice()
            queue = device?.makeCommandQueue()
            ci = device.map { CIContext(mtlDevice: $0, options: [.cacheIntermediates: false]) }
            super.init(frame: .zero, device: device)
            framebufferOnly = false
            colorPixelFormat = .bgra8Unorm
            preferredFramesPerSecond = 15
            backgroundColor = .black
            isOpaque = true
            delegate = self
        }

        required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let buffer = tap.latest, let ci, let queue,
                  let drawable = currentDrawable, let commands = queue.makeCommandBuffer()
            else { return }
            tick += 1

            let source = CIImage(cvPixelBuffer: buffer)
            var image = Self.grade(source, frame: tick)

            // Aspect-fill into the drawable.
            let target = drawableSize
            let scale = max(target.width / source.extent.width, target.height / source.extent.height)
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            image = image.transformed(by: CGAffineTransform(
                translationX: (target.width - image.extent.width) / 2 - image.extent.minX,
                y: (target.height - image.extent.height) / 2 - image.extent.minY))

            ci.render(image, to: drawable.texture, commandBuffer: commands,
                      bounds: CGRect(origin: .zero, size: target), colorSpace: CGColorSpaceCreateDeviceRGB())
            commands.present(drawable)
            commands.commit()
        }

        static func grade(_ input: CIImage, frame: Int) -> CIImage {
            let extent = input.extent
            let mono = input
                .applyingFilter("CIPhotoEffectNoir")
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputContrastKey: 1.3,
                    kCIInputBrightnessKey: -0.02,
                ])
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 0.96, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: 0.92, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: 0.82, w: 0),
                ])
            // Grain: grey noise shifted every frame, soft-lit over the image.
            let shift = CGFloat((frame * 7919) % 512)
            let grain = CIFilter(name: "CIRandomGenerator")!.outputImage!
                .transformed(by: CGAffineTransform(translationX: shift, y: shift * 0.6))
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 0, y: 0.25, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: 0.25, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0.25, z: 0, w: 0),
                    "inputBiasVector": CIVector(x: 0.38, y: 0.38, z: 0.38, w: 0),
                ])
                .cropped(to: extent)
            return grain
                .applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: mono])
                .cropped(to: extent)
        }
    }
}
