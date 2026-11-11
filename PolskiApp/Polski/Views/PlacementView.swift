import SwiftUI

/// Test + Ergebnis. Wird beim ersten Start und beim erneuten Einstufen genutzt.
struct PlacementFlowView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let isRetake: Bool
    @State private var engine: PlacementEngine?
    @State private var showResult = false

    var body: some View {
        Group {
            if let engine {
                if showResult {
                    PlacementResultView(engine: engine) {
                        store.finishPlacement(theta: engine.theta, answers: engine.answers)
                        if isRetake { dismiss() }
                    }
                } else {
                    PlacementQuestionView(engine: engine, isRetake: isRetake) {
                        withAnimation { showResult = true }
                    } onCancel: {
                        dismiss()
                    }
                }
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if engine == nil { engine = PlacementEngine(gender: store.state.gender) }
        }
    }
}

struct PlacementQuestionView: View {
    @ObservedObject var engine: PlacementEngine
    let isRetake: Bool
    let onFinish: () -> Void
    let onCancel: () -> Void
    @State private var selected: String?

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                if isRetake {
                    Button { onCancel() } label: { Image(systemName: "xmark").font(.headline) }
                        .foregroundStyle(.secondary)
                }
                ProgressBar(value: engine.progress)
                Text("\(engine.answers.count + 1)/\(engine.totalQuestions)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let q = engine.current {
                VStack(alignment: .leading, spacing: 16) {
                    Text(q.instruction.uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .top) {
                        Text(q.prompt)
                            .font(.title.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        if let audio = q.audio { SpeakButton(text: audio) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(q.id)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .opacity))

                Spacer()

                VStack(spacing: 12) {
                    ForEach(q.options, id: \.self) { option in
                        Button(option) { selected = option }
                            .buttonStyle(OptionButtonStyle(state: selected == option ? .selected : .normal))
                    }
                }

                HStack(spacing: 12) {
                    Button("Weiß ich nicht") { answer(nil) }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(.secondary)
                    Button("Weiter") { answer(selected) }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(selected == nil)
                }
            }
        }
        .padding(20)
        .onChange(of: engine.isFinished) { _, finished in
            if finished { onFinish() }
        }
    }

    private func answer(_ option: String?) {
        withAnimation(.easeInOut(duration: 0.25)) {
            engine.submit(option)
            selected = nil
        }
    }
}

struct PlacementResultView: View {
    @ObservedObject var engine: PlacementEngine
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Dein Niveau").font(.title2.weight(.semibold)).padding(.top, 32)
                LevelBadge(level: engine.level, large: true)
                Text(engine.level.title).font(.title.weight(.bold))
                Text(engine.level.summary)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                Card {
                    Text("Feinwert").font(.headline)
                    HStack {
                        ForEach(Level.allCases) { l in
                            Text(l.code).font(.caption.bold()).frame(maxWidth: .infinity)
                        }
                    }
                    ProgressBar(value: engine.theta / 5)
                    Text(String(format: "%.1f von 5,0 · %d von %d richtig",
                                engine.theta, engine.correctCount, engine.answers.count))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Card {
                    Text("Nach Bereich").font(.headline)
                    ForEach(engine.areaResults) { result in
                        HStack {
                            Text(result.area)
                            Spacer()
                            Text("\(result.correct)/\(result.total)").monospacedDigit().foregroundStyle(.secondary)
                        }
                        ProgressBar(value: result.total == 0 ? 0 : Double(result.correct) / Double(result.total),
                                    color: .success, height: 8)
                    }
                }

                let wrong = engine.answers.filter { !$0.correct }
                if !wrong.isEmpty {
                    Card {
                        Text("Daran arbeiten wir").font(.headline)
                        ForEach(wrong.prefix(6), id: \.question.id) { a in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.question.prompt.components(separatedBy: "\n").first ?? "")
                                    .font(.subheadline.weight(.semibold))
                                Text("Richtig: " + a.question.answer)
                                    .font(.footnote)
                                    .foregroundStyle(Color.success)
                            }
                        }
                    }
                }

                Button("Los geht's", action: onContinue)
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(20)
        }
    }
}
