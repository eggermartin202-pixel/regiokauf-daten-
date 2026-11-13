import AVFoundation
import CoreImage
import CoreMotion
import Photos
import SwiftUI
import UIKit

/// Zentrale App-Logik: verbindet Kamera, Film-Engine, Szenenanalyse und Ablage.
final class CameraModel: ObservableObject {
    let service = CameraService()
    let pipeline = FramePipeline()

    @Published var look = FilmLook.all[1] { didSet { syncPipeline() } }
    @Published var strength: Float = 1 { didSet { syncPipeline() } }
    @Published var aspect = AspectChoice.r3x4 { didSet { syncPipeline() } }
    @Published var showGrid = false
    @Published var showLevel = true
    @Published var portraitMode = false
    @Published var flash: AVCaptureDevice.FlashMode = .off
    @Published var timerSeconds = 0
    @Published var exposureBias: Float = 0 { didSet { service.setExposureBias(exposureBias) } }

    @Published var guideActive = false { didSet { guideChanged() } }
    @Published var guide: CompositionGuide?
    @Published var guideMessage: String?
    @Published var recommendation: (id: String, reason: String)?

    @Published var countdown = 0
    @Published var shutterFlash = false
    @Published var developing = 0
    @Published var shots: [URL] = []
    @Published var rollDegrees: Double = 0
    @Published var saveError: String?

    private let analyzer = SceneAnalyzer()
    private let analysisQueue = DispatchQueue(label: "korn.analysis", qos: .userInitiated)
    private let developQueue = DispatchQueue(label: "korn.develop", qos: .userInitiated)
    private let photoContext = CIContext(options: [.cacheIntermediates: false])
    private let motion = CMMotionManager()
    private var lockedTarget: (CGPoint, String)?
    private var wantsClassification = false
    private var wasAligned = false

    private var shotsFolder: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    init() {
        service.onFrame = { [pipeline] buffer in pipeline.process(buffer) }
        pipeline.onAnalysisFrame = { [weak self] buffer, aspect in self?.analyse(buffer, aspect: aspect) }
        syncPipeline()
        reloadShots()
    }

    // MARK: Lebenszyklus

    func start() {
        service.start()
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 20
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let g = data?.gravity else { return }
            // 0° = Gerät steht exakt senkrecht im Hochformat.
            let degrees = atan2(g.x, -g.y) * 180 / .pi
            if abs(degrees - (self?.rollDegrees ?? 0)) > 0.2 { self?.rollDegrees = degrees }
        }
    }

    func stop() {
        service.stop()
        motion.stopDeviceMotionUpdates()
    }

    private func syncPipeline() {
        let look = look, strength = strength, aspect = aspect, interval = guideActive ? 8 : 0
        pipeline.update {
            $0.look = look
            $0.strength = strength
            $0.aspect = aspect
            $0.analysisInterval = interval
        }
    }

    // MARK: AI

    private func guideChanged() {
        lockedTarget = nil
        guide = nil
        guideMessage = guideActive ? "Szene wird analysiert …" : nil
        wasAligned = false
        if guideActive { wantsClassification = true }
        syncPipeline()
    }

    /// Einmalige Look-Empfehlung für die aktuelle Szene.
    func recommendLook() {
        wantsClassification = true
        pipeline.requestAnalysis()
    }

    func applyRecommendation() {
        guard let r = recommendation else { return }
        look = FilmLook.named(r.id)
        recommendation = nil
    }

    private func analyse(_ buffer: CVPixelBuffer, aspect: AspectChoice) {
        analysisQueue.async { [weak self] in
            guard let self else { return }
            let classify = self.wantsClassification
            let report = self.analyzer.analyze(buffer, aspect: aspect, classify: classify)
            self.pipeline.analysisFinished()
            DispatchQueue.main.async { self.consume(report, classified: classify) }
        }
    }

    private func consume(_ report: SceneReport, classified: Bool) {
        if classified {
            wantsClassification = false
            let r = Composer.recommend(report)
            recommendation = r.id == look.id ? nil : r
        }
        guard guideActive else { return }
        if lockedTarget == nil { lockedTarget = Composer.target(for: report) }
        guard let subject = report.subject, let (target, rule) = lockedTarget else {
            guide = nil
            guideMessage = "Kein klares Motiv erkannt – näher ran oder Motiv antippen"
            return
        }
        let g = Composer.guide(subject: subject, target: target, rule: rule,
                               horizon: report.horizonDegrees, mirrored: service.position == .front)
        if g.aligned, !wasAligned { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        wasAligned = g.aligned
        guideMessage = nil
        withAnimation(.easeOut(duration: 0.25)) { guide = g }
    }

    // MARK: Aufnahme

    func shutterPressed() {
        guard countdown == 0 else { return }
        if timerSeconds > 0 {
            countdown = timerSeconds
            tick()
        } else {
            shoot()
        }
    }

    private func tick() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.countdown > 0 else { return }
            self.countdown -= 1
            if self.countdown == 0 { self.shoot() } else { self.tick() }
        }
    }

    private func shoot() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        shutterFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { self.shutterFlash = false }
        developing += 1
        let look = look, strength = strength, aspect = aspect, portrait = portraitMode
        service.capture(flash: flash) { [weak self] data, metadata in
            guard let self else { return }
            guard let data, let image = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
                DispatchQueue.main.async {
                    self.developing -= 1
                    self.saveError = "Aufnahme fehlgeschlagen."
                }
                return
            }
            self.develop(image, metadata: metadata, look: look, strength: strength,
                         aspect: aspect, portrait: portrait)
        }
    }

    /// Entwickelt ein importiertes Foto mit dem aktuellen Look.
    func developImported(_ data: Data) {
        guard let image = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
            saveError = "Das Bild konnte nicht gelesen werden."
            return
        }
        developing += 1
        develop(image, metadata: [:], look: look, strength: strength, aspect: nil, portrait: portraitMode)
    }

    private func develop(_ source: CIImage, metadata: [String: Any], look: FilmLook, strength: Float,
                         aspect: AspectChoice?, portrait: Bool) {
        developQueue.async {
            var image = aspect?.crop(source) ?? source.transformed(by: CGAffineTransform(
                translationX: -source.extent.minX, y: -source.extent.minY))
            if portrait { image = PortraitEffect.apply(image, context: self.photoContext) }
            image = FilmRenderer.render(image, look: look, strength: strength,
                                        frame: Int.random(in: 0..<10_000), stamp: Date())

            // Aufnahmedaten behalten; die Drehung ist bereits ins Bild eingerechnet.
            var props = metadata
            props[kCGImagePropertyOrientation as String] = 1
            if var tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
                tiff[kCGImagePropertyTIFFOrientation as String] = 1
                props[kCGImagePropertyTIFFDictionary as String] = tiff
            }
            image = image.settingProperties(props)

            let space = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
            let url = self.shotsFolder.appendingPathComponent(
                "korn-\(Int(Date().timeIntervalSince1970 * 1000)).heic")
            var failure: String?
            do {
                guard let heic = self.photoContext.heifRepresentation(of: image, format: .RGBA8,
                                                                      colorSpace: space, options: [:]) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                try heic.write(to: url, options: .atomic)
                self.saveToLibrary(url)
            } catch {
                failure = "Das Foto konnte nicht gespeichert werden."
            }
            DispatchQueue.main.async {
                self.developing -= 1
                self.saveError = failure
                self.reloadShots()
            }
        }
    }

    private func saveToLibrary(_ url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges({
                PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: url, options: nil)
            }, completionHandler: { ok, _ in
                if !ok {
                    DispatchQueue.main.async {
                        self.saveError = "In der App gespeichert, aber nicht in der Mediathek."
                    }
                }
            })
        }
    }

    // MARK: Ablage

    func reloadShots() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: shotsFolder, includingPropertiesForKeys: nil)) ?? []
        shots = files.filter { $0.pathExtension == "heic" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        reloadShots()
    }
}

enum Thumbnail {
    static func load(_ url: URL, maxPixel: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}
