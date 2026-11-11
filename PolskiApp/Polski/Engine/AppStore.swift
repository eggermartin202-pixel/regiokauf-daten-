import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {

    @Published var state: UserState {
        didSet { save() }
    }

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("polski-state.json")
    }()

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(UserState.self, from: data) {
            state = decoded
        } else {
            state = UserState()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func resetAll() {
        state = UserState()
    }

    // MARK: - Einstufung

    func finishPlacement(theta: Double, answers: [PlacementEngine.Answer]) {
        var s = state
        s.rating = theta
        s.placementDone = true
        s.placementHistory.append(PlacementRecord(
            date: Date(), level: Level.from(rating: theta), rating: theta,
            correct: answers.filter(\.correct).count, total: answers.count))

        // Richtig beantwortete Elemente gelten als „bekannt“ und kommen erst später zur Wiederholung.
        let now = Date()
        for answer in answers where answer.correct {
            var p = s.progress[answer.question.itemID] ?? ItemProgress()
            if p.seen == 0 {
                p.record(quality: 4, now: now)
                p.record(quality: 4, now: now) // direkt auf 3-Tage-Intervall
                s.progress[answer.question.itemID] = p
            }
        }
        state = s
    }

    func skipPlacement() {
        var s = state
        s.rating = 0.3
        s.placementDone = true
        state = s
    }

    // MARK: - Lernen

    /// Verbucht eine Antwort: SRS-Planung, Tag-Statistik, Elo-artige Fähigkeits-Schätzung.
    func record(item: LearningItem, verdict: Verdict, formatDifficulty: Double, isChoice: Bool) {
        var s = state
        let now = Date()

        let quality: Int
        switch verdict {
        case .correct: quality = isChoice ? 4 : 5
        case .accents, .typo: quality = 3
        case .wrong: quality = 1
        }
        var p = s.progress[item.id] ?? ItemProgress()
        p.record(quality: quality, now: now)
        s.progress[item.id] = p

        let ok = verdict.countsAsCorrect
        var tag = s.tagStats[item.tag] ?? TagStat()
        tag.seen += 1
        if ok { tag.correct += 1 }
        tag.recent = tag.recent * 0.8 + (ok ? 0.2 : 0)
        s.tagStats[item.tag] = tag

        // Elo-Update der Fähigkeit: Überraschungen bewegen die Schätzung, Erwartbares kaum.
        let difficulty = item.difficulty + formatDifficulty
        let guessing = isChoice ? 0.25 : 0
        let expected = PlacementEngine.probability(theta: s.rating, difficulty: difficulty, guessing: guessing)
        s.rating = min(5, max(0, s.rating + 0.06 * ((ok ? 1 : 0) - expected)))

        s.recentAccuracy = s.recentAccuracy * 0.9 + (ok ? 0.1 : 0)
        s.days[Self.dayKey(now), default: 0] += 1
        state = s
    }

    // MARK: - Kennzahlen

    static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    var todayCount: Int { state.days[Self.dayKey(Date())] ?? 0 }

    var streakDays: Int {
        let cal = Calendar.current
        var day = Date()
        var count = 0
        // Heute zählt mit, darf aber noch offen sein.
        if (state.days[Self.dayKey(day)] ?? 0) == 0 {
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        while (state.days[Self.dayKey(day)] ?? 0) > 0 {
            count += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return count
    }

    var dueCount: Int {
        let now = Date()
        return state.progress.filter { Content.itemsByID[$0.key] != nil && $0.value.due <= now }.count
    }

    var learnedCount: Int { state.progress.values.filter { $0.streak >= 2 }.count }
    var masteredCount: Int { state.progress.values.filter { $0.mastery >= 0.8 }.count }

    /// Schwachstellen: Themen mit genug Daten und niedriger aktueller Trefferquote.
    struct WeakTag: Identifiable {
        let tag: String
        let stat: TagStat
        var id: String { tag }
    }

    var weakTags: [WeakTag] {
        state.tagStats
            .filter { $0.value.seen >= 4 && $0.value.recent < 0.7 }
            .sorted { $0.value.recent < $1.value.recent }
            .map { WeakTag(tag: $0.key, stat: $0.value) }
    }

    /// Fortschritt innerhalb des aktuellen Niveaus (0…1).
    var levelProgress: Double {
        let r = min(state.rating, 4.999)
        return r - r.rounded(.down)
    }

    func coverage(of level: Level) -> Double {
        let items = Content.allItems.filter { $0.level == level }
        guard !items.isEmpty else { return 0 }
        let learned = items.filter { (state.progress[$0.id]?.streak ?? 0) >= 2 }.count
        return Double(learned) / Double(items.count)
    }
}
