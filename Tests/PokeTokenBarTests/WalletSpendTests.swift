import XCTest
@testable import PokeTokenBar

/// Every place that spends wallet tokens: at the exact price it pays exactly the price, one token short it changes
/// nothing.
@MainActor
final class WalletSpendTests: XCTestCase {
    private func store(tokens: Int, timeCredit: Int = 0, inventory: [String: Int] = [:],
                       dex: [DexEntry] = []) async throws -> CompanionStore {
        var state = TrainingFixture.state(dex: dex, inventory: inventory, tokens: tokens)
        state.timeCredit = timeCredit
        return try await TrainingFixture(self).store(state)
    }

    private func assertPaid(_ s: CompanionStore, _ price: Int, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(s.state.spentTokens, price, file: file, line: line)
        XCTAssertEqual(s.availableTokens, 0, file: file, line: line)
    }

    private func assertUntouched(_ s: CompanionStore, wallet: Int, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(s.state.spentTokens, 0, file: file, line: line)
        XCTAssertEqual(s.availableTokens, wallet, file: file, line: line)
        XCTAssertTrue(s.state.inventory.isEmpty, "\(s.state.inventory)", file: file, line: line)
    }

    // MARK: Items

    func testBuyingSeveralItemsPaysThePriceTimesTheCount() async throws {
        let price = try XCTUnwrap(ItemKind.rareCandy.shopPrice) * 3
        let s = try await store(tokens: price)
        XCTAssertTrue(s.buy(.rareCandy, count: 3))
        assertPaid(s, price)
        XCTAssertEqual(s.itemCount(.rareCandy), 3)
    }

    func testBuyingSeveralItemsOneTokenShortBuysNone() async throws {
        let price = try XCTUnwrap(ItemKind.rareCandy.shopPrice) * 3
        let s = try await store(tokens: price - 1)
        XCTAssertFalse(s.buy(.rareCandy, count: 3))
        assertUntouched(s, wallet: price - 1)
    }

    func testTimeCreditAloneFundsAPurchase() async throws {
        let price = try XCTUnwrap(ItemKind.rareCandy.shopPrice)
        let s = try await store(tokens: 0, timeCredit: price)
        XCTAssertTrue(s.buy(.rareCandy))
        assertPaid(s, price)
    }

    func testMegaStone() async throws {
        let stone = try XCTUnwrap(MegaStone.all.first)
        let price = ShopEntry.megaStone(stone).price
        let short = try await store(tokens: price - 1)
        XCTAssertFalse(short.buy(stone))
        assertUntouched(short, wallet: price - 1)
        let s = try await store(tokens: price)
        XCTAssertTrue(s.buy(stone))
        assertPaid(s, price)
        XCTAssertEqual(s.state.inventory[stone.inventoryKey], 1)
    }

    func testMachine() async throws {
        let move = try XCTUnwrap(MachineCatalog.moves.first)
        let price = PokemonBalance.machinePrice(power: move.power, isWeather: move.isWeather)
        let short = try await store(tokens: price - 1)
        XCTAssertFalse(short.buyTM(moveID: move.id, power: move.power, isWeather: move.isWeather))
        assertUntouched(short, wallet: price - 1)
        let s = try await store(tokens: price)
        XCTAssertTrue(s.buyTM(moveID: move.id, power: move.power, isWeather: move.isWeather))
        assertPaid(s, price)
        XCTAssertTrue(s.ownsTM(move.id))
    }

    func testScoutTicket() async throws {
        let pool = try XCTUnwrap(ScoutPool.all.first)
        let short = try await store(tokens: ScoutTicket.price - 1)
        XCTAssertFalse(short.buyScoutTicket(pool))
        assertUntouched(short, wallet: ScoutTicket.price - 1)
        let s = try await store(tokens: ScoutTicket.price)
        XCTAssertTrue(s.buyScoutTicket(pool))
        assertPaid(s, ScoutTicket.price)
        XCTAssertEqual(s.state.inventory[pool.inventoryKey], 1)
    }

    func testEggForEveryShopTier() async throws {
        for tier in FreshEgg.shopTiers {
            let price = ShopEntry.egg(tier).price
            let short = try await store(tokens: price - 1)
            XCTAssertFalse(short.buyEgg(tier), "\(String(describing: tier))")
            assertUntouched(short, wallet: price - 1)
            XCTAssertTrue(short.hasActive)
            let s = try await store(tokens: price)
            XCTAssertTrue(s.buyEgg(tier), "\(String(describing: tier))")
            assertPaid(s, price)
            XCTAssertTrue(s.isEgg)
            XCTAssertEqual(s.state.eggTier, tier)
        }
    }

    // MARK: Training items bought on the spot

    func testMintBoughtOnTheSpot() async throws {
        let price = try XCTUnwrap(ItemKind.mint.shopPrice)
        let short = try await store(tokens: price - 1)
        XCTAssertEqual(short.changeNature(of: TrainingFixture.activeID, to: .timid), .short)
        assertUntouched(short, wallet: price - 1)
        XCTAssertEqual(short.trainable(id: TrainingFixture.activeID)?.nature, .adamant)
        let s = try await store(tokens: price)
        XCTAssertEqual(s.changeNature(of: TrainingFixture.activeID, to: .timid), .changed)
        assertPaid(s, price)
        XCTAssertEqual(s.trainable(id: TrainingFixture.activeID)?.nature, .timid)
    }

    func testMintFromTheBagSpendsNoTokens() async throws {
        let s = try await store(tokens: 0, inventory: ["mint": 1])
        XCTAssertEqual(s.changeNature(of: TrainingFixture.activeID, to: .timid), .changed)
        XCTAssertEqual(s.state.spentTokens, 0)
        XCTAssertEqual(s.itemCount(.mint), 0)
    }

    func testMirrorHerbBoughtOnTheSpot() async throws {
        let price = try XCTUnwrap(ItemKind.mirrorHerb.shopPrice)
        let pikachu = TrainingFixture.graduate("pikachu", speciesID: 25)
        let short = try await store(tokens: price - 1, dex: [pikachu])
        XCTAssertEqual(short.useMirrorHerb(on: "pikachu"), .short)
        assertUntouched(short, wallet: price - 1)
        let s = try await store(tokens: price, dex: [pikachu])
        XCTAssertEqual(s.useMirrorHerb(on: "pikachu"), .changed)
        assertPaid(s, price)
        XCTAssertEqual(s.trainable(id: "pikachu")?.profile.mirrorHerb, true)
    }

    func testMirrorHerbFromTheBagSpendsNoTokens() async throws {
        let s = try await store(tokens: 0, inventory: ["mirrorHerb": 1], dex: [TrainingFixture.graduate("pikachu", speciesID: 25)])
        XCTAssertEqual(s.useMirrorHerb(on: "pikachu"), .changed)
        XCTAssertEqual(s.state.spentTokens, 0)
    }

    // MARK: Undo and remote buys

    func testUndoGivesTheExactCostBack() async throws {
        let price = try XCTUnwrap(ItemKind.rareCandy.shopPrice) * 2
        let s = try await store(tokens: price)
        XCTAssertTrue(s.buy(.rareCandy, count: 2))
        let receipt = try XCTUnwrap(s.purchaseReceipts[ItemKind.rareCandy.rawValue])
        XCTAssertTrue(s.undoPurchase(receipt))
        assertUntouched(s, wallet: price)
    }

    func testRemoteScoutTicketsAreAllOrNothing() async throws {
        let pool = try XCTUnwrap(ScoutPool.all.first)
        let short = try await store(tokens: ScoutTicket.price * 3 - 1)
        XCTAssertFalse(short.buyFromShop(pool.inventoryKey, count: 3))
        assertUntouched(short, wallet: ScoutTicket.price * 3 - 1)
        let s = try await store(tokens: ScoutTicket.price * 3)
        XCTAssertTrue(s.buyFromShop(pool.inventoryKey, count: 3))
        assertPaid(s, ScoutTicket.price * 3)
        XCTAssertEqual(s.state.inventory[pool.inventoryKey], 3)
        XCTAssertTrue(s.purchaseReceipts.isEmpty)
    }

    func testRemoteItemBuyPaysThePriceTimesTheCount() async throws {
        let price = try XCTUnwrap(ItemKind.rareCandy.shopPrice) * 2
        let short = try await store(tokens: price - 1)
        XCTAssertFalse(short.buyFromShop(ItemKind.rareCandy.rawValue, count: 2))
        assertUntouched(short, wallet: price - 1)
        let s = try await store(tokens: price)
        XCTAssertTrue(s.buyFromShop(ItemKind.rareCandy.rawValue, count: 2))
        assertPaid(s, price)
    }
}
