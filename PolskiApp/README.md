# Polski – adaptive Polnisch-Lern-App (iOS)

SwiftUI-App, iOS 17+, ohne externe Abhängigkeiten, ohne Server. Alles läuft lokal auf dem Gerät.

## Starten

1. Ordner auf einen Mac holen, `PolskiApp/Polski.xcodeproj` in **Xcode 16 oder neuer** öffnen.
2. Unter *Signing & Capabilities* dein Apple-ID-Team wählen und die Bundle-ID
   `de.example.polski` in etwas Eigenes ändern (z. B. `de.deinname.polski`).
3. iPhone per Kabel anschließen → ▶︎. Mit einer kostenlosen Apple-ID läuft die App 7 Tage,
   danach einfach neu aufspielen.

## Was die App anders macht

| Baustein | Umsetzung |
|---|---|
| Einstufung | Adaptiver Test (18 Fragen) mit IRT-Modell: jede Frage wird passend zur aktuellen Schätzung gewählt, Rate-Wahrscheinlichkeit wird herausgerechnet. „Weiß ich nicht“ verfälscht nichts. |
| Niveau | Kein fester Kurs: die Fähigkeits-Schätzung (0–5 ≙ A0–B2) wird nach **jeder** Antwort per Elo-Update angepasst. |
| Wiederholung | SM-2-Spaced-Repetition pro Wort/Regel. Häufig vergessene Elemente zuerst. |
| Dynamische Aufgaben | Format-Leiter: Auswahl → Rückübersetzung → Hören → Satzbau → Tippen → Diktat. Läuft es gut, wird's schwerer, sonst leichter – live innerhalb der Lektion. |
| Fehler-Feedback | Erkennt fehlende Sonderzeichen („Gefehlt: ą, ł“) und Tippfehler, erklärt Grammatik-Regeln. |
| Schwächen | Trefferquote pro Thema/Fall; „Gezielt trainieren“ baut eine Lektion nur daraus. |
| Grammatik-Geschlecht | Vergangenheit/Konditional passend zu dir (byłem/byłam, poszedłem/poszłam). |
| Audio | Polnische Systemstimme, normal & langsam. |

## Inhalte erweitern

Alles steht in `Polski/Model/Content.swift`. Neue Zeile `v("polnisch", "deutsch|alternative", .a2, "Thema")`
bzw. `g(...)` für Grammatik-Lücken. IDs vorhandener Einträge nicht ändern (daran hängt der Fortschritt).

## Grenzen (ehrlich)

- 177 Lerneinheiten (147 Wörter/Sätze, 30 Grammatik-Regeln). Das reicht für einige Wochen, nicht für B2-Abschluss.
- Keine Spracherkennung (Aussprache wird nicht bewertet).
- Inhalte sind statisch. Wirklich offene Übungen (freies Schreiben, Gespräche) bräuchten ein LLM-Backend.
