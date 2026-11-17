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

    private func party(_ state: CompanionState, slot: BattleEntrySlot?,
                       moves: [String: MoveChoice] = [:]) -> [PartyMember] {
        party(state, slots: slot.map { [$0] } ?? [], moves: moves)
    }

    private func party(_ state: CompanionState, slots: [BattleEntrySlot],
                       moves: [String: MoveChoice] = [:]) -> [PartyMember] {
        BattleEntry.party(state: state, slots: slots, moveChoices: moves, rentalSpeciesID: 4)
    }

    private func ids(_ names: String...) -> [BattleEntrySlot] { names.map { BattleEntrySlot(instanceID: $0) } }

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
        let party = self.party(state(), slot: BattleEntrySlot(instanceID: "pikachu"),
                               moves: ["pikachu": MoveChoice(pokemonID: 25, moves: [85, 98])])

        XCTAssertEqual(party.map(\.pokemonID), [25])
        XCTAssertEqual(party.map(\.level), [60])
        XCTAssertEqual(party[0].moves, [85, 98])
    }

    func testMovesChosenBeforeEvolutionAreDropped() {
        let party = self.party(state(), slot: BattleEntrySlot(instanceID: "raised"),
                               moves: ["raised": MoveChoice(pokemonID: 4, moves: [52])])

        XCTAssertEqual(party.map(\.pokemonID), [5])
        XCTAssertNil(party[0].moves)
    }

    func testNoOwnedChoiceSendsThePokemonBeingRaisedWithoutTheStaleMoves() {
        let gone = BattleEntrySlot(instanceID: "gone")
        let moves = ["gone": MoveChoice(pokemonID: 12, moves: [16])]

        XCTAssertEqual(party(state(), slot: nil).map(\.pokemonID), [5])
        XCTAssertEqual(party(state(), slot: gone, moves: moves).map(\.pokemonID), [5])
        XCTAssertNil(party(state(), slot: gone, moves: moves)[0].moves)
    }

    func testMovesChosenOnTheBoxPageFollowAPokemonOutsideTheLineupInWhenItJoins() {
        let moves = ["caterpie": MoveChoice(pokemonID: 10, moves: [33])]

        XCTAssertNil(party(state(), slots: ids("pikachu"), moves: moves)[0].moves)
        XCTAssertEqual(party(state(), slots: ids("pikachu", "caterpie"), moves: moves)[1].moves, [33])
    }

    func testThreePicksFightInSlotOrderEachWithItsOwnMoves() {
        let slots = ids("pikachu", "raised", "caterpie")

        let party = self.party(state(), slots: slots, moves: ["pikachu": MoveChoice(pokemonID: 25, moves: [85])])

        XCTAssertEqual(party.map(\.pokemonID), [25, 5, 10])
        XCTAssertEqual(party.map(\.level), [60, 42, 30])
        XCTAssertEqual(party[0].moves, [85])
        XCTAssertNil(party[1].moves)
        XCTAssertNil(party[2].moves)
    }

    func testThePartyHoldsEveryPickOnceAndNeverTheSamePokemonTwice() {
        var state = state()
        state.dex.append(entry(16, id: "pidgey"))

        let party = self.party(state, slots: ids("caterpie", "caterpie", "pikachu", "raised", "pidgey"))

        XCTAssertEqual(party.map(\.pokemonID), [10, 25, 5, 16])
    }

    func testReleasedPicksAreSkippedAndTheRestKeepTheirOrder() {
        let party = self.party(state(), slots: ids("gone", "pikachu", "missing", "caterpie"))

        XCTAssertEqual(party.map(\.pokemonID), [25, 10])
    }

    func testAnEggCannotBePickedSoOnlyKeptCatchesFight() {
        var egg = state()
        egg.active = nil

        XCTAssertEqual(BattleEntry.candidates(in: egg).map(\.id), ["caterpie", "pikachu"])
        XCTAssertEqual(party(egg, slots: ids("raised", "caterpie")).map(\.pokemonID), [10])
        XCTAssertEqual(party(egg, slots: ids("raised")).map(\.pokemonID), [25])
    }

    func testPicksNeedNotIncludeThePokemonBeingRaised() {
        XCTAssertEqual(party(state(), slots: ids("caterpie", "pikachu")).map(\.pokemonID), [10, 25])
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

        XCTAssertNil(BattleEntry.autoFighter(state: egg))
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

    private func ids(_ store: BattleEntryStore) -> [String] { store.slots.map(\.instanceID) }

    func testAddingFillsTheFirstFreeSlotUpToSixAndPersists() {
        let store = BattleEntryStore(defaults: defaults)

        XCTAssertTrue(store.add("a"))
        XCTAssertTrue(store.add("b"))
        XCTAssertFalse(store.add("b"))
        for id in ["c", "d", "e", "f"] { XCTAssertTrue(store.add(id)) }
        XCTAssertFalse(store.add("g"))

        XCTAssertEqual(ids(store), ["a", "b", "c", "d", "e", "f"])
        XCTAssertEqual(ids(BattleEntryStore(defaults: defaults)), ["a", "b", "c", "d", "e", "f"])
    }

    func testAddingToAnEmptyEntryKeepsTheAutoFighterInSlotOne() {
        let store = BattleEntryStore(defaults: defaults)

        store.add("pikachu", pinning: "raised")

        XCTAssertEqual(ids(store), ["raised", "pikachu"])
    }

    func testReplacingKeepsTheSlotButNotForADuplicate() {
        let store = BattleEntryStore(defaults: defaults)
        store.add("a")
        store.add("b")

        store.replace("a", with: "b")
        XCTAssertEqual(ids(store), ["a", "b"])

        store.replace("a", with: "c")
        XCTAssertEqual(store.slots, [BattleEntrySlot(instanceID: "c"), BattleEntrySlot(instanceID: "b")])
    }

    func testReplacingTheAutoFighterPicksOnlyThatOne() {
        let store = BattleEntryStore(defaults: defaults)

        store.replace("raised", with: "pikachu")

        XCTAssertEqual(ids(store), ["pikachu"])
    }

    func testRemovingAndReorderingKeepEachSlotsMoves() {
        let store = BattleEntryStore(defaults: defaults)
        store.add("a")
        store.add("b")
        store.add("c")
        store.chooseMove(9, at: 0, for: "c", pokemonID: 25, current: [])

        store.move("c", by: -1)
        XCTAssertEqual(ids(store), ["a", "c", "b"])
        store.move("a", by: -1)
        store.move("b", by: 1)
        XCTAssertEqual(ids(store), ["a", "c", "b"])
        XCTAssertEqual(store.chosenMoves(for: "c", pokemonID: 25), [9])

        store.remove("a")
        XCTAssertEqual(ids(store), ["c", "b"])
        store.replace("c", with: "d")
        store.remove("d")
        store.remove("b")
        XCTAssertEqual(store.slots, [])
        XCTAssertEqual(store.chosenMoves(for: "c", pokemonID: 25), [9])
    }

    func testPruneForgetsPicksThatAreNoLongerOwned() {
        let store = BattleEntryStore(defaults: defaults)
        store.add("a")
        store.add("gone")
        store.add("c")

        store.prune(owned: ["a", "c"])

        XCTAssertEqual(ids(store), ["a", "c"])
        XCTAssertTrue(store.add("d"))
    }

    func testTheRentalIsPickedOnceAmongTheStartersAndCanBeSwitched() {
        let store = BattleEntryStore(defaults: defaults)
        XCTAssertTrue(BattleEntry.rentalSpeciesIDs.contains(store.rentalSpeciesID))
        XCTAssertEqual(BattleEntryStore(defaults: defaults).rentalSpeciesID, store.rentalSpeciesID)

        store.chooseRental(7)
        store.chooseRental(25)
        XCTAssertEqual(BattleEntryStore(defaults: defaults).rentalSpeciesID, 7)
    }

    func testAnOlderOneOrThreeSlotEntryLoadsAsIs() throws {
        let saved = ["a", "b", "c"].map { BattleEntrySlot(instanceID: $0) }
        defaults.set(try JSONEncoder().encode(saved), forKey: BattleEntryStore.defaultsKey)
        XCTAssertEqual(BattleEntryStore(defaults: defaults).slots, saved)

        defaults.set(try JSONEncoder().encode([saved[0]]), forKey: BattleEntryStore.defaultsKey)
        XCTAssertEqual(BattleEntryStore(defaults: defaults).slots, [saved[0]])
    }

    func testMovesSavedInsideSlotsMoveToTheirPokemonOnceAndStayResetWhenCleared() {
        let legacy = #"[{"instanceID":"a","pokemonID":25,"moves":[85,98]},{"instanceID":"b","moves":[]},{"instanceID":"c"}]"#
        defaults.set(Data(legacy.utf8), forKey: BattleEntryStore.defaultsKey)

        let store = BattleEntryStore(defaults: defaults)
        XCTAssertEqual(ids(store), ["a", "b", "c"])
        XCTAssertEqual(store.chosenMoves(for: "a", pokemonID: 25), [85, 98])
        XCTAssertEqual(store.chosenMoves(for: "b", pokemonID: 25), [])

        store.resetMoves(for: "a")
        let reloaded = BattleEntryStore(defaults: defaults)
        XCTAssertEqual(ids(reloaded), ["a", "b", "c"])
        XCTAssertEqual(reloaded.chosenMoves(for: "a", pokemonID: 25), [])
    }

    func testALoadedEntryDropsDuplicatesAndKeepsAtMostSix() throws {
        let saved = ["a", "a", "b", "c", "d", "e", "f", "g"].map { BattleEntrySlot(instanceID: $0) }
        defaults.set(try JSONEncoder().encode(saved), forKey: BattleEntryStore.defaultsKey)

        XCTAssertEqual(ids(BattleEntryStore(defaults: defaults)), ["a", "b", "c", "d", "e", "f"])
    }

    func testChoosingAMoveStartsFromTheShownMovesReplacesOrSwapsAndStopsAtFour() {
        let store = BattleEntryStore(defaults: defaults)

        store.chooseMove(9, at: 1, for: "a", pokemonID: 25, current: [1, 2, 3, 4])
        XCTAssertEqual(store.chosenMoves(for: "a", pokemonID: 25), [1, 9, 3, 4])
        store.chooseMove(4, at: 0, for: "a", pokemonID: 25, current: [1, 9, 3, 4])
        XCTAssertEqual(store.chosenMoves(for: "a", pokemonID: 25), [4, 9, 3, 1])
        store.chooseMove(9, at: 1, for: "a", pokemonID: 25, current: [4, 9, 3, 1])
        XCTAssertEqual(store.chosenMoves(for: "a", pokemonID: 25), [4, 9, 3, 1])
        store.chooseMove(7, at: 3, for: "a", pokemonID: 25, current: [4, 9, 3])
        XCTAssertEqual(store.chosenMoves(for: "a", pokemonID: 25), [4, 9, 3, 7])
        store.chooseMove(8, at: 4, for: "a", pokemonID: 25, current: [4, 9, 3, 7])
        XCTAssertEqual(store.chosenMoves(for: "a", pokemonID: 25), [4, 9, 3, 7])

        store.resetMoves(for: "a")
        XCTAssertEqual(store.chosenMoves(for: "a", pokemonID: 25), [])
        XCTAssertTrue(store.slots.isEmpty)
    }

    func testMoveChoicesBelongToThePokemonNotTheLineupAndSurviveARestart() {
        let store = BattleEntryStore(defaults: defaults)
        store.add("a")
        store.add("b")

        store.chooseMove(1, at: 0, for: "outsider", pokemonID: 25, current: [])
        store.chooseMove(2, at: 0, for: "a", pokemonID: 4, current: [3])
        store.remove("a")

        XCTAssertEqual(ids(store), ["b"])
        let reloaded = BattleEntryStore(defaults: defaults)
        XCTAssertEqual(reloaded.chosenMoves(for: "outsider", pokemonID: 25), [1])
        XCTAssertEqual(reloaded.chosenMoves(for: "a", pokemonID: 4), [2])
        XCTAssertEqual(reloaded.chosenMoves(for: "a", pokemonID: 5), [])
    }

    func testPruneForgetsMoveChoicesOfPokemonThatAreGone() {
        let store = BattleEntryStore(defaults: defaults)
        store.chooseMove(1, at: 0, for: "kept", pokemonID: 25, current: [])
        store.chooseMove(1, at: 0, for: "gone", pokemonID: 25, current: [])

        store.prune(owned: ["kept"])

        XCTAssertEqual(store.moveChoices.keys.sorted(), ["kept"])
    }
}

@MainActor
final class LearnableMovesTests: XCTestCase {
    func testRequestAsksForThePokemonAtItsLevelAndOptsIntoMachineMoves() throws {
        let request = try XCTUnwrap(PartyUploader.movesRequest(
            serverURL: "http://example.local:8790", token: "secret", pokemonID: 25, level: 42))

        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "http://example.local:8790/v1/moves?pokemon_id=25&level=42&machine=1")
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
