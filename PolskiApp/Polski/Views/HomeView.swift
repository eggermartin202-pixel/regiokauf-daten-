import SwiftUI

struct SessionLaunch: Identifiable {
    let id = UUID()
    let mode: SessionMode
}

struct HomeView: View {
    @EnvironmentObject var store: AppStore
    @State private var launch: SessionLaunch?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    levelCard
                    dailyCard
                    actions
                    if !store.weakTags.isEmpty { weaknessCard }
                }
                .padding(20)
            }
            .navigationTitle(greeting)
        }
        .fullScreenCover(item: $launch) { launch in
            SessionView(store: store, mode: launch.mode)
                .environmentObject(store)
        }
    }

    private var greeting: String {
        store.state.name.isEmpty ? "Cześć!" : "Cześć, \(store.state.name)!"
    }

    private var header: some View {
        HStack(spacing: 12) {
            statPill(icon: "flame.fill", value: "\(store.streakDays)", label: "Tage", color: .warning)
            statPill(icon: "checkmark.seal.fill", value: "\(store.learnedCount)", label: "gelernt", color: .success)
            statPill(icon: "clock.arrow.circlepath", value: "\(store.dueCount)", label: "fällig", color: .brand)
        }
    }

    private func statPill(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(color)
            Text(value).font(.title2.weight(.bold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var levelCard: some View {
        Card {
            HStack {
                LevelBadge(level: store.state.level)
                Text(store.state.level.title).font(.headline)
                Spacer()
                if store.state.level < .b2 {
                    Text("→ " + (Level(rawValue: store.state.level.rawValue + 1)?.code ?? ""))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            ProgressBar(value: store.levelProgress)
            Text("Dein Niveau bewegt sich mit jeder Antwort – es wird nicht nur einmal festgelegt.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var dailyCard: some View {
        Card {
            HStack {
                Text("Tagesziel").font(.headline)
                Spacer()
                Text("\(min(store.todayCount, store.state.dailyGoal))/\(store.state.dailyGoal)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressBar(value: Double(store.todayCount) / Double(max(1, store.state.dailyGoal)), color: .success)
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                launch = SessionLaunch(mode: .standard)
            } label: {
                Label("Lektion starten", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle())

            Button {
                launch = SessionLaunch(mode: .review)
            } label: {
                Label(store.dueCount > 0 ? "Wiederholen (\(store.dueCount) fällig)" : "Freies Wiederholen",
                      systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(PrimaryButtonStyle(color: Color(red: 0.22, green: 0.27, blue: 0.38)))
            .disabled(store.state.progress.isEmpty)
        }
    }

    private var weaknessCard: some View {
        Card {
            Label("Deine Schwachstellen", systemImage: "scope").font(.headline)
            ForEach(store.weakTags.prefix(3)) { weak in
                HStack {
                    Text(weak.tag)
                    Spacer()
                    Text("\(Int(weak.stat.recent * 100)) %")
                        .monospacedDigit()
                        .foregroundStyle(Color.brand)
                }
            }
            Button("Gezielt trainieren") {
                launch = SessionLaunch(mode: .focus(Set(store.weakTags.prefix(3).map(\.tag))))
            }
            .buttonStyle(PrimaryButtonStyle(color: .warning))
        }
    }
}
