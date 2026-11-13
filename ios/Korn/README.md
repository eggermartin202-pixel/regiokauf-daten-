# Korn – Filmkamera mit On-Device-AI

Eigenständige iPhone-Kamera-App (SwiftUI, iOS 17+). Funktionsumfang orientiert sich an
Film-Kamera-Apps mit AI-Kompositionshilfe; Name, Design und alle Film-Rezepte sind eigene Arbeit.

Alles läuft lokal auf dem Gerät: kein Konto, kein Server, kein Abo, keine Netzwerkzugriffe.

## Funktionen

- Live-Vorschau mit 13 Film-Looks (Farbe, Dia, Kinofilm mit Lichthof, CCD mit Datumsstempel,
  Sofortbild, Schwarzweiß), Stärke stufenlos regelbar – Core Image auf der GPU (Metal)
- AI-Kompositionshilfe: erkennt Motiv, Gesichter und Horizont (Vision) und führt per Overlay
  zum Zielpunkt (Drittelregel, Augenlinie, Symmetrie), mit Haptik bei Treffer
- AI-Look-Vorschlag aus Szenenklassifikation, Helligkeit und Farbstimmung
- Porträtmodus: Personensegmentierung + Hintergrundunschärfe, kombinierbar mit jedem Look
- Raster, Wasserwaage, Blitz, Selbstauslöser, Belichtungskorrektur, Tippen zum Fokussieren,
  Objektivwechsel und Pinch-Zoom, Frontkamera, Formate 3:4 / 1:1 / 2:3 / 9:16
- Galerie in der App, Speichern in die Fotomediathek (HEIC, bis ~24 MP), Teilen, Löschen
- Vorhandene Fotos importieren und mit dem aktuellen Look entwickeln

Nicht enthalten: Live Photos, Video.

## Bauen

Voraussetzung: Mac mit Xcode 16 oder neuer.

```sh
brew install xcodegen
cd ios/Korn
xcodegen generate
open Korn.xcodeproj
```

In Xcode unter *Signing & Capabilities* das eigene Team wählen, iPhone anschließen, starten.
Die Kamera funktioniert nur auf einem echten Gerät, nicht im Simulator.

## Aufbau

| Ordner | Inhalt |
| --- | --- |
| `Sources/Film` | Look-Rezepte (`FilmLook`) und Core-Image-Graph (`FilmRenderer`) |
| `Sources/Camera` | Aufnahme-Session, Frame-Pipeline, Metal-Vorschau |
| `Sources/AI` | Szenenanalyse, Kompositionslogik, Look-Empfehlung, Porträt-Effekt |
| `Sources/UI` | SwiftUI-Oberfläche |
