import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

/// Ergebnis einer On-Device-Analyse. Punkte sind normalisiert (0…1), Ursprung oben links,
/// bezogen auf den sichtbaren Bildausschnitt.
struct SceneReport {
    var subject: CGPoint?
    var subjectIsFace = false
    var horizonDegrees: Double?
    var labels: [String] = []
    var brightness: Double = 0.5
    var warmth: Double = 0
}

/// Alles läuft lokal über Vision (Neural Engine / GPU) – kein Netzwerk, kein Server.
final class SceneAnalyzer {
    private let context = CIContext(options: [.workingColorSpace: NSNull()])

    func analyze(_ buffer: CVPixelBuffer, aspect: AspectChoice, classify: Bool) -> SceneReport {
        var report = SceneReport()
        let w = CGFloat(CVPixelBufferGetWidth(buffer)), h = CGFloat(CVPixelBufferGetHeight(buffer))
        guard w > 0, h > 0 else { return report }

        // Sichtbarer Ausschnitt als normalisierte Region (zentriert, daher ohne Achsen-Flip).
        var rw: CGFloat = 1, rh: CGFloat = 1
        if w / h > aspect.ratio { rw = h * aspect.ratio / w } else { rh = w / aspect.ratio / h }
        let roi = CGRect(x: (1 - rw) / 2, y: (1 - rh) / 2, width: rw, height: rh)

        let saliency = VNGenerateAttentionBasedSaliencyImageRequest()
        saliency.regionOfInterest = roi
        let faces = VNDetectFaceRectanglesRequest()
        faces.regionOfInterest = roi
        let horizon = VNDetectHorizonRequest()
        let classifier = VNClassifyImageRequest()
        var requests: [VNRequest] = [saliency, faces, horizon]
        if classify { requests.append(classifier) }

        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
        try? handler.perform(requests)

        if let face = faces.results?.max(by: { $0.boundingBox.width < $1.boundingBox.width }) {
            // Augenhöhe liegt grob bei 60 % der Gesichtshöhe.
            let box = face.boundingBox
            report.subject = CGPoint(x: box.midX, y: 1 - (box.minY + 0.6 * box.height))
            report.subjectIsFace = true
        } else if let objects = saliency.results?.first?.salientObjects, !objects.isEmpty {
            let union = objects.map(\.boundingBox).reduce(objects[0].boundingBox) { $0.union($1) }
            // Füllt das Motiv fast das ganze Bild, gibt es nichts sinnvoll zu verschieben.
            if union.width * union.height < 0.7 {
                report.subject = CGPoint(x: union.midX, y: 1 - union.midY)
            }
        }

        if let angle = horizon.results?.first?.angle {
            let degrees = Double(angle) * 180 / .pi
            if abs(degrees) < 20 { report.horizonDegrees = degrees }
        }

        if classify, let results = classifier.results {
            report.labels = results.filter { $0.confidence > 0.2 }.prefix(10).map(\.identifier)
        }

        // Mittlere Helligkeit und Farbstimmung über ein 1×1-Pixel-Rendering.
        let image = CIImage(cvPixelBuffer: buffer)
        let average = CIFilter.areaAverage()
        average.inputImage = image
        average.extent = image.extent
        if let out = average.outputImage {
            var px = [UInt8](repeating: 0, count: 4)
            context.render(out, toBitmap: &px, rowBytes: 4,
                           bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                           format: .RGBA8, colorSpace: nil)
            let r = Double(px[0]) / 255, g = Double(px[1]) / 255, b = Double(px[2]) / 255
            report.brightness = 0.2126 * r + 0.7152 * g + 0.0722 * b
            report.warmth = r - b
        }
        return report
    }
}

/// Kompositionshinweis für das AR-Overlay.
struct CompositionGuide: Equatable {
    var subject: CGPoint
    var target: CGPoint
    var rule: String
    var hint: String
    var aligned: Bool
    var horizonDegrees: Double?
}

enum Composer {
    private static let symmetric = ["architecture", "building", "bridge", "tower", "corridor",
                                    "arch", "church", "temple", "road", "tunnel", "staircase"]

    /// Wählt den Zielpunkt einmalig; danach wird nur noch die Motivposition nachgeführt.
    static func target(for report: SceneReport) -> (CGPoint, String)? {
        guard let s = report.subject else { return nil }
        let t: CGFloat = 1.0 / 3.0
        if report.subjectIsFace {
            let options = [CGPoint(x: t, y: t), CGPoint(x: 0.5, y: t), CGPoint(x: 2 * t, y: t)]
            return (nearest(to: s, in: options), "Augen auf die obere Drittellinie")
        }
        let wantsSymmetry = report.labels.contains { l in symmetric.contains { l.contains($0) } }
        if wantsSymmetry, abs(s.x - 0.5) < 0.15 {
            return (CGPoint(x: 0.5, y: 0.5), "Symmetrie: Motiv mittig")
        }
        let thirds = [CGPoint(x: t, y: t), CGPoint(x: 2 * t, y: t),
                      CGPoint(x: t, y: 2 * t), CGPoint(x: 2 * t, y: 2 * t)]
        return (nearest(to: s, in: thirds), "Drittelregel")
    }

    static func guide(subject s: CGPoint, target: CGPoint, rule: String,
                      horizon: Double?, mirrored: Bool) -> CompositionGuide {
        let dx = target.x - s.x, dy = target.y - s.y
        let aligned = hypot(dx, dy) < 0.045
        var parts: [String] = []
        // Motiv soll im Bild nach rechts → Kamera nach links schwenken (Frontkamera gespiegelt).
        if abs(dx) > 0.04 {
            let panLeft = (dx > 0) != mirrored
            parts.append(panLeft ? "nach links schwenken" : "nach rechts schwenken")
        }
        if abs(dy) > 0.04 { parts.append(dy > 0 ? "nach oben neigen" : "nach unten neigen") }
        var hint = aligned ? "Passt – jetzt auslösen" : "Kamera " + parts.joined(separator: " und ")
        if let horizon, abs(horizon) > 1.5, aligned { hint = "Horizont ausrichten" }
        return CompositionGuide(subject: s, target: target, rule: rule, hint: hint,
                                aligned: aligned && abs(horizon ?? 0) <= 1.5, horizonDegrees: horizon)
    }

    private static func nearest(to p: CGPoint, in options: [CGPoint]) -> CGPoint {
        options.min { hypot($0.x - p.x, $0.y - p.y) < hypot($1.x - p.x, $1.y - p.y) } ?? p
    }

    /// Wählt anhand von Motiv, Licht und Farbstimmung einen passenden Look.
    static func recommend(_ r: SceneReport) -> (id: String, reason: String) {
        func has(_ words: String...) -> Bool { r.labels.contains { l in words.contains { l.contains($0) } } }
        if r.brightness < 0.16 || has("night", "neon", "firework", "concert") {
            return ("tungsten", "Wenig Licht – Kinofilm mit Lichthof")
        }
        if r.subjectIsFace || has("people", "portrait", "person", "baby") {
            return ("samt", "Porträt – weiche Hauttöne")
        }
        if has("food", "dessert", "coffee", "drink", "restaurant", "bakery") {
            return ("bernstein", "Essen – warme, satte Farben")
        }
        if has("sunset", "sunrise") || r.warmth > 0.18 {
            return ("agora", "Warmes Licht – rotbetonter Film")
        }
        if has("beach", "sky", "mountain", "ocean", "lake", "flower", "landscape", "outdoor")
            && r.brightness > 0.4 {
            return ("dia-v", "Landschaft bei gutem Licht – kräftiger Diafilm")
        }
        if has("forest", "plant", "tree", "grass", "garden") {
            return ("smaragd", "Viel Grün – kühle, grüne Tiefen")
        }
        if has("building", "architecture", "street", "city", "bridge", "structure") {
            return r.brightness < 0.3 ? ("silber", "Architektur bei flachem Licht – Schwarzweiß")
                                      : ("dia-p", "Architektur – klare, präzise Farben")
        }
        if has("interior", "room", "furniture", "party") {
            return ("ccd", "Innenraum – Kompaktkamera-Look")
        }
        return r.brightness < 0.3 ? ("silber", "Gedämpftes Licht – Schwarzweiß")
                                  : ("bernstein", "Alltagsszene – warmer Allrounder")
    }
}

/// Porträtmodus: Personen per On-Device-Segmentierung freistellen, Hintergrund weichzeichnen.
enum PortraitEffect {
    static func apply(_ image: CIImage, context: CIContext) -> CIImage {
        guard let cg = context.createCGImage(image, from: image.extent) else { return image }
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
        guard let maskBuffer = request.results?.first?.pixelBuffer else { return image }

        var mask = CIImage(cvPixelBuffer: maskBuffer)
        mask = mask.transformed(by: CGAffineTransform(
            scaleX: image.extent.width / mask.extent.width,
            y: image.extent.height / mask.extent.height))
        mask = mask.transformed(by: CGAffineTransform(translationX: image.extent.minX,
                                                      y: image.extent.minY))

        // Ohne erkannte Person nichts verändern.
        let average = CIFilter.areaAverage()
        average.inputImage = mask
        average.extent = mask.extent
        var px = [UInt8](repeating: 0, count: 4)
        if let out = average.outputImage {
            context.render(out, toBitmap: &px, rowBytes: 4,
                           bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                           format: .RGBA8, colorSpace: nil)
        }
        guard px[0] > 6 else { return image }

        let blur = CIFilter.gaussianBlur()
        blur.inputImage = image.clampedToExtent()
        blur.radius = Float(min(image.extent.width, image.extent.height) / 70)
        let background = (blur.outputImage ?? image).cropped(to: image.extent)

        let blend = CIFilter.blendWithMask()
        blend.inputImage = image
        blend.backgroundImage = background
        blend.maskImage = mask
        return (blend.outputImage ?? image).cropped(to: image.extent)
    }
}
