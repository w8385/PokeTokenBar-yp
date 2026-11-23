import Foundation

/// The order of every item list: the plain tabs in `ItemCategory` order, then the `BattleItemGroup` sections.
extension ItemKind {
    static let listOrder: [ItemKind] = training + evolution + attack + typeBoost + bulk + speed + status + weather
        + signature + other

    static let listRank: [ItemKind: Int] = Dictionary(listOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: min)

    var listRank: Int { ItemKind.listRank[self] ?? ItemKind.listOrder.count }

    private static let training: [ItemKind] = [
        .rareCandy, .expShare, .mint, .mirrorHerb, .abilityCapsule, .abilityPatch, .bottleCap, .goldBottleCap,
        .shinyCharm, .revealGlass, .dnaSplicers, .reinsOfUnity,
    ]

    /// Stones in the games' order, the other used-up items and the held ones by the Pokédex number they evolve.
    private static let evolution: [ItemKind] = [
        .fireStone, .waterStone, .thunderStone, .leafStone, .moonStone, .sunStone, .shinyStone, .duskStone, .dawnStone,
        .iceStone,
        .galaricaCuff, .galaricaWreath, .blackAugurite, .peatBlock, .tartApple, .sweetApple, .syrupyApple,
        .crackedPot, .chippedPot, .metalAlloy, .scrollOfDarkness, .scrollOfWaters, .auspiciousArmor, .maliciousArmor,
        .unremarkableTeacup, .masterpieceTeacup,
        .linkingCord,
        .ovalStone, .strawberrySweet,
        .protector, .dragonScale, .electirizer, .magmarizer, .upGrade, .dubiousDisc, .prismScale, .reaperCloth,
        .sachet, .whippedDream,
    ]

    private static let attack: [ItemKind] = [
        .choiceBand, .choiceSpecs, .lifeOrb, .expertBelt, .muscleBand, .wiseGlasses, .punchingGlove,
        .kingsRock, .razorFang, .loadedDice, .metronome, .zoomLens, .gripClaw, .bindingBand, .powerHerb, .throatSpray,
        .boosterEnergy,
        .liechiBerry, .petayaBerry, .lansatBerry, .starfBerry, .micleBerry,
    ]

    /// Each family in type-chart order.
    private static let typeBoost: [ItemKind] = [
        .silkScarf, .charcoal, .mysticWater, .magnet, .miracleSeed, .neverMeltIce, .blackBelt, .poisonBarb, .softSand,
        .sharpBeak, .twistedSpoon, .silverPowder, .hardStone, .spellTag, .dragonFang, .blackGlasses, .metalCoat,
        .fairyFeather,
    ] + plates + gems + [.seaIncense, .waveIncense, .roseIncense, .oddIncense, .rockIncense]

    private static let bulk: [ItemKind] = [
        .assaultVest, .eviolite, .leftovers, .blackSludge, .shellBell, .bigRoot, .focusSash, .focusBand, .airBalloon,
        .sitrusBerry, .oranBerry, .enigmaBerry,
    ] + flavorBerries + [
        .ganlonBerry, .apicotBerry, .keeBerry, .marangaBerry, .jabocaBerry, .rowapBerry,
        .chilanBerry, .occaBerry, .passhoBerry, .wacanBerry, .rindoBerry, .yacheBerry, .chopleBerry, .kebiaBerry,
        .shucaBerry, .cobaBerry, .payapaBerry, .tangaBerry, .chartiBerry, .kasibBerry, .habanBerry, .colburBerry,
        .babiriBerry, .roseliBerry,
    ]

    private static let speed: [ItemKind] = [
        .choiceScarf, .quickClaw, .custapBerry, .salacBerry, .adrenalineOrb,
        .laggingTail, .fullIncense, .ironBall, .roomService,
    ] + powerItems + [
        .scopeLens, .razorClaw, .wideLens, .blunderPolicy, .brightPowder, .laxIncense,
    ]

    private static let status: [ItemKind] = [.lumBerry] + cureBerries + [
        .leppaBerry, .whiteHerb, .mentalHerb, .clearAmulet, .covertCloak, .abilityShield, .protectivePads,
        .safetyGoggles, .heavyDutyBoots, .rockyHelmet, .weaknessPolicy,
    ] + hitStatItems + [.flameOrb, .toxicOrb]

    private static let weather: [ItemKind] = [.heatRock, .dampRock, .smoothRock, .icyRock, .utilityUmbrella]

    /// By the Pokédex number of the species each one belongs to.
    private static let signature: [ItemKind] = [
        .lightBall, .stick, .thickClub, .luckyPunch, .metalPowder, .quickPowder, .deepSeaTooth, .deepSeaScale,
        .soulDew, .blueOrb, .redOrb, .adamantOrb, .adamantCrystal, .lustrousOrb, .lustrousGlobe, .griseousOrb,
        .griseousCore,
    ] + drives + memories + [
        .ultranecroziumZ, .rustedSword, .rustedShield,
        .tealMask, .wellspringMask, .hearthflameMask, .cornerstoneMask, .stellarCrystal,
    ]

    private static let other: [ItemKind] = [
        .everstone, .lightClay, .terrainExtender,
    ] + terrainSeeds + [.floatStone, .stickyBarb, .ringTarget]
}
