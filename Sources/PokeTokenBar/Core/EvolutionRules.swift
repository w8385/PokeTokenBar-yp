import Foundation

/// What the games ask for, as the dex card names it. Text lives in `LocalizationEvolution.swift`.
enum EvolutionOriginal: Equatable, Sendable {
    case happiness(Int)
    case affection(Int)
    case time(DayPeriod)
    case fullMoon
    case knownMove(String)
    case knownMoveType(String)
    case heldItem(String)
    case partySpecies(Int)
    case partyType(String)
    case relativeStats(Int)
    case beauty(Int)
    case upsideDown
    case rain
    case steps(Int)
    case multiplayer
    case criticalHits(Int)
    case damageTaken(Int)
    case recoil(Int)
    case moveUses(String, Int)
    case defeatedBisharp(Int)
    case coins(Int)
    case candies(Int)
    case tower
    case spinWithSweet
    case random
    case nature
    case shed
    case useItem(String)
}

/// A condition the app can check. All requirements of one path must hold; any one path opens the step.
enum EvolutionRequirement: Equatable, Sendable {
    enum Tally: String, Codable, Sendable { case won, lost, played }

    case pets(Int)
    case time(DayPeriod)
    case knownMove(String, fallbackLevel: Int)
    case knownFairyMove(fallbackLevel: Int)
    case holds(ItemKind)
    case bag(ItemKind)
    case friendLine(Int)
    case friendType(String)
    case anyFriend
    case flipped
    case spun
    case tokenRain
    case longStage(percent: Int)
    case battles(Tally, Int)
    case towerChosen
    case spent(Int)
    case candies(Int)
}

/// Picks one child of a branching step when the plan is made. Never a gate: the branch is settled once.
enum EvolutionSelector: Equatable, Sendable {
    case attackAbove, defenseAbove, attackEqualsDefense
    case seedEven, seedOdd
    case never

    func matches(_ traits: EvolutionTraits?) -> Bool {
        guard let traits else { return self == .seedEven || self == .attackEqualsDefense }
        switch self {
        case .attackAbove: return traits.attack > traits.defense
        case .defenseAbove: return traits.attack < traits.defense
        case .attackEqualsDefense: return traits.attack == traits.defense
        case .seedEven: return traits.seed % 2 == 0
        case .seedOdd: return traits.seed % 2 == 1
        case .never: return false
        }
    }
}

/// The per-individual values a selector reads. Tyrogue's three branches compare Attack with Defense at Lv.20
/// (both base 35), so only the IVs and the nature decide.
struct EvolutionTraits: Equatable, Sendable {
    static let tyrogueBase = 35
    static let tyrogueLevel = 20
    let seed: UInt64
    let attack: Int
    let defense: Int

    init(seed: UInt64, ivs: PokemonIVs?, nature: PokemonNature?) {
        func stat(_ name: String, _ iv: Int) -> Int {
            let neutral = (2 * Self.tyrogueBase + iv) * Self.tyrogueLevel / 100 + 5
            let tenths = Int(((nature?.modifier(for: name) ?? 1) * 10).rounded())
            return neutral * tenths / 10
        }
        self.seed = seed
        attack = stat("attack", ivs?.attack ?? 0)
        defense = stat("defense", ivs?.defense ?? 0)
    }
}

struct EvolutionRule: Sendable {
    let species: Int
    /// The `EvolutionRules.signature` values this rule answers; the invariant test fails on any other.
    let covers: Set<String>
    let original: [EvolutionOriginal]
    /// Any one path opens the step. Empty = no gate (a selector, or a form the app does not draw).
    let paths: [[EvolutionRequirement]]
    var selector: EvolutionSelector?
    var formNotShown = false

    /// Reached only by using an item: left out of the plan while a sibling can be reached by growth.
    var isItemOnly: Bool {
        !paths.isEmpty && paths.allSatisfy { path in path.contains { if case .bag = $0 { return true } else { return false } } }
    }
}

/// Maps the PokéAPI evolution conditions the XP loop cannot read to app-native conditions. Keyed by the evolved
/// species. `EvolutionRulesTests` walks `Fixtures/evolution-steps.json` and fails on a step left out.
enum EvolutionRules {
    static func rule(for species: Int) -> EvolutionRule? { byID[species] }

    /// Steps PokéAPI lists with no condition at all (Manaphy under Phione); they keep growing by XP.
    static let unconditional: Set<Int> = [490]

    static let stones: Set<String> = [
        "fire-stone", "water-stone", "thunder-stone", "leaf-stone", "moon-stone", "sun-stone", "shiny-stone",
        "dusk-stone", "dawn-stone", "ice-stone",
    ]
    private static let noise: Set<String> = [
        "version_group", "is_default", "region", "required_pokemon_form", "evolved_pokemon_form", "gender", "min_level",
    ]

    /// Names one PokéAPI `evolution_details` entry by what it asks for; nil when the XP loop already covers it
    /// (a level, a level at some time of day, a stone).
    static func signature(trigger: String, keys: Set<String>, item: String?) -> String? {
        let rest = keys.subtracting(noise).subtracting(["trigger"])
        switch trigger {
        case "level-up":
            return rest.isSubset(of: ["time_of_day"]) ? nil : "level-up+" + rest.sorted().joined(separator: "+")
        case "use-item":
            let extra = rest.subtracting(["item"])
            if let item, stones.contains(item), extra.isEmpty { return nil }
            return "use-item:\(item ?? "?")" + extra.sorted().map { "+" + $0 }.joined()
        default:
            return trigger + rest.sorted().map { "+" + $0 }.joined()
        }
    }

    /// The children a plan may pick: selectors settle their branch, and item-only children wait for their item.
    static func plannable(_ options: [EvoNode], traits: EvolutionTraits?) -> [EvoNode] {
        let selected = options.filter { rule(for: $0.speciesID)?.selector != nil }
        var pool = options
        if !selected.isEmpty {
            let matching = selected.filter { rule(for: $0.speciesID)?.selector?.matches(traits) == true }
            pool = options.filter { rule(for: $0.speciesID)?.selector == nil } + matching
            if pool.isEmpty { pool = options }
        }
        let free = pool.filter { rule(for: $0.speciesID)?.isItemOnly != true }
        return free.isEmpty ? pool : free
    }

    /// The requirements that open the step into `species` right now; empty when it has no rule, nil while closed.
    static func openPath(into species: Int, in context: EvolutionContext) -> [EvolutionRequirement]? {
        guard let rule = rule(for: species) else { return [] }
        return rule.openPath(in: context)
    }

    /// The children growth can reach; an item-only child is reached by using its item on the current form.
    static func growthChildren(_ options: [EvoNode]) -> [EvoNode] {
        options.filter { rule(for: $0.speciesID)?.isItemOnly != true }
    }

    /// At the moment of evolving, a branch chosen by a selector follows the traits as they are now (a mint
    /// changes the nature after the plan was made).
    static func resolvingSelector(_ planned: EvoNode, among siblings: [EvoNode], traits: EvolutionTraits?) -> EvoNode {
        guard let selector = rule(for: planned.speciesID)?.selector, !selector.matches(traits) else { return planned }
        return siblings.first { rule(for: $0.speciesID)?.selector?.matches(traits) == true } ?? planned
    }

    private static let byID: [Int: EvolutionRule] = Dictionary(table.map { ($0.species, $0) }, uniquingKeysWith: { a, _ in a })

    static var all: [EvolutionRule] { table.sorted { $0.species < $1.species } }
}
