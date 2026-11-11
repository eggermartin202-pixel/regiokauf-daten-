import SwiftUI

struct StatsView: View {
    @EnvironmentObject var store: AppStore
    @State private var retake = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Card {
                        HStack {
                            LevelBadge(level: store.state.level)
                            Text(store.state.level.title).font(.headline)
                            Spacer()
                            Text(String(format: "%.2f", store.state.rating))
                                .font(.title3.weight(.bold)).monospacedDigit()
                        }
                        Text("Der Wert (0–5) wird nach jeder Antwort neu geschätzt. Überraschend richtige Antworten auf schwere Aufgaben heben ihn stärker an.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Card {
                        Text("Letzte 7 Tage").font(.headline)
                        WeekChart(days: store.state.days)
                    }

                    Card {
                        Text("Abdeckung pro Niveau").font(.headline)
                        ForEach(Level.allCases) { level in
                            HStack {
                                Text(level.code).font(.subheadline.bold()).frame(width: 32, alignment: .leading)
                                ProgressBar(value: store.coverage(of: level), color: .success, height: 10)
                                Text("\(Int(store.coverage(of: level) * 100)) %")
                                    .font(.caption.monospacedDigit())
                                    .frame(width: 44, alignment: .trailing)
                            }
                        }
                        Text("\(store.learnedCount) gelernt · \(store.masteredCount) sicher · \(Content.allItems.count) insgesamt")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Card {
                        Text("Themen").font(.headline)
                        if store.state.tagStats.isEmpty {
                            Text("Noch keine Daten – starte eine Lektion.").foregroundStyle(.secondary)
                        }
                        ForEach(sortedTags, id: \.self) { tag in
                            let stat = store.state.tagStats[tag] ?? TagStat()
                            HStack {
                                Text(tag).font(.subheadline)
                                Spacer()
                                Text("\(Int(stat.recent * 100)) %")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(stat.recent < 0.7 ? Color.brand : Color.success)
                            }
                        }
                    }

                    if !store.state.placementHistory.isEmpty {
                        Card {
                            Text("Einstufungen").font(.headline)
                            ForEach(Array(store.state.placementHistory.enumerated()), id: \.offset) { _, record in
                                HStack {
                                    Text(record.date, style: .date).font(.subheadline)
                                    Spacer()
                                    LevelBadge(level: record.level)
                                    Text("\(record.correct)/\(record.total)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Button("Einstufungstest wiederholen") { retake = true }
                        .buttonStyle(PrimaryButtonStyle(color: Color(red: 0.22, green: 0.27, blue: 0.38)))
                }
                .padding(20)
            }
            .navigationTitle("Fortschritt")
        }
        .fullScreenCover(isPresented: $retake) {
            PlacementFlowView(isRetake: true).environmentObject(store)
        }
    }

    private var sortedTags: [String] {
        store.state.tagStats.keys.sorted {
            (store.state.tagStats[$0]?.recent ?? 0) < (store.state.tagStats[$1]?.recent ?? 0)
        }
    }
}

struct WeekChart: View {
    let days: [String: Int]

    private var values: [(label: String, count: Int)] {
        let cal = Calendar.current
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEEEEE"
        return (0..<7).reversed().compactMap { offset in
            guard let date = cal.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            return (f.string(from: date), days[AppStore.dayKey(date)] ?? 0)
        }
    }

    var body: some View {
        let data = values
        let maxValue = max(1, data.map(\.count).max() ?? 1)
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(0..<data.count, id: \.self) { i in
                VStack(spacing: 4) {
                    Text("\(data[i].count)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(data[i].count > 0 ? Color.brand : Color(.systemGray5))
                        .frame(height: max(6, 90 * CGFloat(data[i].count) / CGFloat(maxValue)))
                    Text(data[i].label).font(.caption2)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 130, alignment: .bottom)
    }
}
