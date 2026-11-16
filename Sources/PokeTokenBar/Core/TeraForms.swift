import Foundation

/// Ogerpon and Terapagos, whose Terastal forms come from held items: Ogerpon's masks and the Stellar Crystal.
/// Like a Mega Stone, the item only changes the sprite and types shown; species, level and save data stay.
enum TeraForm {
    static let ogerpon = 1017
    static let terapagos = 1024

    /// What the holder is drawn as: a PokéAPI form sprite id and the types that form has.
    struct Sprite: Hashable, Sendable {
        let id: Int
        let types: [String]
        /// hp, attack, defense, special-attack, special-defense, speed; only for a form whose stats differ from the base.
        var stats: [Int]? = nil
    }
}
