import Foundation

/// Battle items NPC teams hold: Primal orbs, Ultranecrozium Z, Origin items, the rusted weapons, Punching Glove,
/// resist berries and plates.
extension ItemKind {
    static let primalOrbs: [ItemKind] = [.redOrb, .blueOrb]
    /// Signature items that transform their holder in battle and take the one Mega slot.
    static let megaSlotItems: [ItemKind] = primalOrbs + [.ultranecroziumZ]
    static let originItems: [ItemKind] = [.adamantCrystal, .lustrousGlobe, .griseousCore]
    static let crownedItems: [ItemKind] = [.rustedSword, .rustedShield]
    static let resistBerries: [ItemKind] = [
        .occaBerry, .passhoBerry, .wacanBerry, .rindoBerry, .yacheBerry, .chopleBerry, .kebiaBerry, .shucaBerry, .cobaBerry,
        .payapaBerry, .tangaBerry, .chartiBerry, .kasibBerry, .habanBerry, .colburBerry, .babiriBerry, .chilanBerry, .roseliBerry,
    ]
    static let plates: [ItemKind] = [
        .flamePlate, .splashPlate, .zapPlate, .meadowPlate, .iciclePlate, .fistPlate, .toxicPlate, .earthPlate, .skyPlate,
        .mindPlate, .insectPlate, .stonePlate, .spookyPlate, .dracoPlate, .dreadPlate, .ironPlate, .pixiePlate,
    ]
    static let championBattleItems: [ItemKind] = megaSlotItems + originItems + crownedItems + [.punchingGlove]
        + resistBerries + plates

    /// The PokéAPI slug the bot knows; nil for every item outside `championBattleItems` and `moreBattleItems`.
    var championItemSlug: String? {
        switch self {
        case .rustedSword: "rusted-sword"
        case .rustedShield: "rusted-shield"
        case .ultranecroziumZ: "ultranecrozium-z"
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
        default: moreItemSlug
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
        case .rustedSword: 888
        case .rustedShield: 889
        case .ultranecroziumZ: 800
        default: moreHolderSpeciesID
        }
    }
}

/// The rest of the battle items the bot runs, sold in the held-item tab.
extension ItemKind {
    static let gems: [ItemKind] = [
        .normalGem, .fireGem, .waterGem, .electricGem, .grassGem, .iceGem, .fightingGem, .poisonGem, .groundGem,
        .flyingGem, .psychicGem, .bugGem, .rockGem, .ghostGem, .dragonGem, .darkGem, .steelGem, .fairyGem,
    ]
    static let typeIncenses: [ItemKind] = [.seaIncense, .waveIncense, .rockIncense, .roseIncense, .oddIncense]
    static let memories: [ItemKind] = [
        .fireMemory, .waterMemory, .electricMemory, .grassMemory, .iceMemory, .fightingMemory, .poisonMemory,
        .groundMemory, .flyingMemory, .psychicMemory, .bugMemory, .rockMemory, .ghostMemory, .dragonMemory,
        .darkMemory, .steelMemory, .fairyMemory,
    ]
    static let drives: [ItemKind] = [.douseDrive, .shockDrive, .burnDrive, .chillDrive]
    static let cureBerries: [ItemKind] = [.cheriBerry, .chestoBerry, .pechaBerry, .rawstBerry, .aspearBerry, .persimBerry]
    static let flavorBerries: [ItemKind] = [.figyBerry, .wikiBerry, .magoBerry, .aguavBerry, .iapapaBerry]
    static let pinchStatBerries: [ItemKind] = [.liechiBerry, .ganlonBerry, .salacBerry, .petayaBerry, .apicotBerry]
    static let terrainSeeds: [ItemKind] = [.electricSeed, .grassySeed, .mistySeed, .psychicSeed]
    static let powerItems: [ItemKind] = [
        .machoBrace, .powerWeight, .powerBracer, .powerBelt, .powerLens, .powerBand, .powerAnklet,
    ]
    static let hitStatItems: [ItemKind] = [.absorbBulb, .cellBattery, .luminousMoss, .snowball]
    static let speciesItems: [ItemKind] = [
        .lightBall, .thickClub, .metalPowder, .quickPowder, .luckyPunch, .stick, .adamantOrb, .lustrousOrb, .griseousOrb,
        .soulDew,
    ]
    /// Sold at the burden price: they mostly hold their own holder back.
    static let burdens: [ItemKind] = powerItems + [.ironBall, .laggingTail, .fullIncense, .stickyBarb, .ringTarget]

    static let moreBattleItems: [ItemKind] = [
        .loadedDice, .metronome, .zoomLens, .gripClaw, .bindingBand, .powerHerb, .throatSpray, .boosterEnergy,
        .liechiBerry, .petayaBerry, .lansatBerry, .starfBerry, .micleBerry,
    ] + gems + typeIncenses + [
        .oranBerry, .enigmaBerry,
    ] + flavorBerries + [
        .ganlonBerry, .apicotBerry, .keeBerry, .marangaBerry, .jabocaBerry, .rowapBerry, .airBalloon,
        .salacBerry, .custapBerry, .blunderPolicy, .adrenalineOrb, .laxIncense, .fullIncense, .laggingTail, .ironBall,
        .roomService,
    ] + powerItems + cureBerries + [
        .leppaBerry, .mentalHerb, .clearAmulet, .covertCloak, .abilityShield, .protectivePads, .safetyGoggles,
        .heavyDutyBoots,
    ] + hitStatItems + [
        .utilityUmbrella,
    ] + drives + memories + speciesItems + terrainSeeds + [
        .lightClay, .terrainExtender, .floatStone, .stickyBarb, .ringTarget,
    ]

    /// The bot slug: the case name in kebab case.
    var moreItemSlug: String? {
        guard ItemKind.moreBattleItems.contains(self) else { return nil }
        return rawValue.reduce(into: "") { slug, character in
            slug += character.isUppercase ? "-\(character.lowercased())" : String(character)
        }
    }

    var moreBattleGroup: BattleItemGroup? {
        guard ItemKind.moreBattleItems.contains(self) else { return nil }
        if gemType != nil || incenseType != nil { return .typeBoost }
        if (ItemKind.drives + ItemKind.memories + ItemKind.speciesItems).contains(self) { return .signature }
        if ItemKind.powerItems.contains(self) { return .speed }
        if ItemKind.terrainSeeds.contains(self) { return .other }
        switch self {
        case .loadedDice, .metronome, .zoomLens, .gripClaw, .bindingBand, .powerHerb, .throatSpray, .boosterEnergy,
             .liechiBerry, .petayaBerry, .lansatBerry, .starfBerry, .micleBerry: return .attack
        case .oranBerry, .enigmaBerry, .figyBerry, .wikiBerry, .magoBerry, .aguavBerry, .iapapaBerry, .ganlonBerry,
             .apicotBerry, .keeBerry, .marangaBerry, .jabocaBerry, .rowapBerry, .airBalloon: return .bulk
        case .salacBerry, .custapBerry, .blunderPolicy, .adrenalineOrb, .laxIncense, .fullIncense, .laggingTail,
             .ironBall, .roomService: return .speed
        case .utilityUmbrella: return .weather
        case .lightClay, .terrainExtender, .floatStone, .stickyBarb, .ringTarget: return .other
        default: return .status
        }
    }

    /// The type a gem boosts once.
    var gemType: String? { ItemKind.gems.contains(self) ? String(rawValue.dropLast("Gem".count)) : nil }

    /// The type a memory gives Silvally and its Multi-Attack.
    var memoryType: String? { ItemKind.memories.contains(self) ? String(rawValue.dropLast("Memory".count)) : nil }

    /// The type a drive gives Genesect's Techno Blast.
    var driveType: String? {
        switch self {
        case .douseDrive: "water"
        case .shockDrive: "electric"
        case .burnDrive: "fire"
        case .chillDrive: "ice"
        default: nil
        }
    }

    /// The type whose moves an incense boosts ×1.2.
    var incenseType: String? {
        switch self {
        case .seaIncense, .waveIncense: "water"
        case .rockIncense: "rock"
        case .roseIncense: "grass"
        case .oddIncense: "psychic"
        default: nil
        }
    }

    var moreHolderSpeciesID: Int? {
        if ItemKind.drives.contains(self) { return 649 }
        if ItemKind.memories.contains(self) { return 773 }
        switch self {
        case .lightBall: return 25
        case .metalPowder, .quickPowder: return 132
        case .luckyPunch: return 113
        case .adamantOrb: return 483
        case .lustrousOrb: return 484
        case .griseousOrb: return 487
        default: return nil
        }
    }
}
