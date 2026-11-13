import Foundation
import simd

/// Ein Film-Look als reine Parameterliste. Alle Rezepte sind eigene Abstimmungen,
/// keine Kopien fremder LUTs.
struct FilmLook: Identifiable, Equatable {
    let id: String
    let name: String
    let detail: String
    var exposure: Float = 0                      // EV
    var contrast: Float = 1
    var saturation: Float = 1
    var warmth: Float = 0                        // -1 kühl … +1 warm
    var tint: Float = 0                          // -1 grün … +1 magenta
    var fade: Float = 0                          // angehobene Schwarztöne
    var shadowTint = SIMD3<Float>(0, 0, 0)       // Farbstich in den Tiefen
    var highlightTint = SIMD3<Float>(0, 0, 0)    // Farbstich in den Lichtern
    var curve: [Float] = [0, 0.25, 0.5, 0.75, 1] // Tonkurve bei x = 0, ¼, ½, ¾, 1
    var grain: Float = 0
    var grainSize: Float = 1
    var vignette: Float = 0
    var halation: Float = 0                      // roter Lichthof um Spitzlichter
    var bloom: Float = 0
    var mono = false
    var dateStamp = false
}

extension FilmLook {
    static let all: [FilmLook] = [
        FilmLook(id: "natur", name: "Natur", detail: "Neutral, nur ein Hauch Korn",
                 contrast: 1.03, grain: 0.08),
        FilmLook(id: "bernstein", name: "Bernstein", detail: "Warmer Alltagsfilm, goldene Lichter",
                 contrast: 1.06, saturation: 1.12, warmth: 0.45, fade: 0.02,
                 highlightTint: SIMD3(0.03, 0.01, -0.03),
                 curve: [0, 0.22, 0.5, 0.78, 1], grain: 0.22, vignette: 0.25, halation: 0.15),
        FilmLook(id: "samt", name: "Samt", detail: "Weicher Porträtfilm, pastellige Haut",
                 exposure: 0.15, contrast: 0.94, saturation: 0.92, warmth: 0.2, fade: 0.035,
                 shadowTint: SIMD3(0, 0.008, 0.012),
                 curve: [0.02, 0.27, 0.52, 0.76, 0.97], grain: 0.14, bloom: 0.15),
        FilmLook(id: "dia-v", name: "Dia V", detail: "Kräftiger Diafilm für Landschaft",
                 contrast: 1.16, saturation: 1.38, tint: 0.1,
                 curve: [0, 0.2, 0.5, 0.8, 1], grain: 0.06, vignette: 0.2),
        FilmLook(id: "dia-p", name: "Dia P", detail: "Präziser Diafilm, klare Farben",
                 contrast: 1.1, saturation: 1.12, warmth: -0.08,
                 curve: [0, 0.23, 0.5, 0.78, 1], grain: 0.06),
        FilmLook(id: "smaragd", name: "Smaragd", detail: "Grünstichige Tiefen, kühle Straße",
                 contrast: 1.08, saturation: 1.05, warmth: -0.1, tint: -0.25, fade: 0.02,
                 shadowTint: SIMD3(-0.01, 0.015, 0.005),
                 grain: 0.2, vignette: 0.2),
        FilmLook(id: "agora", name: "Agora", detail: "Rotbetont, leicht verblasst",
                 contrast: 1.04, saturation: 1.15, warmth: 0.25, tint: 0.2, fade: 0.045,
                 highlightTint: SIMD3(0.04, 0, -0.02),
                 grain: 0.26, vignette: 0.3, halation: 0.1),
        FilmLook(id: "tungsten", name: "Tungsten", detail: "Kinofilm für Nacht, roter Lichthof",
                 exposure: 0.2, contrast: 1.05, saturation: 1.05, warmth: -0.5, fade: 0.03,
                 shadowTint: SIMD3(-0.01, 0.005, 0.02),
                 curve: [0, 0.24, 0.52, 0.78, 0.98], grain: 0.32, grainSize: 1.3,
                 vignette: 0.3, halation: 0.75, bloom: 0.2),
        FilmLook(id: "ccd", name: "CCD 2004", detail: "Kompaktkamera-Look mit Datum",
                 exposure: 0.1, contrast: 1.2, saturation: 1.18, warmth: -0.12,
                 highlightTint: SIMD3(-0.01, 0, 0.03),
                 curve: [0, 0.19, 0.5, 0.83, 1], grain: 0.1, grainSize: 0.7,
                 bloom: 0.35, dateStamp: true),
        FilmLook(id: "sofort", name: "Sofort", detail: "Sofortbild: weich, cyan, starke Vignette",
                 contrast: 0.9, saturation: 0.88, warmth: 0.15, fade: 0.07,
                 shadowTint: SIMD3(-0.015, 0.01, 0.02), highlightTint: SIMD3(0.03, 0.02, -0.03),
                 curve: [0.03, 0.27, 0.52, 0.75, 0.95], grain: 0.18, vignette: 0.6, bloom: 0.2),
        FilmLook(id: "verblasst", name: "Verblasst", detail: "Abgelaufener Film, Magentastich",
                 contrast: 0.92, saturation: 0.8, warmth: 0.1, tint: 0.4, fade: 0.09,
                 grain: 0.4, grainSize: 1.4, vignette: 0.35, halation: 0.2),
        FilmLook(id: "silber", name: "Silber", detail: "Klassisches Schwarzweiß",
                 contrast: 1.12, curve: [0, 0.21, 0.5, 0.79, 1],
                 grain: 0.28, vignette: 0.25, mono: true),
        FilmLook(id: "korn3200", name: "Korn 3200", detail: "Gepushtes Schwarzweiß, grobes Korn",
                 exposure: 0.1, contrast: 1.3, fade: 0.03,
                 shadowTint: SIMD3(0.006, 0.003, 0), curve: [0, 0.17, 0.5, 0.84, 1],
                 grain: 0.7, grainSize: 1.8, vignette: 0.4, mono: true),
    ]

    static func named(_ id: String) -> FilmLook { all.first { $0.id == id } ?? all[0] }
}
