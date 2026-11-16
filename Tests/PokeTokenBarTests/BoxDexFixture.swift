import Foundation
@testable import PokeTokenBar

struct BoxDexProvider: PokeProviding, PokemonDetailProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 4, tree: EvoNode(speciesID: 4, children: [
            EvoNode(speciesID: 5, children: [EvoNode(speciesID: 6, children: [])])]),
                rarity: .common,
                names: [4: ["ko": "파이리", "en": "Charmander"], 5: ["ko": "리자드", "en": "Charmeleon"],
                        6: ["ko": "리자몽", "en": "Charizard"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        try SpeciesFacts.details(speciesID)
    }
}

/// A synthetic save with every kind of individual the Box lists: the raised Pokémon holding an item,
/// a shiny holder, a Mega holder that is a friend, an Onix that can take its trade item, and one with nothing.
enum BoxDexFixture {
    static let raisedID = "raised"
    static let pikachuID = "pikachu"
    static let charizardID = "charizard"
    static let onixID = "onix"
    static let eeveeID = "eevee"

    static func state(language: AppLanguage = .ko) -> CompanionState {
        var state = CompanionState()
        state.language = language
        state.installBaselineSet = true
        state.usedSinceInstall = 9_000_000_000
        var raised = PokemonProfile.generate(seed: 5, instanceID: raisedID)
        raised.level = 24
        state.active = MonState(baseID: 4, pathIDs: [4, 5, 6], stageIndex: 1, usedAtStage: 0,
                                rarity: .common, totalForms: 3, profile: raised)
        func entry(_ id: String, species: Int, chain: [Int], level: Int, seed: UInt64, shiny: Bool = false,
                   names: [Int: [String: String]], at offset: Double) -> DexEntry {
            var profile = PokemonProfile.generate(seed: seed, instanceID: id)
            profile.level = level
            return DexEntry(id: id, baseID: chain[0], finalID: species, chainOrder: chain, rarity: .rare,
                            caughtAt: Date(timeIntervalSince1970: 1_700_000_000 + offset), isShiny: shiny,
                            profile: profile, names: names)
        }
        state.dex = [
            entry(pikachuID, species: 25, chain: [25], level: 42, seed: 25, shiny: true,
                  names: [25: ["ko": "피카츄", "en": "Pikachu"]], at: 300),
            entry(charizardID, species: 6, chain: [4, 5, 6], level: 60, seed: 6,
                  names: [4: ["ko": "파이리", "en": "Charmander"], 5: ["ko": "리자드", "en": "Charmeleon"],
                          6: ["ko": "리자몽", "en": "Charizard"]], at: 200),
            entry(onixID, species: 95, chain: [95], level: 41, seed: 95,
                  names: [95: ["ko": "롱스톤", "en": "Onix"]], at: 100),
            entry(eeveeID, species: 133, chain: [133], level: 15, seed: 133,
                  names: [133: ["ko": "이브이", "en": "Eevee"]], at: 400),
        ]
        state.inventory = [ItemKind.metalCoat.rawValue: 1, ItemKind.leftovers.rawValue: 1,
                           ItemKind.lifeOrb.rawValue: 1, "mega-stone:venusaurite": 1]
        state.heldItems = [raisedID: ItemKind.focusSash.rawValue, pikachuID: ItemKind.choiceScarf.rawValue,
                           charizardID: "mega-stone:charizardite-x"]
        state.friendEntryIDs = [charizardID]
        return state
    }

    @MainActor
    static func makeStore(language: AppLanguage = .ko, mutate: (inout CompanionState) -> Void = { _ in },
                          defaults: UserDefaults? = nil) throws -> (CompanionStore, cleanup: () -> Void) {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("box-dex-\(UUID()).json")
        var state = state(language: language)
        mutate(&state)
        try JSONEncoder().encode(state).write(to: file)
        let store = defaults.map { CompanionStore(provider: BoxDexProvider(), fileURL: file, defaults: $0) }
            ?? CompanionStore(provider: BoxDexProvider(), fileURL: file)
        return (store, { try? FileManager.default.removeItem(at: file) })
    }

    static let botReply = """
    {"ok": true, "party_size": 1,
     "recent_battles": [
       {"opponent_name": "Alex", "my_pokemon_id": 25, "opponent_pokemon_id": 6, "result": "win", "turns": 6,
        "at": "2026-11-13T05:20:11+00:00"},
       {"opponent_name": "Sam", "my_pokemon_id": 25, "opponent_pokemon_id": 94, "result": "loss", "turns": 9,
        "at": "2026-11-13T03:02:40+00:00"}],
     "coworkers": [
       {"name": "Alex", "pokemon_id": 6, "level": 55, "shiny": true},
       {"name": "Sam", "pokemon_id": 94, "level": 38, "shiny": false},
       {"name": "Jordan", "pokemon_id": 130, "level": 33, "shiny": false}]}
    """

    /// A bot link that answers every sync with `botReply`; `connected: false` leaves the token and server empty.
    @MainActor
    static func makeUploader(defaults: UserDefaults, scratch: URL, connected: Bool = true) async -> PartyUploader {
        let uploader = PartyUploader(
            tokenStore: PartyTokenStore(fileURL: scratch.appendingPathComponent("token-\(UUID())")),
            defaults: defaults, appVersion: "test",
            exchange: { _ in (Data(botReply.utf8), 200) },
            fetch: { _ in (Data(#"{"moves":[],"default":[]}"#.utf8), 200) },
            partySource: { [PartyMember(pokemonID: 25, level: 42, shiny: false, ivs: nil)] })
        if connected {
            uploader.saveToken("synthetic-token")
            uploader.serverURL = "http://bot-host:8790"
            await uploader.tick()
        }
        return uploader
    }
}
