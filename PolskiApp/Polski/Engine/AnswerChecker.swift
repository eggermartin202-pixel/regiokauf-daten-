import Foundation

enum Verdict: Equatable {
    case correct
    /// Richtig bis auf polnische Sonderzeichen. Enthält einen Hinweis wie „ą, ł“.
    case accents(hint: String)
    /// Kleiner Tippfehler – zählt als richtig.
    case typo
    case wrong

    var countsAsCorrect: Bool { self != .wrong }
}

enum AnswerChecker {

    private static let diacriticMap: [Character: Character] = [
        "ą": "a", "ć": "c", "ę": "e", "ł": "l", "ń": "n",
        "ó": "o", "ś": "s", "ź": "z", "ż": "z",
    ]

    private static let germanArticles: Set<String> = ["der", "die", "das", "ein", "eine", "einen"]

    static func normalize(_ text: String, stripGermanArticles: Bool = false) -> String {
        let lowered = text.lowercased()
            .replacingOccurrences(of: "ß", with: "ss")
            .replacingOccurrences(of: "’", with: "'")
        let allowed = lowered.unicodeScalars.map { scalar -> Character in
            CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar)
                ? Character(scalar) : " "
        }
        var words = String(allowed).split(separator: " ").map(String.init)
        if stripGermanArticles, let first = words.first, germanArticles.contains(first), words.count > 1 {
            words.removeFirst()
        }
        return words.joined(separator: " ")
    }

    static func foldDiacritics(_ text: String) -> String {
        String(text.map { diacriticMap[$0] ?? $0 })
    }

    /// Prüft eine Eingabe gegen alle akzeptierten Lösungen.
    static func check(_ input: String, accepted: [String], targetIsPolish: Bool) -> Verdict {
        let given = normalize(input, stripGermanArticles: !targetIsPolish)
        guard !given.isEmpty else { return .wrong }
        let solutions = accepted.map { normalize($0, stripGermanArticles: !targetIsPolish) }

        if solutions.contains(given) { return .correct }

        if targetIsPolish {
            let foldedGiven = foldDiacritics(given)
            for solution in solutions where foldDiacritics(solution) == foldedGiven {
                return .accents(hint: missingDiacritics(given: given, expected: solution))
            }
        }

        for solution in solutions {
            let distance = levenshtein(given, solution)
            let allowedTypos = solution.count >= 10 ? 2 : (solution.count >= 5 ? 1 : 0)
            if distance <= allowedTypos { return .typo }
            // Tippfehler UND fehlende Akzente kombiniert
            if targetIsPolish,
               levenshtein(foldDiacritics(given), foldDiacritics(solution)) <= allowedTypos {
                return .typo
            }
        }
        return .wrong
    }

    /// Liefert die Sonderzeichen, die in der Eingabe gefehlt haben – z. B. „ą, ł“.
    static func missingDiacritics(given: String, expected: String) -> String {
        let g = Array(given), e = Array(expected)
        guard g.count == e.count else { return "" }
        var missing: [Character] = []
        for (a, b) in zip(g, e) where a != b && diacriticMap[b] != nil {
            if !missing.contains(b) { missing.append(b) }
        }
        return missing.map(String.init).joined(separator: ", ")
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let s = Array(a), t = Array(b)
        if s.isEmpty { return t.count }
        if t.isEmpty { return s.count }
        var previous = Array(0...t.count)
        var current = [Int](repeating: 0, count: t.count + 1)
        for i in 1...s.count {
            current[0] = i
            for j in 1...t.count {
                let cost = s[i - 1] == t[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[t.count]
    }
}
