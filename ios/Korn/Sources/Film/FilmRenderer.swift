import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Baut aus einem Kamerabild und einem FilmLook einen Core-Image-Graphen.
/// Derselbe Graph läuft für die Live-Vorschau und für das volle Foto auf der GPU.
enum FilmRenderer {
    private static let noise: CIImage = CIFilter.randomGenerator().outputImage ?? CIImage()

    static func render(_ source: CIImage, look: FilmLook, strength: Float,
                       frame: Int = 0, stamp: Date? = nil) -> CIImage {
        let extent = source.extent
        guard !extent.isInfinite, extent.width > 0 else { return source }
        // Effektgrößen relativ zur Bildgröße, damit Vorschau und Foto gleich aussehen.
        let s = min(extent.width, extent.height) / 1080
        var img = source

        if look.exposure != 0 {
            let f = CIFilter.exposureAdjust()
            f.inputImage = img
            f.ev = look.exposure
            img = f.outputImage ?? img
        }

        let cc = CIFilter.colorControls()
        cc.inputImage = img
        cc.saturation = look.mono ? 0 : look.saturation
        cc.contrast = look.contrast
        cc.brightness = 0
        img = cc.outputImage ?? img

        let tc = CIFilter.toneCurve()
        tc.inputImage = img
        tc.point0 = CGPoint(x: 0, y: CGFloat(look.curve[0]))
        tc.point1 = CGPoint(x: 0.25, y: CGFloat(look.curve[1]))
        tc.point2 = CGPoint(x: 0.5, y: CGFloat(look.curve[2]))
        tc.point3 = CGPoint(x: 0.75, y: CGFloat(look.curve[3]))
        tc.point4 = CGPoint(x: 1, y: CGFloat(look.curve[4]))
        img = tc.outputImage ?? img

        // Weißabgleich, Lichter-/Tiefenstich und Fade in einer Matrix.
        let k = 1 - look.fade
        let r = (1 + 0.12 * look.warmth + 0.04 * look.tint + look.highlightTint.x) * k
        let g = (1 - 0.06 * look.tint + look.highlightTint.y) * k
        let b = (1 - 0.12 * look.warmth + 0.04 * look.tint + look.highlightTint.z) * k
        img = matrix(img,
                     r: CIVector(x: CGFloat(r), y: 0, z: 0, w: 0),
                     g: CIVector(x: 0, y: CGFloat(g), z: 0, w: 0),
                     b: CIVector(x: 0, y: 0, z: CGFloat(b), w: 0),
                     bias: CIVector(x: CGFloat(look.fade + look.shadowTint.x),
                                    y: CGFloat(look.fade + look.shadowTint.y),
                                    z: CGFloat(look.fade + look.shadowTint.z), w: 0))

        if look.halation > 0 {
            // Nur Spitzlichter behalten, weichzeichnen, rot einfärben, aufaddieren.
            let h = CGFloat(look.halation)
            var hl = matrix(img,
                            r: CIVector(x: 4, y: 0, z: 0, w: 0),
                            g: CIVector(x: 0, y: 4, z: 0, w: 0),
                            b: CIVector(x: 0, y: 0, z: 4, w: 0),
                            bias: CIVector(x: -3, y: -3, z: -3, w: 0))
            let clamp = CIFilter.colorClamp()
            clamp.inputImage = hl
            clamp.minComponents = CIVector(x: 0, y: 0, z: 0, w: 0)
            clamp.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)
            hl = clamp.outputImage ?? hl
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = hl.clampedToExtent()
            blur.radius = Float(14 * s)
            hl = (blur.outputImage ?? hl).cropped(to: extent)
            hl = matrix(hl,
                        r: CIVector(x: 0.9 * h, y: 0, z: 0, w: 0),
                        g: CIVector(x: 0.22 * h, y: 0, z: 0, w: 0),
                        b: CIVector(x: 0.08 * h, y: 0, z: 0, w: 0),
                        bias: CIVector(x: 0, y: 0, z: 0, w: 0))
            let add = CIFilter.additionCompositing()
            add.inputImage = hl
            add.backgroundImage = img
            img = (add.outputImage ?? img).cropped(to: extent)
        }

        if look.bloom > 0 {
            let f = CIFilter.bloom()
            f.inputImage = img.clampedToExtent()
            f.radius = Float(10 * s)
            f.intensity = look.bloom
            img = (f.outputImage ?? img).cropped(to: extent)
        }

        if look.vignette > 0 {
            let f = CIFilter.vignette()
            f.inputImage = img
            f.intensity = look.vignette * 1.4
            f.radius = 1.7
            img = (f.outputImage ?? img).cropped(to: extent)
        }

        if look.grain > 0 {
            let a = CGFloat(look.grain) * 0.45
            let scale = max(0.5, CGFloat(look.grainSize) * s)
            // Pro Frame verschieben, damit das Korn in der Vorschau lebt.
            let dx = CGFloat((frame &* 131) % 977), dy = CGFloat((frame &* 71) % 839)
            var n = noise.transformed(by: CGAffineTransform(scaleX: scale, y: scale)
                .translatedBy(x: -dx, y: -dy))
            n = matrix(n,
                       r: CIVector(x: 0, y: a, z: 0, w: 0),
                       g: CIVector(x: 0, y: a, z: 0, w: 0),
                       b: CIVector(x: 0, y: a, z: 0, w: 0),
                       a: CIVector(x: 0, y: 0, z: 0, w: 0),
                       bias: CIVector(x: 0.5 - a / 2, y: 0.5 - a / 2, z: 0.5 - a / 2, w: 1))
            let soft = CIFilter.softLightBlendMode()
            soft.inputImage = n.cropped(to: extent)
            soft.backgroundImage = img
            img = (soft.outputImage ?? img).cropped(to: extent)
        }

        if strength < 0.999 {
            let mix = CIFilter.dissolveTransition()
            mix.inputImage = source
            mix.targetImage = img
            mix.time = max(0, strength)
            img = (mix.outputImage ?? img).cropped(to: extent)
        }

        if look.dateStamp, let stamp, let text = stampImage(stamp, height: 34 * s) {
            let m = 0.045 * min(extent.width, extent.height)
            let placed = text.transformed(by: CGAffineTransform(
                translationX: extent.maxX - text.extent.width - m, y: extent.minY + m))
            img = placed.composited(over: img).cropped(to: extent)
        }
        return img
    }

    private static func matrix(_ image: CIImage, r: CIVector, g: CIVector, b: CIVector,
                               a: CIVector = CIVector(x: 0, y: 0, z: 0, w: 1),
                               bias: CIVector) -> CIImage {
        let f = CIFilter.colorMatrix()
        f.inputImage = image
        f.rVector = r
        f.gVector = g
        f.bVector = b
        f.aVector = a
        f.biasVector = bias
        return f.outputImage ?? image
    }

    /// Orangefarbener Datumsstempel wie bei alten Kompaktkameras.
    private static func stampImage(_ date: Date, height: CGFloat) -> CIImage? {
        let df = DateFormatter()
        df.dateFormat = "''yy MM dd"
        let font = UIFont.monospacedDigitSystemFont(ofSize: max(10, height), weight: .bold)
        let shadow = NSShadow()
        shadow.shadowColor = UIColor(red: 1, green: 0.35, blue: 0, alpha: 0.9)
        shadow.shadowBlurRadius = height * 0.25
        let text = NSAttributedString(string: df.string(from: date), attributes: [
            .font: font,
            .foregroundColor: UIColor(red: 1, green: 0.62, blue: 0.2, alpha: 1),
            .shadow: shadow,
        ])
        let pad = height * 0.4
        let size = CGSize(width: ceil(text.size().width + 2 * pad),
                          height: ceil(text.size().height + 2 * pad))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let ui = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            text.draw(at: CGPoint(x: pad, y: pad))
        }
        return ui.cgImage.map { CIImage(cgImage: $0) }
    }
}

enum AspectChoice: String, CaseIterable, Identifiable {
    case r3x4 = "3:4", r1x1 = "1:1", r2x3 = "2:3", r9x16 = "9:16"
    var id: String { rawValue }
    /// Breite / Höhe im Hochformat.
    var ratio: CGFloat {
        switch self {
        case .r3x4: return 3.0 / 4.0
        case .r1x1: return 1
        case .r2x3: return 2.0 / 3.0
        case .r9x16: return 9.0 / 16.0
        }
    }

    /// Größter zentrierter Ausschnitt mit diesem Seitenverhältnis, auf den Ursprung verschoben.
    func crop(_ image: CIImage) -> CIImage {
        let e = image.extent
        var w = e.width, h = e.height
        if w / h > ratio { w = (h * ratio).rounded(.down) } else { h = (w / ratio).rounded(.down) }
        let rect = CGRect(x: e.midX - w / 2, y: e.midY - h / 2, width: w, height: h).integral
        return image.cropped(to: rect)
            .transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
    }
}
