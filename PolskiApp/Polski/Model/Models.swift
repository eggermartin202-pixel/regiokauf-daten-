import Foundation

// MARK: - Niveau

enum Level: Int, Codable, CaseIterable, Comparable, Identifiable {
    case a0, a1, a2, b1, b2

    var id: Int { rawValue }

    static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }

    var code: String {
        switch self {
        case .a0: return "A0"
        case .a1: return "A1"
        case .a2: return "A2"
        case .b1: return "B1"
        case .b2: return "B2"
        }
    }

    var title: String {
        switch self {
        case .a0: return "Einsteiger"
        case .a1: return "Anfänger"
        case .a2: return "Grundkenntnisse"
        case .b1: return "Mittelstufe"
        case .b2: return "Fortgeschritten"
        }
    }

    var summary: String {
        switch self {
        case .a0: return "Du startest bei null – wir bauen Begrüßungen, Zahlen und erste Wörter auf."
        case .a1: return "Du kennst die Basics. Jetzt kommen Alltag, Fälle und die ersten echten Sätze."
        case .a2: return "Du kommst im Alltag zurecht. Fokus: Vergangenheit, Zukunft, Instrumental und Dativ."
        case .b1: return "Du kannst dich verständigen. Jetzt geht es um Aspekte, Konditional und Nuancen."
        case .b2: return "Starkes Niveau. Wir schleifen an Stil, Passiv, Partizipien und Zahlwörtern."
        }
    }

    /// Wandelt eine kontinuierliche Fähigkeits-Schätzung (0…5) in ein Niveau um.
    static func from(rating: Double) -> Level {
        let index = min(4, max(0, Int(rating.rounded(.down))))
        return Level(rawValue: index) ?? .a0
    }
}

enum Gender: String, Codable, CaseIterable, Identifiable {
    case male, female
    var id: String { rawValue }
    var label: String { self == .male ? "männlich (byłem)" : "weiblich (byłam)" }
}

// MARK: - Inhalte

/// Hilfsfunktionen für Felder mit Alternativen, getrennt durch "|".
enum Alt {
    static func list(_ s: String) -> [String] {
        s.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    static func primary(_ s: String) -> String { list(s).first ?? s }
    static func display(_ s: String) -> String { list(s).joined(separator: " / ") }
}

struct VocabCard: Identifiable, Hashable {
    let id: String
    let pl: String
    let de: String
    let level: Level
    let topic: String
    var plFem: String? = nil
    var note: String? = nil

    func polish(for gender: Gender) -> String {
        if gender == .female, let f = plFem { return f }
        return pl
    }

    var difficulty: Double { Double(level.rawValue) + 0.5 }
}

struct GrammarItem: Identifiable, Hashable {
    let id: String
    /// Satz mit "___" als Lücke.
    let sentence: String
    let answer: String
    let options: [String]
    let de: String
    let level: Level
    let tag: String
    let explanation: String
    var answerFem: String? = nil
    var optionsFem: [String]? = nil

    func answer(for gender: Gender) -> String {
        if gender == .female, let f = answerFem { return f }
        return answer
    }

    func options(for gender: Gender) -> [String] {
        if gender == .female, let f = optionsFem { return f }
        return options
    }

    var difficulty: Double { Double(level.rawValue) + 0.65 }
}

enum LearningItem: Identifiable, Hashable {
    case vocab(VocabCard)
    case grammar(GrammarItem)

    var id: String {
        switch self {
        case .vocab(let v): return v.id
        case .grammar(let g): return g.id
        }
    }

    var difficulty: Double {
        switch self {
        case .vocab(let v): return v.difficulty
        case .grammar(let g): return g.difficulty
        }
    }

    var level: Level {
        switch self {
        case .vocab(let v): return v.level
        case .grammar(let g): return g.level
        }
    }

    var tag: String {
        switch self {
        case .vocab(let v): return v.topic
        case .grammar(let g): return g.tag
        }
    }

    var isGrammar: Bool {
        if case .grammar = self { return true }
        return false
    }
}

// MARK: - Lernfortschritt

struct ItemProgress: Codable {
    var ease: Double = 2.5
    var intervalDays: Double = 0
    var due: Date = .distantPast
    var streak: Int = 0
    var lapses: Int = 0
    var seen: Int = 0
    var correct: Int = 0
    var lastSeen: Date? = nil

    /// 0…1 – wie sicher sitzt das Element?
    var mastery: Double {
        guard seen > 0 else { return 0 }
        let byStreak = min(1.0, Double(streak) / 5.0)
        let byInterval = min(1.0, intervalDays / 21.0)
        return max(byStreak, byInterval)
    }

    /// SM-2-Variante. quality: 0…5 (unter 3 = falsch).
    mutating func record(quality: Int, now: Date = Date()) {
        seen += 1
        lastSeen = now
        let q = Double(max(0, min(5, quality)))
        if quality < 3 {
            streak = 0
            lapses += 1
            intervalDays = 0
            ease = max(1.3, ease - 0.2)
            due = now.addingTimeInterval(10 * 60) // in 10 Minuten wieder
        } else {
            correct += 1
            streak += 1
            switch streak {
            case 1: intervalDays = 1
            case 2: intervalDays = 3
            default: intervalDays = max(intervalDays * ease, intervalDays + 1)
            }
            ease = max(1.3, ease + 0.1 - (5 - q) * (0.08 + (5 - q) * 0.02))
            due = now.addingTimeInterval(intervalDays * 86_400)
        }
    }
}

struct TagStat: Codable {
    var seen: Int = 0
    var correct: Int = 0
    /// Gleitender Durchschnitt – reagiert schneller auf aktuelle Leistung.
    var recent: Double = 0.75

    var accuracy: Double { seen == 0 ? 0 : Double(correct) / Double(seen) }
}

struct PlacementRecord: Codable {
    var date: Date
    var level: Level
    var rating: Double
    var correct: Int
    var total: Int
}

struct UserState: Codable {
    var onboarded: Bool = false
    var name: String = ""
    var gender: Gender = .male
    var placementDone: Bool = false
    var placementHistory: [PlacementRecord] = []
    /// Kontinuierliche Fähigkeits-Schätzung 0…5 (A0 … B2).
    var rating: Double = 0.3
    var progress: [String: ItemProgress] = [:]
    var tagStats: [String: TagStat] = [:]
    /// "yyyy-MM-dd" -> Anzahl beantworteter Aufgaben.
    var days: [String: Int] = [:]
    var recentAccuracy: Double = 0.8
    var dailyGoal: Int = 30
    var slowAudio: Bool = false
    var autoPlayAudio: Bool = true

    var level: Level { Level.from(rating: rating) }
}
