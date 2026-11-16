import Foundation

/// A Mega Stone was just put on, or taken off, a Pokémon that matches it. Never saved: a relaunch has none.
struct MegaEvolveEvent: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case equip, unequip }

    let id: Int
    let kind: Kind
    let instanceID: String
    /// The Mega sprite that appears (`equip`) or goes away (`unequip`).
    let megaSpriteID: Int
    let at: Date
}
