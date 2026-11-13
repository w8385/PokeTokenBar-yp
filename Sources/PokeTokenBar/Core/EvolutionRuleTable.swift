import Foundation

extension EvolutionRules {
    /// Trade steps wait for the trade commit; `EvolutionRulesTests` accepts these prefixes until then.
    static let deferredSignaturePrefixes = ["trade"]

    static let table: [EvolutionRule] = friendship + gestures + moves + items + battles + others

    private static func make(
        _ species: Int, _ covers: [String], _ original: [EvolutionOriginal],
        _ paths: [[EvolutionRequirement]] = [], selector: EvolutionSelector? = nil, formNotShown: Bool = false
    ) -> EvolutionRule {
        EvolutionRule(species: species, covers: Set(covers), original: original, paths: paths,
                      selector: selector, formNotShown: formNotShown)
    }

    private static let happy = "level-up+min_happiness"
    private static let happyTime = "level-up+min_happiness+time_of_day"
    private static let move = "level-up+known_move"
    private static let stretch: [EvolutionRequirement] = [.longStage(percent: 200)]

    private static func pets(_ species: Int, happiness: Int = 160) -> EvolutionRule {
        make(species, [happy], [.happiness(happiness)], [[.pets(happiness == 160 ? 30 : 40)]])
    }

    private static func petsAt(_ species: Int, _ period: DayPeriod, happiness: Int = 160) -> EvolutionRule {
        make(species, [happyTime], [.happiness(happiness), .time(period)],
             [[.pets(happiness == 160 ? 30 : 40), .time(period)]])
    }

    private static func knows(_ species: Int, _ name: String, level: Int = 25) -> EvolutionRule {
        make(species, [move], [.knownMove(name)], [[.knownMove(name, fallbackLevel: level)]])
    }

    private static func holds(_ species: Int, _ item: ItemKind, _ slug: String, _ period: DayPeriod) -> EvolutionRule {
        make(species, ["level-up+held_item+time_of_day"], [.heldItem(slug), .time(period)],
             [[.holds(item), .time(period)]])
    }

    private static func uses(_ species: Int, _ item: ItemKind, _ slug: String, covers: String? = nil) -> EvolutionRule {
        make(species, [covers ?? "use-item:\(slug)"], [.useItem(slug)], [[.bag(item)]])
    }

    private static let friendship: [EvolutionRule] = [
        pets(25, happiness: 220), pets(35), pets(39), pets(143), pets(169), pets(176), pets(183), pets(242),
        pets(428), pets(528), pets(542, happiness: 220), pets(773),
        petsAt(196, .day), petsAt(197, .night), petsAt(315, .day), petsAt(358, .night, happiness: 220),
        petsAt(448, .day), petsAt(873, .night),
        make(350, ["level-up+min_beauty"], [.beauty(170)], [[.pets(60)]]),
        make(700, ["level-up+known_move_type+min_affection", "level-up+known_move_type+min_happiness"],
             [.knownMoveType("fairy"), .happiness(160)], [[.pets(30), .knownFairyMove(fallbackLevel: 15)]]),
        make(923, ["level-up+min_steps"], [.steps(1000)], [[.pets(50)]]),
        make(947, ["level-up+min_steps"], [.steps(1000)], [[.pets(50)]]),
        make(954, ["level-up+min_steps"], [.steps(1000)], [[.pets(50)]]),
    ]

    private static let gestures: [EvolutionRule] = [
        make(687, ["level-up+turn_upside_down"], [.upsideDown], [[.flipped]]),
        make(706, ["level-up+needs_overworld_rain"], [.rain], [[.tokenRain], stretch]),
        make(869, ["spin+condition_expression+held_item+time_of_day"], [.heldItem("strawberry-sweet"), .spinWithSweet],
             [[.holds(.strawberrySweet), .spun]], formNotShown: true),
        make(226, ["level-up+party_species"], [.partySpecies(223)], [[.friendLine(223)]]),
        make(675, ["level-up+party_type"], [.partyType("dark")], [[.friendType("dark")]]),
        make(964, ["level-up+needs_multiplayer"], [.multiplayer], [[.anyFriend]]),
    ]

    private static let moves: [EvolutionRule] = [
        knows(122, "mimic"), knows(185, "mimic"), knows(424, "double-hit"), knows(463, "rollout"),
        knows(465, "ancient-power"), knows(469, "ancient-power"), knows(473, "ancient-power"),
        knows(763, "stomp"), knows(804, "dragon-pulse"), knows(853, "taunt"), knows(981, "twin-beam"),
        knows(1019, "dragon-cheer"),
        make(982, ["level-up+condition_expression+known_move"], [.knownMove("hyper-drill"), .random],
             [[.knownMove("hyper-drill", fallbackLevel: 32)]], formNotShown: true),
    ]

    private static let items: [EvolutionRule] = [
        holds(113, .ovalStone, "oval-stone", .day), holds(461, .razorClaw, "razor-claw", .night),
        holds(472, .razorFang, "razor-fang", .night), holds(903, .razorClaw, "razor-claw", .day),
        uses(841, .tartApple, "tart-apple"), uses(842, .sweetApple, "sweet-apple"),
        uses(1011, .syrupyApple, "syrupy-apple"), uses(900, .blackAugurite, "black-augurite"),
        uses(936, .auspiciousArmor, "auspicious-armor"), uses(937, .maliciousArmor, "malicious-armor"),
        uses(1018, .metalAlloy, "metal-alloy"), uses(199, .galaricaWreath, "galarica-wreath"),
        make(855, ["use-item:cracked-pot", "use-item:chipped-pot"], [.useItem("cracked-pot"), .useItem("chipped-pot")],
             [[.bag(.crackedPot)], [.bag(.chippedPot)]]),
        make(1013, ["use-item:unremarkable-teacup", "use-item:masterpiece-teacup"],
             [.useItem("unremarkable-teacup"), .useItem("masterpiece-teacup")],
             [[.bag(.unremarkableTeacup)], [.bag(.masterpieceTeacup)]]),
        make(901, ["use-item:peat-block+time_of_day"], [.useItem("peat-block"), .fullMoon],
             [[.bag(.peatBlock), .time(.night)]]),
        make(892, ["tower-of-darkness", "tower-of-waters", "use-item:scroll-of-darkness", "use-item:scroll-of-waters"],
             [.tower, .useItem("scroll-of-darkness"), .useItem("scroll-of-waters")],
             [[.towerChosen], [.bag(.scrollOfDarkness)], [.bag(.scrollOfWaters)]], formNotShown: true),
        make(809, ["meltan-candies"], [.candies(400)], [[.candies(5)]]),
        make(1000, ["gimmighoul-coins"], [.coins(999)], [[.spent(1_000_000_000)]]),
    ]

    private static let battles: [EvolutionRule] = [
        make(865, ["three-critical-hits"], [.criticalHits(3)], [[.battles(.won, 3)], stretch]),
        make(867, ["take-damage+location+min_damage_taken"], [.damageTaken(49)], [[.battles(.lost, 1)], stretch]),
        make(902, ["recoil-damage+min_damage_taken"], [.recoil(294)], [[.battles(.lost, 5)], stretch]),
        make(983, ["three-defeated-bisharp"], [.defeatedBisharp(3)], [[.battles(.won, 5)], stretch]),
        make(899, ["agile-style-move+min_move_count+used_move"], [.moveUses("psyshield-bash", 20)],
             [[.battles(.played, 20)], stretch]),
        make(979, ["use-move+min_move_count+used_move"], [.moveUses("rage-fist", 20)],
             [[.battles(.played, 20)], stretch]),
        make(904, ["level-up+known_move", "strong-style-move+min_move_count+used_move",
                   "use-move+min_move_count+used_move"],
             [.knownMove("barb-barrage"), .moveUses("barb-barrage", 20)],
             [[.knownMove("barb-barrage", fallbackLevel: 25)], [.battles(.played, 20)], stretch]),
    ]

    private static let others: [EvolutionRule] = [
        make(106, ["level-up+relative_physical_stats"], [.relativeStats(1)], selector: .attackAbove),
        make(107, ["level-up+relative_physical_stats"], [.relativeStats(-1)], selector: .defenseAbove),
        make(237, ["level-up+relative_physical_stats"], [.relativeStats(0)], selector: .attackEqualsDefense),
        make(266, ["level-up+condition_expression"], [.random], selector: .seedEven),
        make(268, ["level-up+condition_expression"], [.random], selector: .seedOdd),
        make(292, ["shed"], [.shed], selector: .never),
        make(849, ["level-up+allowed_natures"], [.nature], formNotShown: true),
        make(925, ["in-battle-level-up+condition_expression"], [.random], formNotShown: true),
    ]
}
