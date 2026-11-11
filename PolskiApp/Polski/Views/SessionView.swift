import SwiftUI
import UIKit

struct SessionView: View {
    @StateObject private var model: SessionModel
    @Environment(\.dismiss) private var dismiss

    init(store: AppStore, mode: SessionMode) {
        _model = StateObject(wrappedValue: SessionModel(store: store, mode: mode))
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.finished {
                SessionSummaryView(model: model) { dismiss() }
            } else if let exercise = model.exercise {
                topBar
                if let hint = model.difficultyHint {
                    Text(hint)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Capsule())
                        .padding(.top, 6)
                }
                ExerciseView(model: model, exercise: exercise)
                    .id(exercise.id)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.exercise?.id)
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.headline).foregroundStyle(.secondary)
            }
            ProgressBar(value: model.progress)
            if model.comboStreak >= 3 {
                Label("\(model.comboStreak)", systemImage: "flame.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.warning)
                    .transition(.scale)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
}

// MARK: - Einzelne Aufgabe

struct ExerciseView: View {
    @ObservedObject var model: SessionModel
    let exercise: Exercise
    @EnvironmentObject var store: AppStore

    @State private var selected: String?
    @State private var typed = ""
    @State private var tiles: [Int] = []
    @FocusState private var fieldFocused: Bool

    private var answered: Bool { model.feedback != nil }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(exercise.instruction.uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    promptView
                    inputView
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            bottomPanel
        }
        .onAppear {
            if exercise.kind.isTyping {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { fieldFocused = true }
            }
        }
    }

    // MARK: Prompt

    @ViewBuilder
    private var promptView: some View {
        switch exercise.kind {
        case .intro:
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    Text(exercise.prompt).font(.largeTitle.weight(.bold))
                    Spacer()
                    if let audio = exercise.audio { SpeakButton(text: audio) }
                }
                Text(exercise.solution).font(.title2).foregroundStyle(.secondary)
                if let note = exercise.note {
                    Label(note, systemImage: "lightbulb.fill")
                        .font(.callout)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.warning.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        case .listenChoose, .dictation:
            HStack {
                Spacer()
                if let audio = exercise.audio {
                    VStack(spacing: 10) {
                        SpeakButton(text: audio, size: 44)
                        Button("Langsam") { Speaker.shared.speak(audio, slow: true) }
                            .font(.subheadline.weight(.semibold))
                    }
                }
                Spacer()
            }
            .padding(.vertical, 20)
        case .clozeChoose, .clozeType:
            VStack(alignment: .leading, spacing: 8) {
                Text(exercise.prompt.replacingOccurrences(of: "___", with: "_____"))
                    .font(.title.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                if let translation = exercise.translation {
                    Text(translation).foregroundStyle(.secondary)
                }
            }
        default:
            HStack(alignment: .top) {
                Text(exercise.prompt)
                    .font(.title.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if exercise.promptIsPolish, let audio = exercise.audio { SpeakButton(text: audio) }
            }
        }
    }

    // MARK: Eingabe

    @ViewBuilder
    private var inputView: some View {
        if exercise.kind.isChoice {
            VStack(spacing: 12) {
                ForEach(exercise.options, id: \.self) { option in
                    Button(option) { if !answered { selected = option } }
                        .buttonStyle(OptionButtonStyle(state: optionState(option)))
                }
            }
        } else if exercise.kind.isTyping {
            VStack(alignment: .leading, spacing: 10) {
                TextField(exercise.targetIsPolish ? "Auf Polnisch …" : "Auf Deutsch …", text: $typed)
                    .font(.title3)
                    .padding(14)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($fieldFocused)
                    .disabled(answered)
                    .submitLabel(.done)
                    .onSubmit { check() }
                if exercise.targetIsPolish && !answered { DiacriticsBar(text: $typed) }
            }
        } else if exercise.kind == .build {
            buildView
        }
    }

    private var buildView: some View {
        VStack(alignment: .leading, spacing: 18) {
            FlowLayout(spacing: 8) {
                ForEach(tiles, id: \.self) { index in
                    tile(exercise.options[index], highlighted: true) {
                        if !answered { tiles.removeAll { $0 == index } }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
            .padding(10)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.separator), style: StrokeStyle(lineWidth: 1, dash: [5])))

            FlowLayout(spacing: 8) {
                ForEach(Array(exercise.options.enumerated()), id: \.offset) { index, word in
                    tile(word, highlighted: false) {
                        if !answered && !tiles.contains(index) { tiles.append(index) }
                    }
                    .opacity(tiles.contains(index) ? 0.25 : 1)
                }
            }
        }
    }

    private func tile(_ word: String, highlighted: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(word)
                .font(.title3.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(highlighted ? Color.brand.opacity(0.12) : Color(.secondarySystemBackground))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.separator), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func optionState(_ option: String) -> OptionButtonStyle.OptionState {
        guard answered else { return selected == option ? .selected : .normal }
        if exercise.accepted.contains(option) { return .correct }
        if selected == option { return .wrong }
        return .normal
    }

    // MARK: Unterer Bereich

    private var currentAnswer: String {
        if exercise.kind.isChoice { return selected ?? "" }
        if exercise.kind == .build { return tiles.map { exercise.options[$0] }.joined(separator: " ") }
        return typed
    }

    private var canCheck: Bool {
        !currentAnswer.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func check() {
        guard canCheck, !answered else { return }
        fieldFocused = false
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            model.submit(currentAnswer)
        }
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(model.feedback?.verdict.countsAsCorrect == true ? .success : .error)
    }

    @ViewBuilder
    private var bottomPanel: some View {
        if exercise.kind == .intro {
            Button("Verstanden") { model.advance() }
                .buttonStyle(PrimaryButtonStyle())
                .padding(20)
        } else if let feedback = model.feedback {
            FeedbackPanel(feedback: feedback) { model.advance() }
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            HStack(spacing: 12) {
                if exercise.kind.isTyping || exercise.kind == .build {
                    Button("Weiß nicht") { model.submit("") }
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                }
                Button("Prüfen") { check() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canCheck)
            }
            .padding(20)
        }
    }
}

// MARK: - Rückmeldung

struct FeedbackPanel: View {
    let feedback: Feedback
    let onContinue: () -> Void

    private var color: Color {
        switch feedback.verdict {
        case .correct: return .success
        case .accents, .typo: return .warning
        case .wrong: return .brand
        }
    }

    private var title: String {
        switch feedback.verdict {
        case .correct:
            let praise = ["Super!", "Świetnie!", "Genau!", "Brawo!"]
            return praise[feedback.solution.count % praise.count]
        case .accents: return "Fast – achte auf die Sonderzeichen"
        case .typo: return "Richtig, mit kleinem Tippfehler"
        case .wrong: return feedback.userAnswer.isEmpty ? "Lösung" : "Nicht ganz"
        }
    }

    private var accentHint: String? {
        if case .accents(let hint) = feedback.verdict, !hint.isEmpty { return hint }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: feedback.verdict == .wrong ? "xmark.circle.fill" : "checkmark.circle.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(color)

            if feedback.verdict != .correct {
                Text(feedback.solution).font(.headline)
            }
            if let hint = accentHint {
                Text("Gefehlt: " + hint).font(.subheadline)
            }
            if let note = feedback.note, feedback.verdict != .correct {
                Text(note).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if feedback.verdict == .wrong {
                Text("Kommt in dieser Lektion noch einmal dran.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Weiter", action: onContinue)
                .buttonStyle(PrimaryButtonStyle(color: color))
                .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.12))
    }
}

/// Schnelleingabe polnischer Sonderzeichen – auch ohne polnische Tastatur.
struct DiacriticsBar: View {
    @Binding var text: String
    private let letters = ["ą", "ć", "ę", "ł", "ń", "ó", "ś", "ź", "ż"]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(letters, id: \.self) { letter in
                Button(letter) { text.append(letter) }
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Zusammenfassung

struct SessionSummaryView: View {
    @ObservedObject var model: SessionModel
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                if model.isEmpty {
                    Text("Gerade nichts zu tun 🎉").font(.title.weight(.bold)).padding(.top, 60)
                    Text("Alles wiederholt. Starte eine neue Lektion, um weiterzumachen.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                } else {
                    Text(model.accuracy >= 0.8 ? "Świetnie! 🎉" : "Gut gemacht! 💪")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .padding(.top, 40)
                    HStack(spacing: 12) {
                        summaryTile("\(Int(model.accuracy * 100)) %", "Trefferquote")
                        summaryTile("\(model.answered)", "Aufgaben")
                        summaryTile(String(format: "%+.2f", model.ratingDelta), "Niveau-Wert")
                    }
                    if !model.mistakes.isEmpty {
                        Card {
                            Text("Das wiederholen wir bald").font(.headline)
                            ForEach(model.mistakes) { item in
                                Text(label(for: item)).font(.subheadline)
                            }
                        }
                    }
                }
                Button("Fertig", action: onClose)
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(20)
        }
    }

    private func summaryTile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.weight(.bold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func label(for item: LearningItem) -> String {
        switch item {
        case .vocab(let v): return Alt.primary(v.pl) + " – " + Alt.primary(v.de)
        case .grammar(let g): return g.tag + ": " + g.sentence.replacingOccurrences(of: "___", with: g.answer)
        }
    }
}

// MARK: - Fließ-Layout für Wortbausteine

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
