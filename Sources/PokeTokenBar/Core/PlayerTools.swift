import Foundation

enum AbilityCapsule {
    static let price = PokemonBalance.Price.abilityCapsule
}

enum AbilityPatch {
    static let price = PokemonBalance.Price.abilityPatch
}

enum BottleCap {
    static let price = PokemonBalance.Price.bottleCap
    static let goldPrice = PokemonBalance.Price.goldBottleCap
    static let maxIV = 31
}

enum MirrorHerb {
    static let price = PokemonBalance.Price.mirrorHerb
}

/// Which species get attacking egg moves from a Mirror Herb, parsed from the generated `EggMoveTable`.
enum EggMoves {
    static let speciesWithAttacking: Set<Int> = Set(
        EggMoveTable.speciesWithAttackingEggMoves.split(whereSeparator: { $0 == "," || $0.isNewline }).compactMap { Int($0) })

    static func hasAttacking(speciesID: Int) -> Bool { speciesWithAttacking.contains(speciesID) }
}

/// Key items that switch a species between its forms, the way an NPC team fields them.
enum FormTool {
    static let price = PokemonBalance.Price.formTool

    static func species(of kind: ItemKind) -> Set<Int>? {
        switch kind {
        case .revealGlass: [641, 642, 645, 905]
        case .dnaSplicers: [646]
        case .reinsOfUnity: [898]
        default: nil
        }
    }

    static func tool(forSpecies speciesID: Int) -> ItemKind? {
        ItemKind.allCases.first { species(of: $0)?.contains(speciesID) == true }
    }
}

extension ItemKind {
    /// Used on one picked Pokémon from its Box page.
    var isTrainingItem: Bool { self == .mint || trainingSlug != nil }

    /// PokéAPI item name, used for both the sprite and the lore.
    var trainingSlug: String? {
        switch self {
        case .abilityCapsule: "ability-capsule"
        case .abilityPatch: "ability-patch"
        case .bottleCap: "bottle-cap"
        case .goldBottleCap: "gold-bottle-cap"
        case .revealGlass: "reveal-glass"
        case .dnaSplicers: "dna-splicers"
        case .reinsOfUnity: "reins-of-unity"
        case .mirrorHerb: "mirror-herb"
        default: nil
        }
    }
}

/// Battle data of the forms that are separate PokéAPI varieties, keyed by that variety's `pokemon_id`.
/// The species details only describe the default form.
struct FormBattleData: Sendable, Equatable {
    let types: [String]
    let baseStats: [String: Int]
    let abilities: [PokemonAbilityOption]

    private init(_ types: [String], _ stats: [Int], ability: String) {
        self.init(types, stats, abilities: [ability])
    }

    private init(_ types: [String], _ stats: [Int], ability: String, hidden: String) {
        self.types = types
        baseStats = Dictionary(uniqueKeysWithValues: zip(PokemonStatCalculator.order, stats))
        abilities = [PokemonAbilityOption(name: ability, slot: 1, isHidden: false),
                     PokemonAbilityOption(name: hidden, slot: 3, isHidden: true)]
    }

    /// `abilities` in PokéAPI slot order; with three, the third is the hidden one.
    private init(_ types: [String], _ stats: [Int], abilities: [String]) {
        self.types = types
        baseStats = Dictionary(uniqueKeysWithValues: zip(PokemonStatCalculator.order, stats))
        self.abilities = abilities.enumerated().map { index, name in
            PokemonAbilityOption(name: name, slot: index + 1, isHidden: abilities.count == 3 && index == 2)
        }
    }

    static let byPokemonID: [Int: FormBattleData] = [
        10001: .init(["psychic"], [50, 180, 20, 180, 20, 150], ability: "pressure"),
        10002: .init(["psychic"], [50, 70, 160, 70, 160, 90], ability: "pressure"),
        10003: .init(["psychic"], [50, 95, 90, 95, 90, 180], ability: "pressure"),
        10004: .init(["bug", "ground"], [60, 79, 105, 59, 85, 36], ability: "anticipation", hidden: "overcoat"),
        10005: .init(["bug", "steel"], [60, 69, 95, 69, 95, 36], ability: "anticipation", hidden: "overcoat"),
        10006: .init(["grass", "flying"], [100, 103, 75, 120, 75, 127], ability: "serene-grace"),
        10007: .init(["ghost", "dragon"], [150, 120, 100, 120, 100, 90], ability: "levitate"),
        10008: .init(["electric", "fire"], [50, 65, 107, 105, 107, 86], ability: "levitate"),
        10009: .init(["electric", "water"], [50, 65, 107, 105, 107, 86], ability: "levitate"),
        10010: .init(["electric", "ice"], [50, 65, 107, 105, 107, 86], ability: "levitate"),
        10011: .init(["electric", "flying"], [50, 65, 107, 105, 107, 86], ability: "levitate"),
        10012: .init(["electric", "grass"], [50, 65, 107, 105, 107, 86], ability: "levitate"),
        10013: .init(["fire"], [70, 70, 70, 70, 70, 70], ability: "forecast"),
        10014: .init(["water"], [70, 70, 70, 70, 70, 70], ability: "forecast"),
        10015: .init(["ice"], [70, 70, 70, 70, 70, 70], ability: "forecast"),
        10016: .init(["water"], [70, 92, 65, 80, 55, 98], abilities: ["rock-head", "adaptability", "mold-breaker"]),
        10017: .init(["fire", "psychic"], [105, 30, 105, 140, 105, 55], ability: "sheer-force", hidden: "zen-mode"),
        10018: .init(["normal", "fighting"], [100, 128, 90, 77, 77, 128], ability: "serene-grace"),
        10024: .init(["water", "fighting"], [91, 72, 90, 129, 90, 108], ability: "justified"),
        10019: .init(["flying"], [79, 100, 80, 110, 90, 121], ability: "regenerator"),
        10020: .init(["electric", "flying"], [79, 105, 70, 145, 80, 101], ability: "volt-absorb"),
        10021: .init(["ground", "flying"], [89, 145, 90, 105, 80, 91], ability: "intimidate"),
        10249: .init(["fairy", "flying"], [74, 115, 110, 135, 100, 46], ability: "overcoat"),
        10022: .init(["dragon", "ice"], [125, 170, 100, 120, 90, 95], ability: "teravolt"),
        10023: .init(["dragon", "ice"], [125, 120, 90, 170, 100, 95], ability: "turboblaze"),
        10191: .init(["fighting", "water"], [100, 130, 100, 63, 60, 97], ability: "unseen-fist"),
        10193: .init(["psychic", "ice"], [100, 165, 150, 85, 130, 50], ability: "as-one-glastrier"),
        10194: .init(["psychic", "ghost"], [100, 85, 80, 165, 100, 150], ability: "as-one-spectrier"),
        10025: .init(["psychic"], [74, 48, 76, 83, 81, 104], abilities: ["keen-eye", "infiltrator", "competitive"]),
        10186: .init(["psychic", "normal"], [70, 55, 65, 95, 105, 85],
                     abilities: ["own-tempo", "synchronize", "psychic-surge"]),
        10248: .init(["water", "ghost"], [120, 92, 65, 100, 75, 78],
                     abilities: ["swift-swim", "adaptability", "mold-breaker"]),
        10254: .init(["normal"], [115, 90, 70, 59, 90, 65], abilities: ["aroma-veil", "gluttony", "thick-fat"]),
    ]

    static func of(speciesID: Int, form: PokemonForm?, gender: PokemonGender?) -> FormBattleData? {
        PokemonForm.varietyID(speciesID: speciesID, form: form, gender: gender).flatMap { byPokemonID[$0] }
    }

    /// The ability this individual has in its current form: the form's option with the same slot, else its first.
    static func abilityName(speciesID: Int, form: PokemonForm?, profile: PokemonProfile) -> String? {
        guard let data = of(speciesID: speciesID, form: form, gender: profile.gender) else { return profile.abilityName }
        let option = data.abilities.first { $0.slot == profile.abilitySlot && $0.isHidden == profile.abilityIsHidden }
            ?? data.abilities.first
        return option?.name
    }
}

extension PokemonDetails {
    /// These details with the types, base stats and abilities of a form that is its own variety.
    func applying(_ form: FormBattleData?) -> PokemonDetails {
        guard let form else { return self }
        return PokemonDetails(speciesID: speciesID, name: name, height: height, weight: weight,
                              baseExperience: baseExperience, genderRate: genderRate, types: form.types,
                              baseStats: form.baseStats, abilities: form.abilities, moves: moves)
    }
}

/// The classic nature chart: rows raise a stat, columns lower one, and the diagonal changes nothing.
enum NatureGrid {
    static let stats = ["attack", "defense", "special-attack", "special-defense", "speed"]

    static let rows: [[PokemonNature]] = stats.map { up in
        stats.map { down in
            PokemonNature.allCases.first { nature in
                up == down ? isNeutral(nature) && neutralIndex(nature) == stats.firstIndex(of: up)
                           : nature.modifier(for: up) > 1 && nature.modifier(for: down) < 1
            }!
        }
    }

    private static func isNeutral(_ nature: PokemonNature) -> Bool {
        stats.allSatisfy { nature.modifier(for: $0) == 1 }
    }

    private static let neutralOrder: [PokemonNature] = [.hardy, .docile, .bashful, .quirky, .serious]
    private static func neutralIndex(_ nature: PokemonNature) -> Int? { neutralOrder.firstIndex(of: nature) }

    /// The raised and lowered stat, or nil for a neutral nature.
    static func change(of nature: PokemonNature) -> (up: String, down: String)? {
        guard let up = stats.first(where: { nature.modifier(for: $0) > 1 }),
              let down = stats.first(where: { nature.modifier(for: $0) < 1 }) else { return nil }
        return (up, down)
    }
}
