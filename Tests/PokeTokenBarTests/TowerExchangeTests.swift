import XCTest
@testable import PokeTokenBar

private struct ExchangeProvider: PokeProviding, SpeciesIndexProviding {
    static let ids = [25, 133, 144, 145, 146, 147, 150, 151]

    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func baseSpeciesIndex() async throws -> [BaseSpecies] {
        try Self.ids.map { BaseSpecies(id: $0, captureRate: try SpeciesFacts.indexEntry($0).captureRate) }
    }
    func speciesIndex() async throws -> SpeciesIndex {
        SpeciesIndex(entries: try Self.ids.map { try SpeciesFacts.indexEntry($0) })
    }
}

@MainActor
final class TowerExchangeTests: XCTestCase {
    private var scratch: URL!

    override func setUp() async throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("tower-exchange-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    private func store(bp: Int, dex: [DexEntry] = []) throws -> CompanionStore {
        var state = CompanionState()
        state.installBaselineSet = true
        state.tower.bp = bp
        state.dex = dex
        let file = scratch.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        return CompanionStore(provider: ExchangeProvider(), fileURL: file)
    }

    func testNoGoodTheTokenShopSellsIsCheaperInBP() throws {
        let store = try store(bp: 0, dex: [TowerFixtures.entry(6, id: "a"), TowerFixtures.entry(376, id: "b")])
        XCTAssertTrue(store.towerGoods.contains { if case .stone = $0 { true } else { false } })
        for good in store.towerGoods {
            let tokens: Int? = switch good {
            case .item(let kind): store.price(of: kind)
            case .stone(let stone): store.price(of: .megaStone(stone))
            case .legendaryScout: nil
            }
            let bp = try XCTUnwrap(store.bpPrice(of: good), "\(good) has no BP price")
            if let tokens { XCTAssertGreaterThanOrEqual(bp * 50_000, tokens, "\(good) undercuts its token price") }
        }
        XCTAssertEqual(TowerExchange.bp(forTokens: 50_001), 2)
    }

    func testMegaStonesOnSaleAreOnlyThoseOfSpeciesInTheBox() throws {
        let store = try store(bp: 0, dex: [TowerFixtures.entry(6, id: "a")])
        let stones = store.towerGoods.compactMap { if case .stone(let stone) = $0 { stone } else { nil } }
        XCTAssertEqual(Set(stones.map(\.speciesID)), [6])
    }

    func testAnExchangeSpendsBPNotTokensAndLeavesNoTokenReceipt() throws {
        let store = try store(bp: 250)
        let spent = store.state.spentTokens
        XCTAssertTrue(store.exchange(.item(.rareCandy)))
        XCTAssertEqual(store.itemCount(.rareCandy), 1)
        XCTAssertEqual(store.state.tower.bp, 250 - TowerExchange.bp(forTokens: RareCandy.price))
        XCTAssertEqual(store.state.spentTokens, spent)
        XCTAssertNil(store.purchaseReceipts[ItemKind.rareCandy.rawValue])
        let reloaded = CompanionStore(provider: ExchangeProvider(), fileURL: store.fileURL)
        XCTAssertEqual(reloaded.state.tower.bp, store.state.tower.bp)
    }

    func testAnExchangeShortOfBPOrForASecondMegaStoneIsRefused() throws {
        let stone = try XCTUnwrap(MegaStone.stones(for: 6).first)
        let store = try store(bp: TowerExchange.bp(forTokens: MegaStone.price) * 2, dex: [TowerFixtures.entry(6, id: "a")])
        XCTAssertTrue(store.exchange(.stone(stone)))
        XCTAssertFalse(store.exchange(.stone(stone)))
        let poor = try self.store(bp: TowerExchange.legendaryScoutBP - 1)
        XCTAssertFalse(poor.exchange(.legendaryScout))
        XCTAssertEqual(poor.state.tower.bp, TowerExchange.legendaryScoutBP - 1)
    }

    func testTheLegendaryScoutTicketIsNeverSoldForTokens() throws {
        XCTAssertFalse(ScoutPool.all.contains(.legendary))
        XCTAssertEqual(ScoutPool(key: "legendary"), .legendary)
        let store = try store(bp: 0)
        store.state.timeCredit = 10_000_000_000
        XCTAssertFalse(store.buyFromShop(ScoutPool.legendary.inventoryKey, count: 1))
        XCTAssertEqual(store.scoutTicketCount(.legendary), 0)
    }

    func testALegendaryScoutDrawsOnlyLegendaryAndMythicalBaseSpecies() async throws {
        let store = try store(bp: TowerExchange.legendaryScoutBP)
        XCTAssertTrue(store.exchange(.legendaryScout))
        XCTAssertEqual(store.ownedScoutTickets.map(\.pool), [.legendary])
        let draw = await store.drawScout(.legendary)
        let drawn = try XCTUnwrap(draw)
        XCTAssertEqual(Set(drawn), [144, 145, 146, 150, 151])
    }
}
