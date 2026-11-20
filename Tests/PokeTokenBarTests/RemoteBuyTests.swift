import Foundation
import XCTest
@testable import PokeTokenBar

private struct BuyProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class RemoteBuyTests: XCTestCase {
    nonisolated(unsafe) private var paths: [URL] = []
    nonisolated(unsafe) private var suites: [String] = []
    private let candy = ItemKind.rareCandy.rawValue
    private let leftovers = ItemKind.leftovers.rawValue
    private let thunder = MachineMove.inventoryKey(87)

    override func tearDown() {
        for path in paths { try? FileManager.default.removeItem(at: path) }
        for suite in suites { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        super.tearDown()
    }

    // MARK: Buying

    func testABuyRunsTheShopPurchaseAndLeavesNoUndo() throws {
        let rig = try rig()
        let price = try XCTUnwrap(rig.store.price(of: .rareCandy))
        XCTAssertNil(apply(rig, candy, count: 3, price: price))
        XCTAssertEqual(rig.store.state.inventory[candy], 3)
        XCTAssertEqual(rig.store.state.spentTokens, price * 3)
        XCTAssertTrue(rig.store.purchaseReceipts.isEmpty)
    }

    func testAMegaStoneAndATMAreBoughtOnceAndLeaveTheShop() throws {
        let rig = try rig()
        let stone = MegaStone.all[0]
        let stonePrice = rig.store.price(of: .megaStone(stone))
        let tmPrice = try XCTUnwrap(line(rig, thunder)).price
        XCTAssertNil(apply(rig, stone.inventoryKey, count: 1, price: stonePrice))
        XCTAssertNil(apply(rig, thunder, count: 1, price: tmPrice))
        XCTAssertEqual(rig.store.state.inventory[stone.inventoryKey], 1)
        XCTAssertTrue(rig.store.ownsTM(87))
        XCTAssertNil(line(rig, stone.inventoryKey))
        XCTAssertNil(line(rig, thunder))
        XCTAssertEqual(apply(rig, thunder, count: 1, price: tmPrice), RemoteBuy.Reason.notSold)
    }

    func testScoutTicketsAreBoughtByTheCount() throws {
        let rig = try rig()
        let pool = ScoutPool.all[0]
        XCTAssertNil(apply(rig, pool.inventoryKey, count: 2, price: rig.store.scoutPrice))
        XCTAssertEqual(rig.store.scoutTicketCount(pool), 2)
        XCTAssertEqual(rig.store.state.spentTokens, rig.store.scoutPrice * 2)
    }

    func testTheShopLinesSayWhatCanBeHeldAndWhatSellsOneAtATime() throws {
        let rig = try rig()
        let held = try XCTUnwrap(line(rig, leftovers))
        XCTAssertEqual(held.equip, true)
        XCTAssertEqual(held.heldItem, "leftovers")
        XCTAssertEqual(held.categoryName, "지닌 도구")
        XCTAssertNil(try XCTUnwrap(line(rig, candy)).equip)
        XCTAssertEqual(try XCTUnwrap(line(rig, ItemKind.expShare.rawValue)).single, true)
        XCTAssertEqual(try XCTUnwrap(line(rig, MegaStone.all[0].inventoryKey)).heldItem, MegaStone.all[0].slug)
    }

    // MARK: Cancelling with nothing changed

    func testAShortBalanceCancelsWithNothingChanged() throws {
        let price = try XCTUnwrap(ItemKind.rareCandy.shopPrice)
        let rig = try rig(wallet: price * 2)
        let before = rig.store.state
        XCTAssertEqual(rig.store.availableTokens, price * 2)
        XCTAssertEqual(apply(rig, candy, count: 3, price: price), RemoteBuy.Reason.noTokens)
        assertUnchanged(rig, before)
    }

    func testAnItemNoLongerSoldCancels() throws {
        let rig = try rig { $0.inventory[ItemKind.shinyCharm.rawValue] = 1 }
        let before = rig.store.state
        let price = try XCTUnwrap(rig.store.price(of: .shinyCharm))
        XCTAssertEqual(apply(rig, ItemKind.shinyCharm.rawValue, count: 1, price: price), RemoteBuy.Reason.notSold)
        XCTAssertEqual(apply(rig, "no-such-item", count: 1, price: 1), RemoteBuy.Reason.notSold)
        assertUnchanged(rig, before)
    }

    func testAnyPriceChangeCancels() throws {
        let rig = try rig()
        let before = rig.store.state
        let price = try XCTUnwrap(rig.store.price(of: .rareCandy))
        XCTAssertEqual(apply(rig, candy, count: 1, price: price + 1), RemoteBuy.Reason.priceChanged)
        XCTAssertEqual(apply(rig, candy, count: 1, price: price - 1), RemoteBuy.Reason.priceChanged)
        assertUnchanged(rig, before)
    }

    func testMoreThanOneOfALineSoldOneAtATimeIsInvalid() throws {
        let rig = try rig()
        let before = rig.store.state
        XCTAssertEqual(apply(rig, thunder, count: 2, price: try XCTUnwrap(line(rig, thunder)).price),
                       RemoteBuy.Reason.invalid)
        XCTAssertEqual(RemoteBuy.apply(Data("{}".utf8), store: rig.store), RemoteBuy.Reason.invalid)
        assertUnchanged(rig, before)
    }

    // MARK: Order with lineup ops

    func testALineupEquippingAPendingBuyAppliesAfterIt() throws {
        let rig = try rig()
        let price = try XCTUnwrap(line(rig, leftovers)).price
        rig.store.applyRemoteOps([buyOp(1, leftovers, price: price), lineupOp(2, item: leftovers)],
                                 appliers: RemoteOpAppliers.all(battleEntry: rig.battle))
        XCTAssertEqual(rig.store.state.remoteOpResults, [RemoteOpResult(id: 1), RemoteOpResult(id: 2)])
        XCTAssertEqual(rig.store.state.heldItems["b"], leftovers)
        XCTAssertEqual(rig.store.state.inventory[leftovers], 0)
        XCTAssertEqual(rig.battle.slots.map(\.instanceID), ["b"])
    }

    func testTheSameLineupWithoutTheBuyCancels() throws {
        let rig = try rig()
        rig.store.applyRemoteOps([lineupOp(1, item: leftovers)], appliers: RemoteOpAppliers.all(battleEntry: rig.battle))
        XCTAssertEqual(rig.store.state.remoteOpResults, [RemoteOpResult(id: 1, reason: RemoteLineup.Reason.noItem)])
        XCTAssertNil(rig.store.state.heldItems["b"])
    }

    // MARK: Idempotency

    func testABuyAppliedBeforeARestartIsNotAppliedAgain() throws {
        let rig = try rig()
        let price = try XCTUnwrap(rig.store.price(of: .rareCandy))
        let op = buyOp(1, candy, count: 2, price: price)
        rig.store.applyRemoteOps([op], appliers: RemoteOpAppliers.all(battleEntry: rig.battle))

        let store = try openStore(at: rig.url)
        store.applyRemoteOps([op], appliers: RemoteOpAppliers.all(battleEntry: rig.battle))

        XCTAssertEqual(store.state.remoteOpResults, [RemoteOpResult(id: 1)])
        XCTAssertEqual(store.state.inventory[candy], 2)
        XCTAssertEqual(store.state.spentTokens, price * 2)
    }

    // MARK: Helpers

    private struct Rig {
        let store: CompanionStore
        let battle: BattleEntryStore
        let url: URL
    }

    /// Pikachu `b` in the Box, nothing in the bag, and `wallet` tokens to spend.
    private func rig(wallet: Int = 9_000_000_000,_ edit: (inout CompanionState) -> Void = { _ in }) throws -> Rig {
        var state = CompanionState()
        state.installBaselineSet = true
        state.language = .ko
        state.usedSinceInstall = wallet
        var profile = PokemonProfile.generate(seed: 7, instanceID: "b")
        profile.level = 30
        var entry = DexEntry(baseID: 25, finalID: 25, chainOrder: [25], rarity: .common, caughtAt: nil,
                             isShiny: false, profile: profile, names: [25: ["ko": "b", "en": "b"]])
        entry.id = "b"
        state.dex = [entry]
        edit(&state)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("buy-\(UUID().uuidString).json")
        paths.append(url)
        try JSONEncoder().encode(state).write(to: url)
        let suite = "buy-\(UUID().uuidString)"
        suites.append(suite)
        let battle = BattleEntryStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        return Rig(store: try openStore(at: url), battle: battle, url: url)
    }

    private func openStore(at url: URL) throws -> CompanionStore {
        let suite = "buy-store-\(UUID().uuidString)"
        suites.append(suite)
        return CompanionStore(provider: BuyProvider(), fileURL: url, rng: SeededRNG(seed: 1),
                              dittoDisguiseRollingEnabled: false,
                              defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
    }

    private func line(_ rig: Rig, _ key: String) -> RemoteShopLine? {
        rig.store.remoteShop.first { $0.key == key }
    }

    private func buyPayload(_ key: String, count: Int, price: Int) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["key": key, "name": key, "count": count, "price": price])) ?? Data()
    }

    private func apply(_ rig: Rig, _ key: String, count: Int, price: Int) -> String? {
        RemoteBuy.apply(buyPayload(key, count: count, price: price), store: rig.store)
    }

    private func buyOp(_ id: Int, _ key: String, count: Int = 1, price: Int) -> RemoteOp {
        RemoteOp(id: id, kind: RemoteBuy.kind, payload: buyPayload(key, count: count, price: price))
    }

    private func lineupOp(_ id: Int, item: String) -> RemoteOp {
        let member: [String: Any] = ["id": "b", "pokemon_id": 25, "name": "b", "moves": [], "machine": [], "item": item]
        let payload = (try? JSONSerialization.data(withJSONObject: ["members": [member]])) ?? Data()
        return RemoteOp(id: id, kind: RemoteLineup.kind, payload: payload)
    }

    private func assertUnchanged(_ rig: Rig, _ before: CompanionState, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(rig.store.state.inventory, before.inventory, file: file, line: line)
        XCTAssertEqual(rig.store.state.spentTokens, before.spentTokens, file: file, line: line)
        XCTAssertTrue(rig.store.purchaseReceipts.isEmpty, file: file, line: line)
    }
}
