import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Profil") {
                    TextField("Name", text: $store.state.name)
                    Picker("Verbformen", selection: $store.state.gender) {
                        ForEach(Gender.allCases) { g in Text(g.label).tag(g) }
                    }
                }
                Section("Lernen") {
                    Stepper("Tagesziel: \(store.state.dailyGoal) Aufgaben",
                            value: $store.state.dailyGoal, in: 10...150, step: 10)
                }
                Section {
                    Toggle("Audio automatisch abspielen", isOn: $store.state.autoPlayAudio)
                    Toggle("Langsame Aussprache", isOn: $store.state.slowAudio)
                    Button("Stimme testen") {
                        Speaker.shared.speak("Dzień dobry! Jak się masz?", slow: store.state.slowAudio)
                    }
                } header: {
                    Text("Audio")
                } footer: {
                    Text("Bessere Stimme: Einstellungen → Bedienungshilfen → Gesprochene Inhalte → Stimmen → Polnisch → „Zosia (Erweitert)“ laden.")
                }
                Section {
                    Button("Gesamten Fortschritt löschen", role: .destructive) { confirmReset = true }
                }
            }
            .navigationTitle("Einstellungen")
            .confirmationDialog("Wirklich alles löschen?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) { store.resetAll() }
            }
        }
    }
}
