import XCTest
@testable import PokeTokenBar

/// Real PokéAPI abilities of the species the training tests use (default form).
enum TrainingAbilities {
    static let byID: [Int: [PokemonAbilityOption]] = [
        25: [.init(name: "static", slot: 1, isHidden: false), .init(name: "lightning-rod", slot: 3, isHidden: true)],
        95: [.init(name: "rock-head", slot: 1, isHidden: false), .init(name: "sturdy", slot: 2, isHidden: false),
             .init(name: "weak-armor", slot: 3, isHidden: true)],
        641: [.init(name: "prankster", slot: 1, isHidden: false), .init(name: "defiant", slot: 3, isHidden: true)],
        642: [.init(name: "prankster", slot: 1, isHidden: false), .init(name: "defiant", slot: 3, isHidden: true)],
        645: [.init(name: "sand-force", slot: 1, isHidden: false), .init(name: "sheer-force", slot: 3, isHidden: true)],
        646: [.init(name: "pressure", slot: 1, isHidden: false)],
        898: [.init(name: "unnerve", slot: 1, isHidden: false)],
        905: [.init(name: "cute-charm", slot: 1, isHidden: false), .init(name: "contrary", slot: 3, isHidden: true)],
    ]
}

struct TrainingItemProvider: PokeProviding, PokemonDetailProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        try SpeciesFacts.details(speciesID, abilities: TrainingAbilities.byID[speciesID] ?? [])
    }
}

/// A save with an active Pikachu and graduates in the Box, written to a temp file. Never the user's save.
@MainActor
struct TrainingFixture {
    static let now = Date(timeIntervalSince1970: 1_700_000_000)
    let url: URL
    let defaults: UserDefaults

    init(_ test: XCTestCase) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("training-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("companion-state.json")
        let suite = "training-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.set(1.0, forKey: "growthDifficulty")
        defaults.set(1.0, forKey: "shopDifficulty")
        test.addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
    }

    static func profile(_ instanceID: String, slot: Int = 1, hidden: Bool = false, ability: String? = nil,
                        level: Int = 50) -> PokemonProfile {
        var profile = PokemonProfile.generate(seed: 42, instanceID: instanceID)
        profile.ivs = PokemonIVs(hp: 10, attack: 20, defense: 31, specialAttack: 5, specialDefense: 0, speed: 15)
        profile.abilitySlot = slot
        profile.abilityIsHidden = hidden
        profile.abilityName = ability
        profile.level = level
        return profile
    }

    static func graduate(_ id: String, speciesID: Int, nature: PokemonNature = .lonely, form: PokemonForm? = nil,
                         profile: PokemonProfile? = nil) -> DexEntry {
        DexEntry(id: id, baseID: speciesID, finalID: speciesID, chainOrder: [speciesID], rarity: .common,
                 caughtAt: now, isShiny: false, nature: nature, profile: profile ?? Self.profile("iv-\(id)"),
                 names: [speciesID: ["en": SpeciesFacts.byID[speciesID]?.en ?? "", "ko": SpeciesFacts.byID[speciesID]?.ko ?? ""]],
                 form: form)
    }

    static let activeID = "active-pikachu"

    static func state(dex: [DexEntry] = [], inventory: [String: Int] = [:], tokens: Int = 1_000_000_000,
                      nature: PokemonNature = .adamant, language: AppLanguage = .en) -> CompanionState {
        var state = CompanionState()
        state.language = language
        state.installBaselineSet = true
        state.usedSinceInstall = tokens
        state.lastDate = "d"
        state.active = MonState(baseID: 25, pathIDs: [25], stageIndex: 0, usedAtStage: 0, rarity: .common,
                                totalForms: 1, isShiny: false, nature: nature, profile: profile(activeID))
        state.dex = dex
        state.inventory = inventory
        return state
    }

    func store(_ state: CompanionState, loadDetailsFor species: [Int] = []) async throws -> CompanionStore {
        try JSONEncoder().encode(state).write(to: url)
        let store = reload()
        for id in species { await store.loadPokemonDetails(speciesID: id) }
        return store
    }

    func reload() -> CompanionStore {
        CompanionStore(provider: TrainingItemProvider(), clock: { Self.now }, fileURL: url, rng: SeededRNG(seed: 7),
                       dittoDisguiseRollingEnabled: false, defaults: defaults)
    }
}
