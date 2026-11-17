import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct ShopOnlyProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

private let thunderbolt = 85
private let iceBeam = 58
private let pikachu = 25

@MainActor
final class MachineShopTests: XCTestCase {
    private var scratch: URL!

    override func setUp() async throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("machine-shop-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    private func makeStore(tokens: Int = 1_000_000_000, owning species: [Int] = [pikachu]) throws -> CompanionStore {
        var state = CompanionState()
        state.language = .en
        state.installBaselineSet = true
        state.usedSinceInstall = tokens
        for id in species {
            var entry = DexEntry(baseID: id, finalID: id, chainOrder: [id], rarity: .common,
                                 caughtAt: Date(timeIntervalSince1970: 1_700_000_000),
                                 profile: PokemonProfile.generate(seed: UInt64(id), instanceID: "dex-\(id)"))
            entry.id = "dex-\(id)"
            state.dex.append(entry)
        }
        let file = scratch.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        return CompanionStore(provider: ShopOnlyProvider(), fileURL: file,
                              defaults: UserDefaults(suiteName: "machine-shop-\(UUID())")!)
    }

    private func ids(_ moves: [MachineEntry]) -> [Int] { moves.map(\.id) }

    func testTheCatalogCarriesEveryNameAndWhoLearnsIt() throws {
        let move = try XCTUnwrap(MachineCatalog.moves.first { $0.id == thunderbolt })
        XCTAssertEqual(move.type, "electric")
        XCTAssertEqual(move.power, 90)
        XCTAssertEqual(move.en, "Thunderbolt")
        XCTAssertEqual(move.name(.ko), "10만볼트")
        XCTAssertEqual(move.name(.ja), "１０まんボルト")
        XCTAssertEqual(move.name(.de), "Thunderbolt")
        XCTAssertGreaterThan(MachineCatalog.moves.count, 150)
        XCTAssertTrue(MachineCatalog.learnersBySpecies[pikachu]?.contains(thunderbolt) == true)
        XCTAssertFalse(MachineCatalog.learnersBySpecies[pikachu]?.contains(iceBeam) == true)
    }

    func testSearchMatchesEveryLanguageIgnoringCaseWidthKanaAndSpaces() throws {
        let store = try makeStore()
        XCTAssertTrue(ids(store.machineShopMoves(query: "thunderbolt")).contains(thunderbolt))
        XCTAssertTrue(ids(store.machineShopMoves(query: "THUNDER bolt")).contains(thunderbolt))
        XCTAssertTrue(ids(store.machineShopMoves(query: "10만")).contains(thunderbolt))
        XCTAssertTrue(ids(store.machineShopMoves(query: "10まんボルト")).contains(thunderbolt))
        XCTAssertTrue(ids(store.machineShopMoves(query: "ice beam")).contains(iceBeam))
        XCTAssertTrue(ids(store.machineShopMoves(query: "냉동빔")).contains(iceBeam))
        XCTAssertEqual(ids(store.machineShopMoves(query: "れいとうビーム")), [iceBeam])
        XCTAssertEqual(ids(store.machineShopMoves(query: "レイトウビーム")), [iceBeam])
        XCTAssertTrue(store.machineShopMoves(query: "no such move").isEmpty)
    }

    func testTheTypeFilterAndSearchNarrowTogether() throws {
        let store = try makeStore()
        let electric = store.machineShopMoves(type: "electric")
        XCTAssertTrue(electric.contains { $0.id == thunderbolt })
        XCTAssertTrue(electric.allSatisfy { $0.type == "electric" })
        XCTAssertEqual(ids(store.machineShopMoves(query: "punch", type: "ice")), [8])
    }

    func testLearnableOnlyKeepsMovesMyPokemonLearn() throws {
        let store = try makeStore()
        let learnable = Set(ids(store.machineShopMoves(learnableOnly: true)))
        XCTAssertEqual(learnable, MachineCatalog.learnersBySpecies[pikachu])
        let all = store.machineShopMoves(learnableOnly: false)
        XCTAssertGreaterThan(all.count, learnable.count)
        XCTAssertTrue(all.prefix(learnable.count).allSatisfy { learnable.contains($0.id) })
    }

    func testWithoutAPokemonNothingIsLearnable() throws {
        let store = try makeStore(owning: [])
        XCTAssertTrue(store.machineShopMoves(learnableOnly: true).isEmpty)
        XCTAssertFalse(store.machineShopMoves().isEmpty)
    }

    func testOwnedMovesSinkToTheBottomAndCheaperComesFirst() throws {
        let store = try makeStore()
        let before = store.machineShopMoves(learnableOnly: true)
        let prices = before.map { store.tmPrice(power: $0.power, isWeather: $0.isWeather) }
        XCTAssertEqual(prices, prices.sorted())
        let first = try XCTUnwrap(before.first)
        XCTAssertTrue(store.buyTM(moveID: first.id, power: first.power, isWeather: first.isWeather))
        XCTAssertEqual(store.machineShopMoves(learnableOnly: true).last?.id, first.id)
    }

    func testBuyingFromTheShopSpendsTheTierPriceOnceAndMarksItOwned() throws {
        let store = try makeStore()
        let move = try XCTUnwrap(MachineCatalog.moves.first { $0.id == thunderbolt })
        let before = store.availableTokens
        XCTAssertFalse(store.ownsTM(thunderbolt))
        XCTAssertTrue(store.buyTM(moveID: move.id, power: move.power, isWeather: move.isWeather))
        XCTAssertEqual(before - store.availableTokens, 80_000_000)
        XCTAssertTrue(store.ownsTM(thunderbolt))
        XCTAssertFalse(store.buyTM(moveID: move.id, power: move.power, isWeather: move.isWeather))
        XCTAssertEqual(before - store.availableTokens, 80_000_000)
    }

    func testABoughtTMCanBeTakenBackInsideTheUndoWindow() throws {
        let store = try makeStore()
        let move = try XCTUnwrap(MachineCatalog.moves.first { $0.id == thunderbolt })
        let before = store.availableTokens
        store.buyTM(moveID: move.id, power: move.power, isWeather: move.isWeather)
        let receipt = try XCTUnwrap(store.purchaseReceipts[MachineMove.inventoryKey(thunderbolt)])
        XCTAssertTrue(store.undoPurchase(receipt))
        XCTAssertFalse(store.ownsTM(thunderbolt))
        XCTAssertEqual(store.availableTokens, before)
    }

    func testWeatherMovesCostTheTopTier() throws {
        let store = try makeStore()
        let weather = MachineCatalog.moves.filter(\.isWeather)
        XCTAssertFalse(weather.isEmpty)
        for move in weather {
            XCTAssertEqual(store.tmPrice(power: move.power, isWeather: true), 120_000_000, move.en)
        }
    }

    func testTheTMCategoryIsAShopTabButNotInTheAllListOrTheBag() throws {
        let store = try makeStore()
        XCTAssertTrue(store.shopCategories.contains(.machine))
        XCTAssertFalse(store.shopEntries.contains { $0.category == .machine })
        XCTAssertTrue(store.shopEntries(in: .machine).isEmpty)
        XCTAssertFalse(store.bagCategories.contains(.machine))
        XCTAssertEqual(store.l.categoryName(.machine), "TM")
    }

    /// Opt-in PR screenshots from a synthetic save:
    ///
    ///     PTB_TM_SHOP_SCREENSHOT_DIR=/tmp/shots swift test --filter MachineShopTests/testCaptureTheTMShop
    func testCaptureTheTMShop() async throws {
        guard let path = ProcessInfo.processInfo.environment["PTB_TM_SHOP_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_TM_SHOP_SCREENSHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try makeStore(tokens: 3_000_000_000, owning: [pikachu, 143])
        let thunderboltEntry = try XCTUnwrap(MachineCatalog.moves.first { $0.id == thunderbolt })
        store.buyTM(moveID: thunderbolt, power: thunderboltEntry.power, isWeather: false)
        let nav = PopoverNavigation()
        let size = CGSize(width: PopoverMetrics.contentWidth, height: 520)
        func shot(_ name: String, language: AppLanguage, query: String = "") async throws {
            store.setLanguage(language)
            try await OffscreenRender.capture(
                ShopView(store: store, nav: nav, initialCategory: .machine, machineQuery: query)
                    .environment(store).frame(width: size.width, height: size.height)
                    .background(Color.white).environment(\.colorScheme, .light)
                    .environment(\.locale, language.displayLocale),
                size: size, appearance: .aqua, scale: 2,
                to: directory.appendingPathComponent(name))
        }
        try await shot("tm-shop-list.png", language: .en)
        try await shot("tm-shop-search.png", language: .en, query: "thunder")
        try await shot("tm-shop-search-ko.png", language: .ko, query: "빔")
    }

    func testTheShopRendersTheTMCategory() async throws {
        let store = try makeStore()
        let file = scratch.appendingPathComponent("tm-shop.png")
        let size = CGSize(width: PopoverMetrics.contentWidth, height: 520)
        let png = try await OffscreenRender.capture(
            ShopView(store: store, nav: PopoverNavigation(), initialCategory: .machine, machineQuery: "bolt")
                .environment(store).frame(width: size.width, height: size.height),
            size: size, appearance: .aqua, to: file)
        XCTAssertGreaterThan(png.count, 5_000)
    }
}
