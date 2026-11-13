import Foundation
import XCTest
@testable import PokeTokenBar

final class BattleEntryTests: XCTestCase {
    private func profile(level: Int, id: String) -> PokemonProfile {
        var profile = PokemonProfile.generate(seed: 7, instanceID: id)
        profile.level = level
        return profile
    }

    private func entry(_ species: Int, id: String, level: Int = 30, released: Bool = false) -> DexEntry {
        var entry = DexEntry(baseID: species, finalID: species, chainOrder: [species], rarity: .common, caughtAt: nil,
                             profile: profile(level: level, id: id),
                             releasedAt: released ? Date(timeIntervalSince1970: 1) : nil)
        entry.id = id
        return entry
    }

    private func state() -> CompanionState {
        var state = CompanionState()
        state.active = MonState(baseID: 4, pathIDs: [4, 5], stageIndex: 1, usedAtStage: 0,
                                rarity: .common, totalForms: 3, profile: profile(level: 42, id: "raised"))
        state.dex = [entry(10, id: "caterpie"), entry(25, id: "pikachu", level: 60), entry(12, id: "gone", released: true)]
        return state
    }

    private func party(_ state: CompanionState, slot: BattleEntrySlot?) -> [PartyMember] {
        BattleEntry.party(state: state, slot: slot, rentalSpeciesID: 4)
    }

    func testCandidatesAreTheRaisedPokemonAndKeptCatches() {
        let candidates = BattleEntry.candidates(in: state())

        XCTAssertEqual(candidates.map(\.id), ["raised", "caterpie", "pikachu"])
        XCTAssertEqual(candidates.map(\.member.pokemonID), [5, 10, 25])
        XCTAssertNil(candidates[0].dexEntry)
    }

    func testCandidatesCarryTheirNature() {
        var state = state()
        state.active?.nature = .adamant
        state.dex[1].nature = .timid

        let candidates = BattleEntry.candidates(in: state)

        XCTAssertEqual(candidates.map(\.member.nature), ["adamant", nil, "timid"])
    }

    func testPartyIsTheChosenPokemonWithItsMoves() {
        let party = self.party(state(),
                                      slot: BattleEntrySlot(instanceID: "pikachu", pokemonID: 25, moves: [85, 98]))

        XCTAssertEqual(party.map(\.pokemonID), [25])
        XCTAssertEqual(party.map(\.level), [60])
        XCTAssertEqual(party[0].moves, [85, 98])
    }

    func testMovesChosenBeforeEvolutionAreDropped() {
        let party = self.party(state(), slot: BattleEntrySlot(instanceID: "raised", pokemonID: 4, moves: [52]))

        XCTAssertEqual(party.map(\.pokemonID), [5])
        XCTAssertNil(party[0].moves)
    }

    func testNoOwnedChoiceSendsThePokemonBeingRaisedWithoutTheStaleMoves() {
        let gone = BattleEntrySlot(instanceID: "gone", pokemonID: 12, moves: [16])

        XCTAssertEqual(party(state(), slot: nil).map(\.pokemonID), [5])
        XCTAssertEqual(party(state(), slot: gone).map(\.pokemonID), [5])
        XCTAssertNil(party(state(), slot: gone)[0].moves)
    }

    func testAnEggWithCatchesAndNothingChosenSendsTheHighestLevelCatch() {
        var egg = state()
        egg.active = nil

        XCTAssertEqual(party(egg, slot: nil).map(\.pokemonID), [25])
        XCTAssertNil(party(egg, slot: nil)[0].rental)
        XCTAssertEqual(party(egg, slot: BattleEntrySlot(instanceID: "caterpie")).map(\.pokemonID), [10])
    }

    func testAnEggOnlySaveSendsTheRentalStarter() throws {
        var egg = CompanionState()
        egg.dex = [entry(12, id: "gone", released: true)]

        XCTAssertNil(BattleEntry.fighter(state: egg, slot: nil))
        XCTAssertEqual(party(egg, slot: nil),
                       [PartyMember(pokemonID: 4, level: BattleEntry.rentalLevel, shiny: false, ivs: nil, rental: true)])
        let json = try PartyPayload(appVersion: nil, party: party(egg, slot: nil)).encoded()
        let sent = try XCTUnwrap((JSONSerialization.jsonObject(with: json) as? [String: Any])?["party"] as? [[String: Any]])
        XCTAssertEqual(sent[0]["rental"] as? Bool, true)
        XCTAssertNil(sent[0]["moves"])
    }

    func testTheRentalGoesAwayOnceAPokemonHatches() throws {
        var hatched = CompanionState()
        hatched.active = state().active

        XCTAssertEqual(party(hatched, slot: nil).map(\.pokemonID), [5])
        XCTAssertNil(party(hatched, slot: nil)[0].rental)
        let json = try PartyPayload(appVersion: nil, party: party(hatched, slot: nil)).encoded()
        XCTAssertFalse(String(decoding: json, as: UTF8.self).contains("rental"))
    }

    func testPayloadSendsMovesOnlyWhenChosen() throws {
        let data = try PartyPayload(appVersion: nil, party: [
            PartyMember(pokemonID: 25, level: 60, shiny: false, ivs: nil, moves: [85]),
            PartyMember(pokemonID: 5, level: 42, shiny: false, ivs: nil),
        ]).encoded()

        let party = try XCTUnwrap((JSONSerialization.jsonObject(with: data) as? [String: Any])?["party"] as? [[String: Any]])
        XCTAssertEqual(party[0]["moves"] as? [Int], [85])
        XCTAssertNil(party[1]["moves"])
    }
}

@MainActor
final class BattleEntryStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "BattleEntry-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testChoosingKeepsOnePokemonAndPersists() {
        let store = BattleEntryStore(defaults: defaults)
        store.choose("a")
        store.choose("b")
        XCTAssertEqual(store.slot, BattleEntrySlot(instanceID: "b"))
        XCTAssertEqual(BattleEntryStore(defaults: defaults).slot, store.slot)

        store.choose(nil)
        XCTAssertNil(BattleEntryStore(defaults: defaults).slot)
    }

    func testTheRentalIsPickedOnceAmongTheStartersAndCanBeSwitched() {
        let store = BattleEntryStore(defaults: defaults)
        XCTAssertTrue(BattleEntry.rentalSpeciesIDs.contains(store.rentalSpeciesID))
        XCTAssertEqual(BattleEntryStore(defaults: defaults).rentalSpeciesID, store.rentalSpeciesID)

        store.chooseRental(7)
        store.chooseRental(25)
        XCTAssertEqual(BattleEntryStore(defaults: defaults).rentalSpeciesID, 7)
    }

    func testAnOlderThreeSlotEntryLoadsItsFirstSlot() throws {
        let saved = [BattleEntrySlot(instanceID: "a", pokemonID: 25, moves: [85]),
                     BattleEntrySlot(instanceID: "b"), BattleEntrySlot(instanceID: "c")]
        defaults.set(try JSONEncoder().encode(saved), forKey: BattleEntryStore.defaultsKey)

        XCTAssertEqual(BattleEntryStore(defaults: defaults).slot, saved[0])
    }

    func testChoosingTheSamePokemonKeepsItsMoves() {
        let store = BattleEntryStore(defaults: defaults)
        store.toggleMove(1, for: "a", pokemonID: 25, current: [1, 2])
        store.choose("a")
        XCTAssertEqual(store.slot, BattleEntrySlot(instanceID: "a", pokemonID: 25, moves: [2]))
    }

    func testTogglingStartsFromTheShownMovesAndStopsAtFour() {
        let store = BattleEntryStore(defaults: defaults)

        store.toggleMove(1, for: "a", pokemonID: 25, current: [1, 2, 3, 4])
        XCTAssertEqual(store.slot?.moves, [2, 3, 4])
        store.toggleMove(5, for: "a", pokemonID: 25, current: store.slot?.moves ?? [])
        store.toggleMove(6, for: "a", pokemonID: 25, current: store.slot?.moves ?? [])
        XCTAssertEqual(store.slot, BattleEntrySlot(instanceID: "a", pokemonID: 25, moves: [2, 3, 4, 5]))

        store.resetMoves()
        XCTAssertEqual(store.slot, BattleEntrySlot(instanceID: "a"))
    }
}

@MainActor
final class LearnableMovesTests: XCTestCase {
    func testRequestAsksForThePokemonAtItsLevel() throws {
        let request = try XCTUnwrap(PartyUploader.movesRequest(
            serverURL: "http://example.local:8790", token: "secret", pokemonID: 25, level: 42))

        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "http://example.local:8790/v1/moves?pokemon_id=25&level=42")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
    }

    func testDecodesTheBotReplyAndFailsQuietly() async throws {
        let body = Data("""
        {"ok": true, "default": [85], "moves": [{"id": 85, "name": "10만볼트", "type": "electric", "power": 90,
         "damage_class": "special", "accuracy": null, "level": 26}]}
        """.utf8)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Moves-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let tokens = PartyTokenStore(fileURL: directory.appendingPathComponent("token"))
        try tokens.save("secret")
        let suite = "Moves-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        func uploader(status: Int) -> PartyUploader {
            let uploader = PartyUploader(tokenStore: tokens, defaults: defaults, appVersion: nil,
                                         send: { _ in 200 }, fetch: { _ in (body, status) }, partySource: { [] })
            uploader.serverURL = "http://example.local:8790"
            return uploader
        }

        let moves = await uploader(status: 200).learnableMoves(pokemonID: 25, level: 42)
        let offline = await uploader(status: 503).learnableMoves(pokemonID: 25, level: 42)

        XCTAssertEqual(moves?.default, [85])
        XCTAssertEqual(moves?.moves, [LearnableMove(id: 85, name: "10만볼트", type: "electric", power: 90,
                                                    damageClass: "special", accuracy: nil, level: 26)])
        XCTAssertNil(offline)
    }

    func testDecodesTheDetailFields() throws {
        let body = Data("""
        {"ok": true, "default": [315], "moves": [{"id": 315, "name": "오버히트", "type": "fire", "power": 130,
         "damage_class": "special", "accuracy": 90, "level": 50, "pp": 5, "crit_rate": 0, "ailment": null,
         "ailment_chance": 0, "stat_changes": [{"stat": "special_attack", "change": -2}], "stat_target": "user",
         "stat_chance": 100}]}
        """.utf8)

        let move = try XCTUnwrap(LearnableMoves.decode(body).moves.first)

        XCTAssertEqual(move.pp, 5)
        XCTAssertNil(move.ailment)
        XCTAssertEqual(move.statChanges, [LearnableMove.StatChange(stat: "special_attack", change: -2)])
        XCTAssertEqual(move.statTarget, "user")
        XCTAssertEqual(move.statChance, 100)
        XCTAssertNil(move.drain)
        XCTAssertNil(move.maxHits)
    }

    func testDecodesStatusDrainAndHitFields() throws {
        let body = Data("""
        {"ok": true, "default": [3], "moves": [{"id": 3, "name": "연속뺨치기", "type": "normal", "power": 15,
         "damage_class": "physical", "accuracy": 85, "level": 1, "ailment": "toxic", "ailment_chance": 50,
         "drain": -25, "min_hits": 2, "max_hits": 5}]}
        """.utf8)

        let move = try XCTUnwrap(LearnableMoves.decode(body).moves.first)

        XCTAssertEqual([move.ailment, move.drain.map(String.init), move.minHits.map(String.init),
                        move.maxHits.map(String.init)], ["toxic", "-25", "2", "5"])
        XCTAssertEqual(L(.en).moveAilment("toxic"), "Toxic")
        XCTAssertEqual(L(.en).moveAilment("burn"), "Burn")
    }
}
