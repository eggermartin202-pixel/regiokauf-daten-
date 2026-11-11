import Foundation

struct PlacementQuestion: Identifiable {
    let id: String
    let instruction: String
    let prompt: String
    let options: [String]
    let answer: String
    let difficulty: Double
    let area: String
    let itemID: String
    var audio: String? = nil
}

/// Adaptiver Einstufungstest (Computerized Adaptive Testing).
///
/// Jede Antwort aktualisiert eine Fähigkeits-Schätzung θ (0…5) per
/// Maximum-a-posteriori-Schätzung unter einem 3PL-ähnlichen IRT-Modell
/// (mit Rate-Wahrscheinlichkeit bei Multiple Choice). Die nächste Frage
/// ist immer die mit der Schwierigkeit am nächsten an θ – dort liefert sie
/// die meiste Information.
@MainActor
final class PlacementEngine: ObservableObject {

    struct Answer {
        let question: PlacementQuestion
        let given: String?
        let correct: Bool
    }

    @Published private(set) var current: PlacementQuestion?
    @Published private(set) var answers: [Answer] = []
    @Published private(set) var theta: Double = 1.5

    let totalQuestions = 18
    private var pool: [PlacementQuestion]
    private var usedItems = Set<String>()

    init(gender: Gender) {
        pool = PlacementEngine.buildPool(gender: gender)
        current = nextQuestion()
    }

    var isFinished: Bool { answers.count >= totalQuestions || current == nil }
    var progress: Double { Double(answers.count) / Double(totalQuestions) }
    var level: Level { Level.from(rating: theta) }
    var correctCount: Int { answers.filter(\.correct).count }

    func submit(_ option: String?) {
        guard let q = current else { return }
        let ok = option == q.answer
        answers.append(Answer(question: q, given: option, correct: ok))
        theta = PlacementEngine.estimateTheta(answers)
        current = answers.count >= totalQuestions ? nil : nextQuestion()
    }

    /// Ergebnisse pro Bereich (Wortschatz / Grammatik).
    struct AreaResult: Identifiable {
        let area: String
        let correct: Int
        let total: Int
        var id: String { area }
    }

    var areaResults: [AreaResult] {
        let grouped = Dictionary(grouping: answers, by: { $0.question.area })
        return grouped.keys.sorted().map { key in
            let list = grouped[key] ?? []
            return AreaResult(area: key, correct: list.filter(\.correct).count, total: list.count)
        }
    }

    // MARK: - Auswahl

    private func nextQuestion() -> PlacementQuestion? {
        // Bereiche abwechseln, damit Grammatik und Wortschatz beide gemessen werden.
        let preferGrammar = answers.count % 3 == 2
        let candidates = pool.filter { !usedItems.contains($0.itemID) }
        guard !candidates.isEmpty else { return nil }
        let areaFiltered = candidates.filter { ($0.area == "Grammatik") == preferGrammar }
        let source = areaFiltered.isEmpty ? candidates : areaFiltered
        let scored = source.map { (q: $0, score: abs($0.difficulty - theta) + Double.random(in: 0...0.35)) }
        let chosen = scored.min { $0.score < $1.score }?.q
        if let chosen { usedItems.insert(chosen.itemID) }
        return chosen
    }

    // MARK: - Schätzung

    static func probability(theta: Double, difficulty: Double, guessing: Double) -> Double {
        let logistic = 1.0 / (1.0 + exp(-1.7 * (theta - difficulty)))
        return guessing + (1 - guessing) * logistic
    }

    static func estimateTheta(_ answers: [Answer]) -> Double {
        var best = 1.5
        var bestScore = -Double.infinity
        var t = 0.0
        while t <= 5.0001 {
            // schwacher Prior um A2 herum, verhindert Ausreißer bei wenigen Antworten
            var score = -pow(t - 1.5, 2) / (2 * 1.6 * 1.6)
            for a in answers {
                let guessing = a.given == nil ? 0.0 : 1.0 / Double(a.question.options.count)
                let p = probability(theta: t, difficulty: a.question.difficulty, guessing: guessing)
                score += a.correct ? log(max(p, 1e-6)) : log(max(1 - p, 1e-6))
            }
            if score > bestScore { bestScore = score; best = t }
            t += 0.05
        }
        return best
    }

    // MARK: - Fragen-Pool

    private static func buildPool(gender: Gender) -> [PlacementQuestion] {
        var result: [PlacementQuestion] = []
        let vocab = Content.vocab

        for card in vocab {
            let pl = Alt.primary(card.polish(for: gender))
            let de = Alt.primary(card.de)
            let sameLevel = vocab.filter { $0.id != card.id && abs($0.level.rawValue - card.level.rawValue) <= 1 }
            let useReverse = card.id.hashValue % 2 == 0 && card.level >= .a1

            if useReverse {
                let distractors = Array(Set(sameLevel.map { Alt.primary($0.polish(for: gender)) }).subtracting([pl]).shuffled().prefix(3))
                result.append(PlacementQuestion(
                    id: "p_" + card.id, instruction: "Wie sagt man auf Polnisch?",
                    prompt: de, options: (distractors + [pl]).shuffled(), answer: pl,
                    difficulty: card.difficulty + 0.2, area: "Wortschatz", itemID: card.id))
            } else {
                let distractors = Array(Set(sameLevel.map { Alt.primary($0.de) }).subtracting([de]).shuffled().prefix(3))
                result.append(PlacementQuestion(
                    id: "p_" + card.id, instruction: "Was bedeutet das?",
                    prompt: pl, options: (distractors + [de]).shuffled(), answer: de,
                    difficulty: card.difficulty, area: "Wortschatz", itemID: card.id, audio: pl))
            }
        }

        for item in Content.grammar {
            let answer = item.answer(for: gender)
            result.append(PlacementQuestion(
                id: "p_" + item.id, instruction: "Ergänze die Lücke",
                prompt: item.sentence + "\n(" + item.de + ")",
                options: item.options(for: gender).shuffled(), answer: answer,
                difficulty: item.difficulty, area: "Grammatik", itemID: item.id))
        }
        return result
    }
}
