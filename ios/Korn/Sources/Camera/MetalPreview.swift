import CoreImage
import MetalKit
import SwiftUI

/// Zeichnet ein CIImage direkt per Metal – der Film-Graph wird erst hier auf der GPU ausgeführt.
final class MetalPreviewView: MTKView {
    var image: CIImage?
    private var queue: MTLCommandQueue?
    private var context: CIContext?

    init() {
        let device = MTLCreateSystemDefaultDevice()
        super.init(frame: .zero, device: device)
        if let device {
            queue = device.makeCommandQueue()
            context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        }
        framebufferOnly = false
        isPaused = true
        enableSetNeedsDisplay = false
        backgroundColor = .black
        isOpaque = true
    }

    required init(coder: NSCoder) { fatalError("init(coder:) wird nicht verwendet") }

    override func draw(_ rect: CGRect) {
        guard let image, let context, let queue,
              let drawable = currentDrawable,
              let buffer = queue.makeCommandBuffer() else { return }
        let size = drawableSize
        guard size.width > 0, size.height > 0, image.extent.width > 0 else { return }
        // Bild füllend und zentriert in den Drawable skalieren.
        let scale = max(size.width / image.extent.width, size.height / image.extent.height)
        let scaled = image
            .transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let dx = (scaled.extent.width - size.width) / 2
        let dy = (scaled.extent.height - size.height) / 2
        let destination = CIRenderDestination(width: Int(size.width), height: Int(size.height),
                                              pixelFormat: colorPixelFormat, commandBuffer: buffer,
                                              mtlTextureProvider: { drawable.texture })
        _ = try? context.startTask(toRender: scaled,
                                   from: CGRect(x: dx, y: dy, width: size.width, height: size.height),
                                   to: destination, at: .zero)
        buffer.present(drawable)
        buffer.commit()
    }
}

struct PreviewRepresentable: UIViewRepresentable {
    let pipeline: FramePipeline

    func makeUIView(context: Context) -> MetalPreviewView {
        let view = MetalPreviewView()
        pipeline.view = view
        return view
    }

    func updateUIView(_ uiView: MetalPreviewView, context: Context) {}
}
