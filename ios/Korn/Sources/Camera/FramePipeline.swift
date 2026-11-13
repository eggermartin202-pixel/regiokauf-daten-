import CoreImage
import CoreVideo
import Foundation

/// Läuft auf der Video-Queue: wendet den aktuellen Look an und reicht das Bild an die Vorschau.
/// Zusätzlich gibt sie in Abständen Frames an die Szenenanalyse weiter.
final class FramePipeline {
    struct State {
        var look = FilmLook.all[0]
        var strength: Float = 1
        var aspect = AspectChoice.r3x4
        var analysisInterval = 0   // 0 = aus, sonst jedes n-te Frame
    }

    weak var view: MetalPreviewView?
    var onAnalysisFrame: ((CVPixelBuffer, AspectChoice) -> Void)?

    private let lock = NSLock()
    private var state = State()
    private var frame = 0
    private var analysisBusy = false
    private var pendingOneShot = false

    func update(_ change: (inout State) -> Void) {
        lock.lock()
        change(&state)
        lock.unlock()
    }

    /// Fordert genau eine Analyse des nächsten Frames an.
    func requestAnalysis() {
        lock.lock()
        pendingOneShot = true
        lock.unlock()
    }

    func analysisFinished() {
        lock.lock()
        analysisBusy = false
        lock.unlock()
    }

    func process(_ buffer: CVPixelBuffer) {
        lock.lock()
        let s = state
        frame &+= 1
        let n = frame
        var analyse = false
        if !analysisBusy, pendingOneShot || (s.analysisInterval > 0 && n % s.analysisInterval == 0) {
            analysisBusy = true
            pendingOneShot = false
            analyse = true
        }
        lock.unlock()

        if analyse { onAnalysisFrame?(buffer, s.aspect) }

        let cropped = s.aspect.crop(CIImage(cvPixelBuffer: buffer))
        let output = FilmRenderer.render(cropped, look: s.look, strength: s.strength, frame: n)
        DispatchQueue.main.async { [weak self] in
            guard let view = self?.view else { return }
            view.image = output
            view.draw()
        }
    }
}
