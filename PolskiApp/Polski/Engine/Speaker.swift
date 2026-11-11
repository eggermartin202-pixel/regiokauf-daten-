import AVFoundation

/// Polnische Sprachausgabe über die iOS-Systemstimme (pl-PL).
final class Speaker {
    static let shared = Speaker()
    private let synthesizer = AVSpeechSynthesizer()

    private lazy var voice: AVSpeechSynthesisVoice? = {
        let polish = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "pl-PL" }
        // Bessere Qualität bevorzugen, falls der Nutzer sie geladen hat.
        return polish.max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: "pl-PL")
    }()

    func speak(_ text: String, slow: Bool = false) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = slow ? 0.32 : 0.47
        synthesizer.speak(utterance)
    }
}
