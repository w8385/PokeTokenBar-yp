import Foundation
import XCTest
@testable import PokeTokenBar

private struct OfflineProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class BoxSlotPlacementTests: XCTestCase {
    private func entry(_ species: Int, id: String, released: Bool = false) -> DexEntry {
        var profile = PokemonProfile.generate(seed: 7, instanceID: id)
        profile.level = 30
        var entry = DexEntry(baseID: species, finalID: species, chainOrder: [species], rarity: .common, caughtAt: nil,
                             isShiny: false, profile: profile, names: [species: ["ko": id, "en": id]],
                             releasedAt: released ? Date(timeIntervalSince1970: 1) : nil)
        entry.id = id
        return entry
    }

    private func store() -> CompanionStore {
        var state = CompanionState()
        var profile = PokemonProfile.generate(seed: 7, instanceID: "raised")
        profile.level = 42
        state.active = MonState(baseID: 4, pathIDs: [4, 5], stageIndex: 1, usedAtStage: 0,
                                rarity: .common, totalForms: 3, profile: profile)
        state.dex = [entry(10, id: "a"), entry(25, id: "b"), entry(94, id: "c"), entry(12, id: "gone", released: true)]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("box-slot-\(UUID()).json")
        try? JSONEncoder().encode(state).write(to: url)
        return CompanionStore(provider: OfflineProvider(), fileURL: url, rng: SeededRNG(seed: 1))
    }

    private func dex(_ store: CompanionStore, _ id: String) throws -> DexEntry {
        try XCTUnwrap(store.dexEntries.first { $0.id == id } ?? store.state.dex.first { $0.id == id })
    }

    private func suite() -> UserDefaults { UserDefaults(suiteName: "box-slot-\(UUID())")! }

    func testPlacingIntoAnEmptySlotAppendsAndPinsTheAutoFighterInSlotOne() throws {
        let store = store()
        let battle = BattleEntryStore(defaults: suite())

        XCTAssertTrue(battle.place(try dex(store, "a"), at: 2, in: store))

        XCTAssertEqual(battle.slots.map(\.instanceID), ["raised", "a"])
    }

    func testPlacingIntoAnOccupiedSlotReplacesTheHolderAndResetsItsMoves() throws {
        let store = store()
        let battle = BattleEntryStore(defaults: suite())
        battle.add("raised")
        battle.toggleMove(85, for: "raised", pokemonID: 5, current: [])
        battle.add("a")

        XCTAssertTrue(battle.place(try dex(store, "b"), at: 0, in: store))

        XCTAssertEqual(battle.slots.map(\.instanceID), ["b", "a"])
        XCTAssertEqual(battle.slot(for: "b")?.moves, [])
    }

    func testTappingItsOwnSlotTakesItOutButNeverTheLastMember() throws {
        let store = store()
        let battle = BattleEntryStore(defaults: suite())
        battle.add("raised")
        battle.add("a")
        let a = try dex(store, "a")

        XCTAssertTrue(battle.place(a, at: 1, in: store))
        XCTAssertEqual(battle.slots.map(\.instanceID), ["raised"])

        let raised = try XCTUnwrap(store.dexEntries.first { store.isActiveDexEntry($0) })
        XCTAssertFalse(battle.place(raised, at: 0, in: store))
        XCTAssertEqual(battle.slots.map(\.instanceID), ["raised"])
    }

    func testPlacingAMemberInAnotherSlotSwapsAndKeepsItsMoves() throws {
        let store = store()
        let battle = BattleEntryStore(defaults: suite())
        battle.add("raised")
        battle.add("a")
        battle.add("b")
        battle.toggleMove(85, for: "a", pokemonID: 10, current: [])

        XCTAssertTrue(battle.place(try dex(store, "a"), at: 2, in: store))

        XCTAssertEqual(battle.slots.map(\.instanceID), ["raised", "b", "a"])
        XCTAssertEqual(battle.slot(for: "a")?.moves, [85])
    }

    func testAnEmptySlotAfterTheLastMovesAMemberToTheEnd() throws {
        let store = store()
        let battle = BattleEntryStore(defaults: suite())
        battle.add("raised")
        battle.add("a")

        let raised = try XCTUnwrap(store.dexEntries.first { store.isActiveDexEntry($0) })
        XCTAssertTrue(battle.place(raised, at: 2, in: store))
        XCTAssertEqual(battle.slots.map(\.instanceID), ["a", "raised"])
    }

    func testATradeListedPokemonCannotMoveAndAnIneligibleOneHasNoSlot() throws {
        let store = store()
        let battle = BattleEntryStore(defaults: suite())
        store.lockForTrade("b")

        XCTAssertFalse(battle.place(try dex(store, "b"), at: 1, in: store))
        XCTAssertEqual(battle.slots, [])
        let gone = try dex(store, "gone")
        XCTAssertNil(store.battleCandidate(for: gone))
        XCTAssertFalse(battle.place(gone, at: 1, in: store))
    }

    func testSlotOrderSurvivesARelaunch() throws {
        let store = store()
        let defaults = suite()
        let battle = BattleEntryStore(defaults: defaults)
        battle.add("raised")
        battle.add("a")
        battle.add("b")
        XCTAssertTrue(battle.place(try dex(store, "b"), at: 0, in: store))

        let relaunched = BattleEntryStore(defaults: defaults)

        XCTAssertEqual(relaunched.slots.map(\.instanceID), ["b", "a", "raised"])
    }

    func testEachRealChangeReportsOnceAndANoOpReportsNothing() throws {
        let store = store()
        let battle = BattleEntryStore(defaults: suite())
        let a = try dex(store, "a")

        let results = [battle.place(a, at: 1, in: store), battle.place(a, at: 2, in: store),
                       battle.place(a, at: 1, in: store)]

        XCTAssertEqual(results, [true, false, true])
    }
}
