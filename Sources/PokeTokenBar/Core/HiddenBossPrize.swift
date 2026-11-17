import Foundation

/// What a region's first hidden boss clear pays on top of its TM.
struct HiddenBossPrize: Equatable, Sendable {
    let region: PokedexRegion
    /// The species of the guaranteed-shiny egg.
    let eggSpeciesID: Int
    /// Inventory keys of the signature items, one copy each.
    let itemKeys: [String]

    /// Worth one guaranteed-legendary egg at shop prices, paid in Rare Candies.
    static var candyCount: Int { FreshEgg.price(guaranteeing: .legendary) / RareCandy.price }

    static let eggKeyPrefix = "shiny-egg:"
    var eggKey: String { Self.eggKey(eggSpeciesID) }
    static func eggKey(_ speciesID: Int) -> String { eggKeyPrefix + String(speciesID) }

    static func prize(for regionID: String) -> HiddenBossPrize? { all.first { $0.region.rawValue == regionID } }

    static let all: [HiddenBossPrize] = [
        HiddenBossPrize(region: .kanto, eggSpeciesID: 150, itemKeys: megaStones("mewtwonite-x", "mewtwonite-y")),
        HiddenBossPrize(region: .johto, eggSpeciesID: 251, itemKeys: []),
        HiddenBossPrize(region: .hoenn, eggSpeciesID: 384, itemKeys: []),
        HiddenBossPrize(region: .sinnoh, eggSpeciesID: 493, itemKeys: ItemKind.plates.map(\.rawValue)),
        HiddenBossPrize(region: .unova, eggSpeciesID: 494, itemKeys: [ItemKind.charcoal.rawValue]),
        HiddenBossPrize(region: .kalos, eggSpeciesID: 718, itemKeys: megaStones("zygardite")),
        HiddenBossPrize(region: .alola, eggSpeciesID: 800, itemKeys: []),
        HiddenBossPrize(region: .galar, eggSpeciesID: 890, itemKeys: [ItemKind.blackSludge.rawValue]),
        HiddenBossPrize(region: .paldea, eggSpeciesID: 1024, itemKeys: [ItemKind.stellarCrystal.rawValue]),
    ]

    private static func megaStones(_ slugs: String...) -> [String] {
        slugs.compactMap { MegaStone.stone(slug: $0)?.inventoryKey }
    }
}
