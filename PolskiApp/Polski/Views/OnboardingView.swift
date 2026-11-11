import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var store: AppStore
    @State private var name = ""
    @State private var gender: Gender = .male

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cześć! 👋")
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                    Text("Polnisch lernen – angepasst an dich, nicht an einen starren Kurs.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 40)

                Card {
                    Label("So funktioniert's", systemImage: "sparkles").font(.headline)
                    bullet("Ein adaptiver Test findet in ~3 Minuten dein Niveau (A0–B2).")
                    bullet("Jede Antwort passt Schwierigkeit und Aufgabentyp live an.")
                    bullet("Wiederholung genau dann, wenn du kurz vor dem Vergessen bist.")
                    bullet("Fehler werden erklärt – inklusive fehlender ą, ę, ł & Co.")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Wie heißt du?").font(.headline)
                    TextField("Dein Vorname", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.words)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Wie sollen Verbformen für dich lauten?").font(.headline)
                    Text("Im Polnischen hängt die Vergangenheit vom Geschlecht ab: „byłem“ oder „byłam“.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("Form", selection: $gender) {
                        ForEach(Gender.allCases) { g in Text(g.label).tag(g) }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(spacing: 12) {
                    Button("Einstufungstest starten") { finish(skip: false) }
                        .buttonStyle(PrimaryButtonStyle())
                    Button("Ich kann noch gar kein Polnisch") { finish(skip: true) }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }
            .padding(24)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.brand)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func finish(skip: Bool) {
        var s = store.state
        s.name = name.trimmingCharacters(in: .whitespaces)
        s.gender = gender
        s.onboarded = true
        store.state = s
        if skip { store.skipPlacement() }
    }
}
