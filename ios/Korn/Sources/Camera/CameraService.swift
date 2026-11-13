import AVFoundation
import UIKit

struct ZoomStop: Identifiable, Equatable {
    let factor: CGFloat   // videoZoomFactor des Geräts
    let label: String     // Anzeige, z. B. "0,5" / "1" / "2"
    var id: CGFloat { factor }
}

/// Kapselt AVCaptureSession: Live-Frames für die Vorschau und volle Fotos.
final class CameraService: NSObject, ObservableObject,
    AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate {

    @Published var permissionDenied = false
    @Published var position: AVCaptureDevice.Position = .back
    @Published var zoomStops: [ZoomStop] = []
    @Published var zoomFactor: CGFloat = 1
    @Published var hasFlash = false

    /// Wird auf der Video-Queue aufgerufen.
    var onFrame: ((CVPixelBuffer) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "korn.session")
    private let videoQueue = DispatchQueue(label: "korn.video", qos: .userInteractive)
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var input: AVCaptureDeviceInput?
    private var configured = false
    private let lock = NSLock()
    private var handlers: [Int64: (Data?, [String: Any]) -> Void] = [:]

    private var device: AVCaptureDevice? { input?.device }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] ok in
                DispatchQueue.main.async { self?.permissionDenied = !ok }
                if ok { self?.run() }
            }
        default:
            permissionDenied = true
        }
    }

    func stop() {
        sessionQueue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    private func run() {
        sessionQueue.async {
            if !self.configured {
                self.configure()
                self.configured = true
            }
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .quality
        }
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        attachDevice(for: .back)
        session.commitConfiguration()
    }

    /// Muss innerhalb von begin/commitConfiguration auf der Session-Queue laufen.
    private func attachDevice(for position: AVCaptureDevice.Position) {
        let types: [AVCaptureDevice.DeviceType] = position == .back
            ? [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
            : [.builtInWideAngleCamera]
        let found = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video,
                                                     position: position).devices.first
        guard let device = found, let newInput = try? AVCaptureDeviceInput(device: device) else { return }
        if let old = input { session.removeInput(old) }
        guard session.canAddInput(newInput) else {
            if let old = input, session.canAddInput(old) { session.addInput(old) }
            return
        }
        session.addInput(newInput)
        input = newInput

        // Größtes Fotoformat bis ~25 MP (48 MP würde die Entwicklung unnötig bremsen).
        let dims = device.activeFormat.supportedMaxPhotoDimensions
        if let best = dims.filter({ Int($0.width) * Int($0.height) <= 25_000_000 })
            .max(by: { $0.width < $1.width }) ?? dims.first {
            photoOutput.maxPhotoDimensions = best
        }

        for output in [photoOutput, videoOutput] as [AVCaptureOutput] {
            guard let c = output.connection(with: .video) else { continue }
            if c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
            if c.isVideoMirroringSupported {
                c.automaticallyAdjustsVideoMirroring = false
                c.isVideoMirrored = position == .front
            }
        }

        // Zoomstufen aus den Objektivwechseln des virtuellen Geräts ableiten.
        let hasUltraWide = device.constituentDevices.contains { $0.deviceType == .builtInUltraWideCamera }
        let mult: CGFloat = hasUltraWide ? 0.5 : 1
        var factors: [CGFloat] = [1] + device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
        let twoX = 2 / mult
        if !factors.contains(where: { abs($0 - twoX) < 0.05 }), twoX <= device.activeFormat.videoMaxZoomFactor {
            factors.append(twoX)
        }
        factors.sort()
        let stops = factors.map { f -> ZoomStop in
            let shown = f * mult
            let text = shown == shown.rounded() ? String(Int(shown)) : String(format: "%.1f", shown)
            return ZoomStop(factor: f, label: text.replacingOccurrences(of: ".", with: ","))
        }
        let initial: CGFloat = hasUltraWide ? 2 : 1
        applyZoom(initial, on: device)
        let flash = device.hasFlash
        DispatchQueue.main.async {
            self.position = position
            self.zoomStops = stops
            self.zoomFactor = initial
            self.hasFlash = flash
        }
    }

    func flip() {
        sessionQueue.async {
            let next: AVCaptureDevice.Position = self.device?.position == .back ? .front : .back
            self.session.beginConfiguration()
            self.attachDevice(for: next)
            self.session.commitConfiguration()
        }
    }

    private func applyZoom(_ factor: CGFloat, on device: AVCaptureDevice) {
        let maxFactor = min(device.activeFormat.videoMaxZoomFactor, 30)
        let f = max(device.minAvailableVideoZoomFactor, min(factor, maxFactor))
        guard (try? device.lockForConfiguration()) != nil else { return }
        device.videoZoomFactor = f
        device.unlockForConfiguration()
    }

    func setZoom(_ factor: CGFloat) {
        zoomFactor = factor
        sessionQueue.async {
            guard let device = self.device else { return }
            self.applyZoom(factor, on: device)
        }
    }

    /// Belichtungskorrektur in EV.
    func setExposureBias(_ ev: Float) {
        sessionQueue.async {
            guard let d = self.device, (try? d.lockForConfiguration()) != nil else { return }
            d.setExposureTargetBias(max(d.minExposureTargetBias, min(ev, d.maxExposureTargetBias)))
            d.unlockForConfiguration()
        }
    }

    /// Fokus und Belichtung auf einen Punkt der Vorschau (0…1, Ursprung oben links).
    func focus(at p: CGPoint) {
        sessionQueue.async {
            guard let d = self.device, (try? d.lockForConfiguration()) != nil else { return }
            // Sensor-Koordinaten sind querformatig; die Frontkamera ist zusätzlich gespiegelt.
            let poi = d.position == .front ? CGPoint(x: p.y, y: p.x) : CGPoint(x: p.y, y: 1 - p.x)
            if d.isFocusPointOfInterestSupported, d.isFocusModeSupported(.autoFocus) {
                d.focusPointOfInterest = poi
                d.focusMode = .autoFocus
            }
            if d.isExposurePointOfInterestSupported, d.isExposureModeSupported(.continuousAutoExposure) {
                d.exposurePointOfInterest = poi
                d.exposureMode = .continuousAutoExposure
            }
            d.unlockForConfiguration()
        }
    }

    /// Nimmt ein Foto auf. Der Handler kommt auf einer Hintergrund-Queue zurück.
    func capture(flash: AVCaptureDevice.FlashMode, handler: @escaping (Data?, [String: Any]) -> Void) {
        sessionQueue.async {
            guard self.session.isRunning, self.photoOutput.connection(with: .video) != nil else {
                handler(nil, [:])
                return
            }
            let settings: AVCapturePhotoSettings
            if self.photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            } else {
                settings = AVCapturePhotoSettings()
            }
            if self.photoOutput.supportedFlashModes.contains(flash) { settings.flashMode = flash }
            settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
            settings.photoQualityPrioritization = .quality
            self.lock.lock()
            self.handlers[settings.uniqueID] = handler
            self.lock.unlock()
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        lock.lock()
        let handler = handlers.removeValue(forKey: photo.resolvedSettings.uniqueID)
        lock.unlock()
        let data = error == nil ? photo.fileDataRepresentation() : nil
        let meta = photo.metadata
        DispatchQueue.global(qos: .userInitiated).async { handler?(data, meta) }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(buffer)
    }
}
