import Foundation
import XCTest
@testable import PokeTokenBar

@MainActor
final class BattleSixSlotTests: XCTestCase {
    private let names = ["a", "b", "c", "d", "e", "f", "g"]

    private func entry(_ species: Int, id: String) -> DexEntry {
        var profile = PokemonProfile.generate(seed: 7, instanceID: id)
        profile.level = 30
        var entry = DexEntry(baseID: species, finalID: species, chainOrder: [species], rarity: .common, caughtAt: nil,
                             profile: profile)
        entry.id = id
        return entry
    }

    private func state(held: [String: String] = [:]) -> CompanionState {
        var state = CompanionState()
        state.dex = names.enumerated().map { entry(10 + $0.offset, id: $0.element) }
        state.heldItems = held
        return state
    }

    private func slots(_ ids: [String]) -> [BattleEntrySlot] { ids.map { BattleEntrySlot(instanceID: $0) } }

    private func party(_ state: CompanionState, _ ids: [String]) -> [PartyMember] {
        BattleEntry.party(state: state, slots: slots(ids), moveChoices: [:], rentalSpeciesID: 4)
    }

    private func suite() -> UserDefaults { UserDefaults(suiteName: "six-slot-\(UUID())")! }

    func testTheLineupHoldsSixAndTheBotGetsAllSixInOrder() {
        let state = state()
        let six = Array(names.prefix(6))

        XCTAssertEqual(BattleEntry.lineup(state: state, slots: slots(names)).map(\.id), six)
        XCTAssertEqual(party(state, names).map(\.pokemonID), [10, 11, 12, 13, 14, 15])
    }

    func testMembersNoLongerOwnedDropOutAndTheRestMoveUp() {
        var state = state()
        state.dex.removeAll { ["a", "c"].contains($0.id) }

        XCTAssertEqual(party(state, ["a", "b", "c", "d"]).map(\.pokemonID), [11, 13])
    }

    func testMovingASlotReordersTheUploadedParty() {
        let state = state()
        let store = BattleEntryStore(defaults: suite())
        ["a", "b", "c", "d"].forEach { store.add($0) }

        store.move("c", by: 1)
        XCTAssertEqual(party(state, store.slots.map(\.instanceID)).map(\.pokemonID), [10, 11, 13, 12])
    }

    func testAStoredThreeSlotListLoadsAndTheFreeSlotsTakeMore() throws {
        let defaults = suite()
        defaults.set(try JSONEncoder().encode(slots(["a", "b", "c"])), forKey: BattleEntryStore.defaultsKey)

        let store = BattleEntryStore(defaults: defaults)
        XCTAssertEqual(store.slots.map(\.instanceID), ["a", "b", "c"])
        XCTAssertTrue(store.add("d"))
        XCTAssertEqual(party(state(), store.slots.map(\.instanceID)).map(\.pokemonID), [10, 11, 12, 13])
    }

    func testTheItemClauseCoversSlotsFourToSix() {
        let state = state(held: ["a": "leftovers", "e": "leftovers", "f": "lifeOrb"])
        let ids = Array(names.prefix(6))

        XCTAssertEqual(BattleEntry.duplicateItemHolders(state: state, slots: slots(ids)), ["e"])
        XCTAssertTrue(BattleEntry.itemClash("g", replacing: nil, among: ids, state: stateHolding("g", "lifeOrb")))
        XCTAssertTrue(BattleEntry.equipClash("leftovers", onto: "f", state: state, slots: slots(ids)))
    }

    func testALaterMemberWithADuplicateItemUploadsWithoutIt() {
        let upload = party(state(held: ["a": "leftovers", "e": "leftovers"]), names)

        XCTAssertEqual(upload.map(\.heldItem), ["leftovers", nil, nil, nil, nil, nil])
    }

    private func stateHolding(_ id: String, _ key: String) -> CompanionState {
        var state = state(held: ["f": key])
        state.heldItems[id] = key
        return state
    }
}
