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
        self.types = types
        baseStats = Dictionary(uniqueKeysWithValues: zip(PokemonStatCalculator.order, stats))
        abilities = [PokemonAbilityOption(name: ability, slot: 1, isHidden: false)]
    }

    static let byPokemonID: [Int: FormBattleData] = [
        10019: .init(["flying"], [79, 100, 80, 110, 90, 121], ability: "regenerator"),
        10020: .init(["electric", "flying"], [79, 105, 70, 145, 80, 101], ability: "volt-absorb"),
        10021: .init(["ground", "flying"], [89, 145, 90, 105, 80, 91], ability: "intimidate"),
        10249: .init(["fairy", "flying"], [74, 115, 110, 135, 100, 46], ability: "overcoat"),
        10022: .init(["dragon", "ice"], [125, 170, 100, 120, 90, 95], ability: "teravolt"),
        10023: .init(["dragon", "ice"], [125, 120, 90, 170, 100, 95], ability: "turboblaze"),
        10191: .init(["fighting", "water"], [100, 130, 100, 63, 60, 97], ability: "unseen-fist"),
        10193: .init(["psychic", "ice"], [100, 165, 150, 85, 130, 50], ability: "as-one-glastrier"),
        10194: .init(["psychic", "ghost"], [100, 85, 80, 165, 100, 150], ability: "as-one-spectrier"),
    ]

    static func of(speciesID: Int, form: PokemonForm?) -> FormBattleData? {
        let resolved = PokemonForm.resolved(speciesID: speciesID, form: form)
        guard let pokemonID = PokemonForm.entries(speciesID: speciesID).first(where: { $0.form == resolved })?.pokemonID
        else { return nil }
        return byPokemonID[pokemonID]
    }

    /// The ability this individual has in its current form: the form's option with the same slot, else its first.
    static func abilityName(speciesID: Int, form: PokemonForm?, profile: PokemonProfile) -> String? {
        guard let data = of(speciesID: speciesID, form: form) else { return profile.abilityName }
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
