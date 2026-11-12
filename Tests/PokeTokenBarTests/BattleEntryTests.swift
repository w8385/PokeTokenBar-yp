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

    func testCandidatesAreTheRaisedPokemonAndKeptCatches() {
        let candidates = BattleEntry.candidates(in: state())

        XCTAssertEqual(candidates.map(\.id), ["raised", "caterpie", "pikachu"])
        XCTAssertEqual(candidates.map(\.member.pokemonID), [5, 10, 25])
        XCTAssertNil(candidates[0].dexEntry)
    }

    func testPartyFollowsTheChosenOrderWithChosenMoves() {
        let slots = [BattleEntrySlot(instanceID: "pikachu", pokemonID: 25, moves: [85, 98]),
                     BattleEntrySlot(instanceID: "raised")]

        let party = BattleEntry.party(state: state(), slots: slots)

        XCTAssertEqual(party.map(\.pokemonID), [25, 5])
        XCTAssertEqual(party.map(\.level), [60, 42])
        XCTAssertEqual(party[0].moves, [85, 98])
        XCTAssertNil(party[1].moves)
    }

    func testMovesChosenBeforeEvolutionAreDropped() {
        let slots = [BattleEntrySlot(instanceID: "raised", pokemonID: 4, moves: [52])]

        let party = BattleEntry.party(state: state(), slots: slots)

        XCTAssertEqual(party.map(\.pokemonID), [5])
        XCTAssertNil(party[0].moves)
    }

    func testNoOwnedChoiceSendsThePokemonBeingRaised() {
        let fallback = [5]

        XCTAssertEqual(BattleEntry.party(state: state(), slots: []).map(\.pokemonID), fallback)
        XCTAssertEqual(BattleEntry.party(state: state(), slots: [BattleEntrySlot(instanceID: "gone")])
            .map(\.pokemonID), fallback)
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

    func testAddsUpToThreeDistinctPokemonAndReorders() {
        let store = BattleEntryStore(defaults: defaults)
        for id in ["a", "b", "a", "c", "d"] { store.add(id) }
        XCTAssertEqual(store.slots.map(\.instanceID), ["a", "b", "c"])

        store.move("c", by: -1)
        store.move("a", by: -1)
        store.remove("b")

        XCTAssertEqual(store.slots.map(\.instanceID), ["a", "c"])
        XCTAssertEqual(BattleEntryStore(defaults: defaults).slots, store.slots)
    }

    func testTogglingStartsFromTheShownMovesAndStopsAtFour() {
        let store = BattleEntryStore(defaults: defaults)
        store.add("a")

        store.toggleMove(1, for: "a", pokemonID: 25, current: [1, 2, 3, 4])
        XCTAssertEqual(store.slots[0].moves, [2, 3, 4])
        store.toggleMove(5, for: "a", pokemonID: 25, current: store.slots[0].moves)
        store.toggleMove(6, for: "a", pokemonID: 25, current: store.slots[0].moves)
        XCTAssertEqual(store.slots[0], BattleEntrySlot(instanceID: "a", pokemonID: 25, moves: [2, 3, 4, 5]))

        store.resetMoves(for: "a")
        XCTAssertEqual(store.slots[0], BattleEntrySlot(instanceID: "a"))
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
}
