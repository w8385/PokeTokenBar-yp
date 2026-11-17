import Foundation

/// Battle items the bot engine knows: Primal orbs, Origin items, Punching Glove, resist berries and plates.
extension ItemKind {
    static let primalOrbs: [ItemKind] = [.redOrb, .blueOrb]
    static let originItems: [ItemKind] = [.adamantCrystal, .lustrousGlobe, .griseousCore]
    static let resistBerries: [ItemKind] = [
        .occaBerry, .passhoBerry, .wacanBerry, .rindoBerry, .yacheBerry, .chopleBerry, .kebiaBerry, .shucaBerry, .cobaBerry,
        .payapaBerry, .tangaBerry, .chartiBerry, .kasibBerry, .habanBerry, .colburBerry, .babiriBerry, .chilanBerry, .roseliBerry,
    ]
    static let plates: [ItemKind] = [
        .flamePlate, .splashPlate, .zapPlate, .meadowPlate, .iciclePlate, .fistPlate, .toxicPlate, .earthPlate, .skyPlate,
        .mindPlate, .insectPlate, .stonePlate, .spookyPlate, .dracoPlate, .dreadPlate, .ironPlate, .pixiePlate,
    ]
    static let championBattleItems: [ItemKind] = primalOrbs + originItems + [.punchingGlove] + resistBerries + plates

    /// The PokéAPI slug the bot knows; nil for every item outside `championBattleItems`.
    var championItemSlug: String? {
        switch self {
        case .redOrb: "red-orb"
        case .blueOrb: "blue-orb"
        case .adamantCrystal: "adamant-crystal"
        case .lustrousGlobe: "lustrous-globe"
        case .griseousCore: "griseous-core"
        case .punchingGlove: "punching-glove"
        case .occaBerry: "occa-berry"
        case .passhoBerry: "passho-berry"
        case .wacanBerry: "wacan-berry"
        case .rindoBerry: "rindo-berry"
        case .yacheBerry: "yache-berry"
        case .chopleBerry: "chople-berry"
        case .kebiaBerry: "kebia-berry"
        case .shucaBerry: "shuca-berry"
        case .cobaBerry: "coba-berry"
        case .payapaBerry: "payapa-berry"
        case .tangaBerry: "tanga-berry"
        case .chartiBerry: "charti-berry"
        case .kasibBerry: "kasib-berry"
        case .habanBerry: "haban-berry"
        case .colburBerry: "colbur-berry"
        case .babiriBerry: "babiri-berry"
        case .chilanBerry: "chilan-berry"
        case .roseliBerry: "roseli-berry"
        case .flamePlate: "flame-plate"
        case .splashPlate: "splash-plate"
        case .zapPlate: "zap-plate"
        case .meadowPlate: "meadow-plate"
        case .iciclePlate: "icicle-plate"
        case .fistPlate: "fist-plate"
        case .toxicPlate: "toxic-plate"
        case .earthPlate: "earth-plate"
        case .skyPlate: "sky-plate"
        case .mindPlate: "mind-plate"
        case .insectPlate: "insect-plate"
        case .stonePlate: "stone-plate"
        case .spookyPlate: "spooky-plate"
        case .dracoPlate: "draco-plate"
        case .dreadPlate: "dread-plate"
        case .ironPlate: "iron-plate"
        case .pixiePlate: "pixie-plate"
        default: nil
        }
    }

    /// The type whose hit a resist berry softens; Chilan softens Normal.
    var resistedType: String? {
        switch self {
        case .occaBerry: "fire"
        case .passhoBerry: "water"
        case .wacanBerry: "electric"
        case .rindoBerry: "grass"
        case .yacheBerry: "ice"
        case .chopleBerry: "fighting"
        case .kebiaBerry: "poison"
        case .shucaBerry: "ground"
        case .cobaBerry: "flying"
        case .payapaBerry: "psychic"
        case .tangaBerry: "bug"
        case .chartiBerry: "rock"
        case .kasibBerry: "ghost"
        case .habanBerry: "dragon"
        case .colburBerry: "dark"
        case .babiriBerry: "steel"
        case .chilanBerry: "normal"
        case .roseliBerry: "fairy"
        default: nil
        }
    }

    /// The type a plate boosts and turns Arceus into.
    var plateType: String? {
        switch self {
        case .flamePlate: "fire"
        case .splashPlate: "water"
        case .zapPlate: "electric"
        case .meadowPlate: "grass"
        case .iciclePlate: "ice"
        case .fistPlate: "fighting"
        case .toxicPlate: "poison"
        case .earthPlate: "ground"
        case .skyPlate: "flying"
        case .mindPlate: "psychic"
        case .insectPlate: "bug"
        case .stonePlate: "rock"
        case .spookyPlate: "ghost"
        case .dracoPlate: "dragon"
        case .dreadPlate: "dark"
        case .ironPlate: "steel"
        case .pixiePlate: "fairy"
        default: nil
        }
    }

    var championHolderSpeciesID: Int? {
        switch self {
        case .redOrb: 383
        case .blueOrb: 382
        case .adamantCrystal: 483
        case .lustrousGlobe: 484
        case .griseousCore: 487
        default: nil
        }
    }
}
