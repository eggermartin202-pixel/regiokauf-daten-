import PhotosUI
import SwiftUI

struct CameraScreen: View {
    @StateObject private var model: CameraModel
    @ObservedObject private var service: CameraService
    @Environment(\.scenePhase) private var scenePhase
    @State private var showGallery = false
    @State private var showExposure = false
    @State private var importItem: PhotosPickerItem?
    @State private var pinchStart: CGFloat?

    init() {
        let m = CameraModel()
        _model = StateObject(wrappedValue: m)
        _service = ObservedObject(wrappedValue: m.service)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 10) {
                topBar
                preview
                if let r = model.recommendation { recommendationChip(r) }
                zoomBar
                if showExposure { exposureRow }
                LookPicker(model: model)
                bottomBar
            }
            .padding(.vertical, 8)
            if service.permissionDenied { permissionNotice }
        }
        .onAppear { model.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.start() } else if phase == .background { model.stop() }
        }
        .onChange(of: importItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    model.developImported(data)
                }
                importItem = nil
            }
        }
        .sheet(isPresented: $showGallery) { GalleryView(model: model) }
        .alert("Hinweis", isPresented: Binding(get: { model.saveError != nil },
                                               set: { if !$0 { model.saveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.saveError ?? "")
        }
    }

    // MARK: Leisten

    private var topBar: some View {
        HStack(spacing: 0) {
            if service.hasFlash {
                barButton(flashIcon, active: model.flash != .off, label: "Blitz") {
                    model.flash = model.flash == .off ? .auto : (model.flash == .auto ? .on : .off)
                }
            }
            barButton("grid", active: model.showGrid, label: "Raster") { model.showGrid.toggle() }
            barButton("level", active: model.showLevel, label: "Wasserwaage") { model.showLevel.toggle() }
            barButton("plusminus", active: showExposure || model.exposureBias != 0, label: "Belichtung") {
                withAnimation { showExposure.toggle() }
            }
            barButton("person.crop.square", active: model.portraitMode, label: "Porträt") {
                model.portraitMode.toggle()
            }
            Button {
                model.timerSeconds = model.timerSeconds == 0 ? 3 : (model.timerSeconds == 3 ? 10 : 0)
            } label: {
                Label(model.timerSeconds == 0 ? "Aus" : "\(model.timerSeconds)s", systemImage: "timer")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(model.timerSeconds == 0 ? Color.white : Color.orange)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityLabel("Selbstauslöser")
            Menu {
                Picker("Format", selection: $model.aspect) {
                    ForEach(AspectChoice.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: {
                Text(model.aspect.rawValue)
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityLabel("Seitenverhältnis")
        }
        .padding(.horizontal, 8)
    }

    private var flashIcon: String {
        switch model.flash {
        case .on: return "bolt.fill"
        case .auto: return "bolt.badge.automatic"
        default: return "bolt.slash"
        }
    }

    private func barButton(_ icon: String, active: Bool, label: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(active ? Color.orange : Color.white)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .accessibilityLabel(label)
    }

    // MARK: Vorschau

    private var preview: some View {
        GeometryReader { geo in
            let size = fitted(in: geo.size)
            ZStack {
                PreviewRepresentable(pipeline: model.pipeline)
                if model.showGrid { GridOverlay() }
                if model.showLevel { LevelOverlay(degrees: model.rollDegrees) }
                if model.guideActive { GuideOverlay(guide: model.guide, message: model.guideMessage) }
                if model.countdown > 0 {
                    Text("\(model.countdown)")
                        .font(.system(size: 96, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(radius: 8)
                }
                if model.shutterFlash { Color.black }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { tap in
                model.service.focus(at: CGPoint(x: tap.location.x / size.width,
                                                y: tap.location.y / size.height))
            })
            .gesture(MagnificationGesture()
                .onChanged { value in
                    let start = pinchStart ?? service.zoomFactor
                    pinchStart = start
                    model.service.setZoom(max(1, start * value))
                }
                .onEnded { _ in pinchStart = nil })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func fitted(in available: CGSize) -> CGSize {
        let ratio = model.aspect.ratio
        var w = available.width, h = available.width / ratio
        if h > available.height {
            h = available.height
            w = h * ratio
        }
        return CGSize(width: max(1, w), height: max(1, h))
    }

    private func recommendationChip(_ r: (id: String, reason: String)) -> some View {
        Button { model.applyRecommendation() } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text("\(FilmLook.named(r.id).name) · \(r.reason)").lineLimit(1)
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.orange, in: Capsule())
        }
        .padding(.horizontal, 12)
    }

    private var zoomBar: some View {
        HStack(spacing: 10) {
            ForEach(service.zoomStops) { stop in
                let active = abs(service.zoomFactor - stop.factor) < 0.05
                Button { model.service.setZoom(stop.factor) } label: {
                    Text(active ? stop.label + "×" : stop.label)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(active ? Color.orange : Color.white)
                        .frame(minWidth: 36, minHeight: 36)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
            }
        }
    }

    private var exposureRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "sun.min")
            Slider(value: $model.exposureBias, in: -2...2, step: 0.1).tint(.orange)
            Text(String(format: "%+.1f", model.exposureBias))
                .font(.caption.monospacedDigit())
                .frame(width: 40)
            Button("0") { model.exposureBias = 0 }.font(.caption.weight(.bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
    }

    private var bottomBar: some View {
        HStack {
            Button { showGallery = true } label: { LastShotThumb(url: model.shots.first) }
                .accessibilityLabel("Galerie")
            Spacer()
            PhotosPicker(selection: $importItem, matching: .images) {
                Image(systemName: "photo.badge.plus").font(.title3).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Foto importieren und entwickeln")
            Spacer()
            Button { model.shutterPressed() } label: {
                ZStack {
                    Circle().stroke(Color.white, lineWidth: 4).frame(width: 76, height: 76)
                    Circle().fill(model.countdown > 0 ? Color.orange : Color.white)
                        .frame(width: 62, height: 62)
                    if model.developing > 0 { ProgressView().tint(.black) }
                }
            }
            .accessibilityLabel("Auslösen")
            Spacer()
            Button {
                model.guideActive.toggle()
            } label: {
                Image(systemName: "viewfinder")
                    .font(.title3)
                    .foregroundStyle(model.guideActive ? Color.orange : Color.white)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("AI-Kompositionshilfe")
            Spacer()
            Button { model.service.flip() } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.title3).foregroundStyle(.white)
                    .frame(width: 52, height: 52)
            }
            .accessibilityLabel("Kamera wechseln")
        }
        .padding(.horizontal, 18)
    }

    private var permissionNotice: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.fill").font(.largeTitle)
            Text("Kein Kamerazugriff").font(.headline)
            Text("Erlaube den Zugriff in den Einstellungen, um zu fotografieren.")
                .font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Einstellungen öffnen") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent).tint(.orange)
        }
        .padding(28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(32)
    }
}

struct LastShotThumb: View {
    let url: URL?
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.12))
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo.on.rectangle").foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: url) {
            guard let url else { image = nil; return }
            image = await Task.detached { Thumbnail.load(url, maxPixel: 200) }.value
        }
    }
}
