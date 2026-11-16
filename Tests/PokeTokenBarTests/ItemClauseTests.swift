import Foundation
import XCTest
@testable import PokeTokenBar

private struct ClauseProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class ItemClauseTests: XCTestCase {
    private let charizardX = MegaStone.stone(slug: "charizardite-x")!

    private func entry(_ species: Int, id: String) -> DexEntry {
        var profile = PokemonProfile.generate(seed: 7, instanceID: id)
        profile.level = 30
        var entry = DexEntry(baseID: species, finalID: species, chainOrder: [species], rarity: .common, caughtAt: nil,
                             isShiny: false, profile: profile, names: [species: ["ko": id, "en": id]])
        entry.id = id
        return entry
    }

    private func store(held: [String: String] = [:], inventory: [String: Int] = [:], tokens: Int = 0) -> CompanionStore {
        var state = CompanionState()
        state.installBaselineSet = true
        state.usedSinceInstall = tokens
        var profile = PokemonProfile.generate(seed: 7, instanceID: "raised")
        profile.level = 42
        state.active = MonState(baseID: 4, pathIDs: [4, 5], stageIndex: 1, usedAtStage: 0,
                                rarity: .common, totalForms: 3, profile: profile)
        state.dex = [entry(6, id: "a"), entry(25, id: "b"), entry(94, id: "c")]
        state.heldItems = held
        state.inventory = inventory
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("clause-\(UUID()).json")
        try? JSONEncoder().encode(state).write(to: url)
        return CompanionStore(provider: ClauseProvider(), fileURL: url, rng: SeededRNG(seed: 1))
    }

    private func dex(_ store: CompanionStore, _ id: String) throws -> DexEntry {
        try XCTUnwrap(store.state.dex.first { $0.id == id })
    }

    private func battle(_ ids: [String]) -> BattleEntryStore {
        let battle = BattleEntryStore(defaults: UserDefaults(suiteName: "clause-\(UUID())")!)
        ids.forEach { battle.add($0) }
        return battle
    }

    // MARK: Mega Stone purchase limit

    func testBuyingTheSameStoneTwiceIsRefused() {
        let store = store(tokens: 10 * MegaStone.price)

        XCTAssertTrue(store.buy(charizardX))
        XCTAssertFalse(store.canBuy(charizardX))
        XCTAssertFalse(store.buy(charizardX))
        XCTAssertEqual(store.megaStoneCount(charizardX), 1)
    }

    func testBuyingStaysRefusedWhileTheStoneIsEquippedAndAfterItComesOff() {
        let store = store(tokens: 10 * MegaStone.price)
        XCTAssertTrue(store.buy(charizardX))
        XCTAssertTrue(store.equip(charizardX, to: "a"))

        XCTAssertFalse(store.canBuy(charizardX))
        XCTAssertFalse(store.buy(charizardX))

        XCTAssertTrue(store.unequip(from: "a"))
        XCTAssertFalse(store.canBuy(charizardX))
    }

    func testAnotherStoneKindIsStillBuyableAndOwnersOfTwoKeepBoth() {
        let store = store(inventory: [charizardX.inventoryKey: 2], tokens: 10 * MegaStone.price)
        let charizardY = MegaStone.stone(slug: "charizardite-y")!

        XCTAssertFalse(store.canBuy(charizardX))
        XCTAssertEqual(store.megaStoneCount(charizardX), 2)
        XCTAssertTrue(store.canBuy(charizardY))
    }

    // MARK: Lineup item clause

    func testPlacingIsRefusedWhenAnotherMemberHoldsTheSameItem() throws {
        let store = store(held: ["a": "leftovers", "b": "leftovers"])
        let battle = battle(["raised", "a"])

        XCTAssertFalse(battle.place(try dex(store, "b"), at: 2, in: store))
        XCTAssertEqual(battle.slots.map(\.instanceID), ["raised", "a"])
    }

    func testPlacingOverTheMemberWithTheSameItemIsAllowed() throws {
        let store = store(held: ["a": "leftovers", "b": "leftovers"])
        let battle = battle(["raised", "a"])

        XCTAssertTrue(battle.place(try dex(store, "b"), at: 1, in: store))
        XCTAssertEqual(battle.slots.map(\.instanceID), ["raised", "b"])
    }

    func testAPokemonWithoutAnItemIsNeverBlocked() throws {
        let store = store(held: ["a": "leftovers", "b": "leftovers"])
        let battle = battle(["a", "c"])

        XCTAssertTrue(battle.place(try dex(store, "c"), at: 0, in: store))
        XCTAssertEqual(BattleEntry.itemBlockedCandidates(state: store.state, slots: battle.slots, replacing: nil), ["b"])
    }

    func testMembersOfAnAlreadyViolatingLineupCanStillSwapAndLeave() throws {
        let store = store(held: ["a": "leftovers", "b": "leftovers"])
        let battle = battle(["a", "b"])

        XCTAssertTrue(battle.place(try dex(store, "a"), at: 1, in: store))
        XCTAssertEqual(battle.slots.map(\.instanceID), ["b", "a"])
        XCTAssertTrue(battle.place(try dex(store, "a"), at: 1, in: store))
        XCTAssertEqual(battle.slots.map(\.instanceID), ["b"])
    }

    func testEquippingOntoALineupMemberIsBlockedOnlyForAnItemAnotherMemberHolds() {
        let store = store(held: ["a": "leftovers"])
        let slots = battle(["raised", "a"]).slots

        XCTAssertTrue(BattleEntry.equipClash("leftovers", onto: "raised", state: store.state, slots: slots))
        XCTAssertFalse(BattleEntry.equipClash("lifeOrb", onto: "raised", state: store.state, slots: slots))
        XCTAssertFalse(BattleEntry.equipClash("leftovers", onto: "b", state: store.state, slots: slots))
        XCTAssertFalse(BattleEntry.equipClash("leftovers", onto: "a", state: store.state, slots: slots))
    }

    func testEquippingTheSameStoneKindIsAlsoAClash() {
        let store = store(held: ["a": charizardX.inventoryKey])
        let slots = battle(["raised", "a"]).slots

        XCTAssertTrue(BattleEntry.equipClash(charizardX.inventoryKey, onto: "raised", state: store.state, slots: slots))
    }

    func testAViolatingSaveUploadsOnlyTheFirstHoldersItemAndIsNotRewritten() {
        let store = store(held: ["a": "leftovers", "b": "leftovers", "c": "lifeOrb"])
        let slots = battle(["a", "b", "c"]).slots

        let party = BattleEntry.party(state: store.state, slots: slots, moveChoices: [:], rentalSpeciesID: 1)

        XCTAssertEqual(party.map(\.heldItem), [store.state.heldItemSlug(of: "a"), nil, store.state.heldItemSlug(of: "c")])
        XCTAssertNotNil(store.state.heldItemSlug(of: "a"))
        XCTAssertEqual(BattleEntry.duplicateItemHolders(state: store.state, slots: slots), ["b"])
        XCTAssertEqual(store.state.heldItems["b"], "leftovers")
    }

    func testDistinctItemsAreUploadedUntouched() {
        let store = store(held: ["a": "leftovers", "b": "lifeOrb"])
        let slots = battle(["a", "b"]).slots

        let party = BattleEntry.party(state: store.state, slots: slots, moveChoices: [:], rentalSpeciesID: 1)

        XCTAssertEqual(party.map(\.heldItem), [store.state.heldItemSlug(of: "a"), store.state.heldItemSlug(of: "b")])
        XCTAssertTrue(BattleEntry.duplicateItemHolders(state: store.state, slots: slots).isEmpty)
    }
}
