import SwiftUI

/// ♂/♀ in the main-series colors, as `Text` so it can ride at the end of a line of nature text.
enum GenderGlyph {
    static func text(_ gender: PokemonGender?, leadingSpace: Bool = false) -> Text {
        guard let gender, let symbol = gender.symbol else { return Text("") }
        let glyph = Text(symbol).foregroundStyle(gender == .female ? Color.pink : Color.blue)
        return leadingSpace ? Text(" ") + glyph : glyph
    }
}
