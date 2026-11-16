import SwiftUI

/// Colors that have no system equivalent. Everything else uses semantic colors (`.primary`, `.secondary`,
/// `Color.accentColor`, `NSColor.controlBackgroundColor`) so light, dark and the user's accent color work.
enum Palette {
    /// Per-provider stack colors in the daily chart. A provider keeps its slot across launches.
    static let providerSeries: [Color] = [
        Color(red: 0.85, green: 0.47, blue: 0.34),
        Color(red: 0.36, green: 0.62, blue: 0.95),
        Color(red: 0.45, green: 0.78, blue: 0.52),
        Color(red: 0.78, green: 0.55, blue: 0.92),
        Color(red: 0.95, green: 0.76, blue: 0.32),
        Color(red: 0.35, green: 0.78, blue: 0.80),
        Color(red: 0.93, green: 0.51, blue: 0.68),
        Color(red: 0.62, green: 0.64, blue: 0.70),
        Color(red: 0.88, green: 0.80, blue: 0.60),
        Color(red: 0.70, green: 0.82, blue: 0.38),
        Color(red: 0.60, green: 0.42, blue: 0.30),
        Color(red: 0.30, green: 0.60, blue: 0.55),
        Color(red: 0.80, green: 0.35, blue: 0.40),
        Color(red: 0.40, green: 0.48, blue: 0.80),
        Color(red: 0.96, green: 0.58, blue: 0.22),
        Color(red: 0.76, green: 0.58, blue: 0.38),
    ]

    static let sun = Color(red: 1, green: 0.85, blue: 0.25)
    static let moon = Color(red: 0.93, green: 0.93, blue: 0.85)
    /// The Mega ring's keystone sweep; the last stop repeats the first so the gradient closes.
    static let megaKeystone: [Color] = [
        Color(red: 1.0, green: 0.44, blue: 0.71), Color(red: 0.61, green: 0.42, blue: 1.0),
        Color(red: 0.25, green: 0.82, blue: 1.0), Color(red: 0.36, green: 0.89, blue: 0.49),
        Color(red: 1.0, green: 0.85, blue: 0.29), Color(red: 1.0, green: 0.44, blue: 0.71),
    ]
    /// Gold tag for the Pokémon that stands for the box.
    static let representative = Color(red: 0.72, green: 0.48, blue: 0)
    static let heart = Color(red: 0xE0 / 255, green: 0x30 / 255, blue: 0x3C / 255)

    /// The handheld on the usage recap card: red shell, green LCD, amber highlights, three LEDs, a glass lens.
    enum Recap {
        static let shellTop = Color(red: 0.84, green: 0.21, blue: 0.18)
        static let shellBottom = Color(red: 0.66, green: 0.12, blue: 0.11)
        static let screenInk = Color(red: 0.05, green: 0.07, blue: 0.08)
        static let lcd = Color(red: 0.51, green: 0.98, blue: 0.62)
        static let amber = Color(red: 1.0, green: 0.73, blue: 0.28)
        static let ledRed = Color(red: 0.95, green: 0.35, blue: 0.35)
        static let ledYellow = Color(red: 0.98, green: 0.82, blue: 0.35)
        static let ledGreen = Color(red: 0.45, green: 0.88, blue: 0.5)
        static let lensHighlight = Color(red: 0.72, green: 0.88, blue: 1.0)
        static let lensBody = Color(red: 0.15, green: 0.45, blue: 0.85)
    }
}
