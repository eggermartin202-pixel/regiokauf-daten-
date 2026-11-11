import Foundation

enum ExerciseKind: Equatable {
    case intro          // Neues Wort vorstellen
    case chooseMeaning  // PL → DE, Auswahl
    case choosePolish   // DE → PL, Auswahl
    case listenChoose   // Hören → DE, Auswahl
    case build          // DE → PL, Wortbausteine
    case typePolish     // DE → PL, tippen
    case dictation      // Hören → PL, tippen
    case clozeChoose    // Grammatik-Lücke, Auswahl
    case clozeType      // Grammatik-Lücke, tippen

    var isChoice: Bool {
        switch self {
        case .chooseMeaning, .choosePolish, .listenChoose, .clozeChoose: return true
        default: return false
        }
    }

    var isTyping: Bool {
        switch self {
        case .typePolish, .dictation, .clozeType: return true
        default: return false
        }
    }

    /// Zusätzliche Schwierigkeit des Formats (für die Fähigkeits-Schätzung).
    var formatDifficulty: Double {
        switch self {
        case .intro: return 0
        case .chooseMeaning: return -0.6
        case .listenChoose: return -0.3
        case .choosePolish: return -0.4
        case .build: return -0.1
        case .typePolish: return 0.4
        case .dictation: return 0.5
        case .clozeChoose: return -0.3
        case .clozeType: return 0.3
        }
    }
}

struct Exercise: Identifiable {
    let id = UUID()
    let item: LearningItem
    let kind: ExerciseKind
    let instruction: String
    let prompt: String
    let promptIsPolish: Bool
    var options: [String] = []
    var accepted: [String] = []
    var solution: String = ""
    var audio: String? = nil
    var note: String? = nil
    var targetIsPolish: Bool = true
    var translation: String? = nil
}

struct Feedback {
    let verdict: Verdict
    let userAnswer: String
    let solution: String
    let note: String?
}

enum SessionMode: Equatable {
    case standard
    case review
    case focus(Set<String>)

    var title: String {
        switch self {
        case .standard: return "Lektion"
        case .review: return "Wiederholung"
        case .focus: return "Schwächen-Training"
        }
    }
}

// MARK: - Sitzungs-Planung

enum SessionPlanner {

    struct Entry {
        let item: LearningItem
        var isIntro: Bool
        var retries: Int = 0
    }

    static func plan(state: UserState, mode: SessionMode) -> [Entry] {
        let now = Date()
        let progress = state.progress
        let all = Content.allItems

        let due = all
            .compactMap { item -> (LearningItem, ItemProgress)? in
                guard let p = progress[item.id], p.due <= now else { return nil }
                return (item, p)
            }
            .sorted { a, b in
                // Häufig vergessene Elemente zuerst, danach die am längsten fälligen.
                if a.1.lapses != b.1.lapses { return a.1.lapses > b.1.lapses }
                return a.1.due < b.1.due
            }
            .map { $0.0 }

        let practice = all
            .filter { progress[$0.id] != nil }
            .sorted { (progress[$0.id]?.mastery ?? 0) < (progress[$1.id]?.mastery ?? 0) }

        switch mode {
        case .review:
            var items = Array(due.prefix(20))
            if items.count < 10 {
                items += practice.filter { p in !items.contains(where: { $0.id == p.id }) }.prefix(10 - items.count)
            }
            return items.shuffled().map { Entry(item: $0, isIntro: false) }

        case .focus(let tags):
            let inTags = all.filter { tags.contains($0.tag) }
            let seen = inTags.filter { progress[$0.id] != nil }
                .sorted { (progress[$0.id]?.mastery ?? 0) < (progress[$1.id]?.mastery ?? 0) }
            let unseen = inTags.filter { progress[$0.id] == nil }
                .sorted { abs($0.difficulty - state.rating) < abs($1.difficulty - state.rating) }
            var entries = seen.prefix(9).map { Entry(item: $0, isIntro: false) }
            entries += unseen.prefix(3).map { Entry(item: $0, isIntro: true) }
            return entries.shuffled()

        case .standard:
            let accuracy = state.recentAccuracy
            var newCount = accuracy > 0.85 ? 5 : (accuracy > 0.7 ? 4 : 2)
            if due.count < 4 { newCount += 2 }
            let reviewCount = max(4, 12 - newCount)

            let reviews = Array(due.prefix(reviewCount))
            let newItems = pickNew(state: state, count: newCount)

            var entries = reviews.map { Entry(item: $0, isIntro: false) }
            // Neue Elemente gleichmäßig zwischen die Wiederholungen streuen.
            for (index, item) in newItems.enumerated() {
                let position = min(entries.count, (index + 1) * max(1, entries.count / max(1, newItems.count)))
                entries.insert(Entry(item: item, isIntro: true), at: position)
            }
            if entries.count < 8 {
                let extra = practice.filter { p in !entries.contains(where: { $0.item.id == p.id }) }
                entries += extra.prefix(8 - entries.count).map { Entry(item: $0, isIntro: false) }
            }
            return entries
        }
    }

    /// Neue Elemente knapp oberhalb der aktuellen Fähigkeit (Zone der nächsten Entwicklung).
    static func pickNew(state: UserState, count: Int) -> [LearningItem] {
        let target = state.rating + 0.4
        let unseen = Content.allItems
            .filter { state.progress[$0.id] == nil && $0.difficulty <= state.rating + 1.2 }
            .sorted { abs($0.difficulty - target) < abs($1.difficulty - target) }

        var picked: [LearningItem] = []
        // Mindestens ein Grammatik-Element pro Lektion, falls verfügbar.
        if let grammar = unseen.first(where: { $0.isGrammar }) { picked.append(grammar) }
        for item in unseen where picked.count < count && !picked.contains(item) {
            picked.append(item)
        }
        if picked.count < count {
            // Alles im Zielbereich gelernt → darüber hinaus weitermachen.
            let rest = Content.allItems
                .filter { state.progress[$0.id] == nil && !picked.contains($0) }
                .sorted { $0.difficulty < $1.difficulty }
            picked += rest.prefix(count - picked.count)
        }
        return picked
    }
}

// MARK: - Aufgaben-Generator

enum ExerciseFactory {

    private static let vocabLadder: [ExerciseKind] =
        [.chooseMeaning, .choosePolish, .listenChoose, .build, .typePolish, .dictation]

    /// shift: −1 = leichter, +1 = schwerer (aus der aktuellen Leistung der Sitzung).
    static func make(_ item: LearningItem, progress: ItemProgress?, shift: Int, state: UserState) -> Exercise {
        let streak = progress?.streak ?? 0
        switch item {
        case .vocab(let card):
            let step = min(vocabLadder.count - 1, max(0, streak + shift))
            var kind = vocabLadder[step]
            let wordCount = Alt.primary(card.polish(for: state.gender)).split(separator: " ").count
            if kind == .build && wordCount < 3 { kind = .typePolish }
            // Bei sehr schwacher Phase nie mit Diktat bestrafen
            if kind == .dictation && state.recentAccuracy < 0.7 { kind = .typePolish }
            return vocabExercise(card, kind: kind, state: state)
        case .grammar(let g):
            let kind: ExerciseKind = (streak + shift) >= 2 ? .clozeType : .clozeChoose
            return grammarExercise(g, kind: kind, state: state)
        }
    }

    static func intro(_ item: LearningItem, state: UserState) -> Exercise {
        switch item {
        case .vocab(let card):
            let pl = Alt.primary(card.polish(for: state.gender))
            return Exercise(item: item, kind: .intro, instruction: "Neues Wort", prompt: pl,
                            promptIsPolish: true, solution: Alt.display(card.de), audio: pl,
                            note: card.note)
        case .grammar(let g):
            let filled = g.sentence.replacingOccurrences(of: "___", with: g.answer(for: state.gender))
            return Exercise(item: item, kind: .intro, instruction: "Neue Regel: " + g.tag, prompt: filled,
                            promptIsPolish: true, solution: g.de, audio: filled, note: g.explanation)
        }
    }

    private static func vocabExercise(_ card: VocabCard, kind: ExerciseKind, state: UserState) -> Exercise {
        let item = LearningItem.vocab(card)
        let plFull = card.polish(for: state.gender)
        let pl = Alt.primary(plFull)
        let de = Alt.primary(card.de)
        let nearby = Content.vocab.filter { $0.id != card.id && abs($0.level.rawValue - card.level.rawValue) <= 1 }

        func distractorsDE() -> [String] {
            Array(Set(nearby.map { Alt.primary($0.de) }).subtracting([de]).shuffled().prefix(3))
        }
        func distractorsPL() -> [String] {
            Array(Set(nearby.map { Alt.primary($0.polish(for: state.gender)) }).subtracting([pl]).shuffled().prefix(3))
        }

        switch kind {
        case .chooseMeaning:
            return Exercise(item: item, kind: kind, instruction: "Was bedeutet das?", prompt: pl,
                            promptIsPolish: true, options: (distractorsDE() + [de]).shuffled(),
                            accepted: [de], solution: Alt.display(card.de), audio: pl, note: card.note,
                            targetIsPolish: false)
        case .listenChoose:
            return Exercise(item: item, kind: kind, instruction: "Hör zu – was bedeutet das?", prompt: "",
                            promptIsPolish: true, options: (distractorsDE() + [de]).shuffled(),
                            accepted: [de], solution: pl + " = " + Alt.display(card.de), audio: pl,
                            note: card.note, targetIsPolish: false)
        case .choosePolish:
            return Exercise(item: item, kind: kind, instruction: "Wähle die polnische Übersetzung", prompt: de,
                            promptIsPolish: false, options: (distractorsPL() + [pl]).shuffled(),
                            accepted: [pl], solution: pl, audio: pl, note: card.note)
        case .build:
            let words = pl.split(separator: " ").map(String.init)
            let extra = nearby.flatMap { Alt.primary($0.polish(for: state.gender)).split(separator: " ").map(String.init) }
            let distractors = Array(Set(extra).subtracting(words).shuffled().prefix(3))
            return Exercise(item: item, kind: kind, instruction: "Bilde den Satz auf Polnisch", prompt: de,
                            promptIsPolish: false, options: (words + distractors).shuffled(),
                            accepted: Alt.list(plFull), solution: pl, audio: pl, note: card.note)
        case .dictation:
            return Exercise(item: item, kind: kind, instruction: "Hör zu und schreib auf Polnisch", prompt: "",
                            promptIsPolish: true, accepted: Alt.list(plFull),
                            solution: pl + " = " + Alt.display(card.de), audio: pl, note: card.note)
        default: // .typePolish
            return Exercise(item: item, kind: .typePolish, instruction: "Schreib auf Polnisch", prompt: de,
                            promptIsPolish: false, accepted: Alt.list(plFull), solution: pl, audio: pl,
                            note: card.note)
        }
    }

    private static func grammarExercise(_ g: GrammarItem, kind: ExerciseKind, state: UserState) -> Exercise {
        let answer = g.answer(for: state.gender)
        let filled = g.sentence.replacingOccurrences(of: "___", with: answer)
        return Exercise(item: .grammar(g), kind: kind,
                        instruction: kind == .clozeType ? "Schreib das fehlende Wort" : "Ergänze die Lücke",
                        prompt: g.sentence, promptIsPolish: true,
                        options: kind == .clozeChoose ? g.options(for: state.gender).shuffled() : [],
                        accepted: [answer], solution: filled, audio: filled, note: g.explanation,
                        targetIsPolish: true, translation: g.de)
    }
}

// MARK: - Laufende Sitzung

@MainActor
final class SessionModel: ObservableObject {

    @Published private(set) var exercise: Exercise?
    @Published private(set) var feedback: Feedback?
    @Published private(set) var finished = false
    @Published private(set) var answered = 0
    @Published private(set) var correct = 0
    @Published private(set) var completedSteps = 0
    @Published private(set) var comboStreak = 0
    @Published private(set) var difficultyHint: String?

    let mode: SessionMode
    private let store: AppStore
    private var queue: [SessionPlanner.Entry]
    private var current: SessionPlanner.Entry?
    private var window: [Bool] = []
    private(set) var mistakes: [LearningItem] = []
    private let ratingAtStart: Double

    init(store: AppStore, mode: SessionMode) {
        self.store = store
        self.mode = mode
        self.queue = SessionPlanner.plan(state: store.state, mode: mode)
        self.ratingAtStart = store.state.rating
        advance()
    }

    var progress: Double {
        let remaining = queue.count + (exercise == nil ? 0 : 1)
        let total = completedSteps + remaining
        return total == 0 ? 1 : Double(completedSteps) / Double(total)
    }

    var accuracy: Double { answered == 0 ? 0 : Double(correct) / Double(answered) }
    var ratingDelta: Double { store.state.rating - ratingAtStart }
    var isEmpty: Bool { finished && answered == 0 }

    /// Passt das Aufgabenformat an die Leistung der letzten Antworten an.
    private var shift: Int {
        let last = window.suffix(5)
        guard last.count >= 3 else { return store.state.recentAccuracy < 0.65 ? -1 : 0 }
        let rate = Double(last.filter { $0 }.count) / Double(last.count)
        if rate < 0.6 { return -1 }
        if rate >= 0.9 && last.count >= 4 { return 1 }
        return 0
    }

    func submit(_ answer: String) {
        guard let ex = exercise, feedback == nil, ex.kind != .intro else { return }
        let verdict = AnswerChecker.check(answer, accepted: ex.accepted, targetIsPolish: ex.targetIsPolish)
        store.record(item: ex.item, verdict: verdict, formatDifficulty: ex.kind.formatDifficulty,
                     isChoice: ex.kind.isChoice)
        answered += 1
        let ok = verdict.countsAsCorrect
        window.append(ok)
        if ok {
            correct += 1
            comboStreak += 1
        } else {
            comboStreak = 0
            if !mistakes.contains(ex.item) { mistakes.append(ex.item) }
            if var entry = current, entry.retries < 2 {
                entry.retries += 1
                entry.isIntro = false
                queue.insert(entry, at: min(queue.count, 3))
            }
        }
        if ok, let audio = ex.audio, store.state.autoPlayAudio, ex.kind != .listenChoose, ex.kind != .dictation {
            Speaker.shared.speak(audio, slow: store.state.slowAudio)
        }
        feedback = Feedback(verdict: verdict, userAnswer: answer, solution: ex.solution, note: ex.note)
    }

    func advance() {
        if exercise != nil { completedSteps += 1 }
        let oldShift = shift
        feedback = nil
        guard !queue.isEmpty else {
            exercise = nil
            finished = true
            return
        }
        let entry = queue.removeFirst()
        current = entry
        if entry.isIntro {
            exercise = ExerciseFactory.intro(entry.item, state: store.state)
            // Nach der Vorstellung sofort einmal abfragen.
            queue.insert(SessionPlanner.Entry(item: entry.item, isIntro: false), at: 0)
        } else {
            exercise = ExerciseFactory.make(entry.item, progress: store.state.progress[entry.item.id],
                                            shift: oldShift, state: store.state)
        }
        if oldShift > 0 {
            difficultyHint = "Läuft gut – Aufgaben werden schwerer"
        } else if oldShift < 0 {
            difficultyHint = "Wir gehen einen Schritt zurück"
        } else {
            difficultyHint = nil
        }
        if let ex = exercise, store.state.autoPlayAudio,
           ex.kind == .intro || ex.kind == .listenChoose || ex.kind == .dictation, let audio = ex.audio {
            Speaker.shared.speak(audio, slow: store.state.slowAudio)
        }
    }
}
