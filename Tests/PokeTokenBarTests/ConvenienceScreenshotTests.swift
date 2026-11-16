import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// Opt-in captures for the PR: a synthetic save, the real views.
///
///     PTB_CONVENIENCE_SCREENSHOT_DIR=/tmp/shots swift test --filter ConvenienceScreenshotTests
@MainActor
final class ConvenienceScreenshotTests: XCTestCase {
    private struct Provider: PokeProviding, PokemonDetailProviding {
        func line(baseSpeciesID: Int) async throws -> EvoLine { try await BoxDexProvider().line(baseSpeciesID: baseSpeciesID) }
        func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
        func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
        func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
            try SpeciesFacts.details(speciesID)
        }
    }

    func testCaptureShopUndoAndBoxFilterMenu() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_CONVENIENCE_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_CONVENIENCE_SCREENSHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("convenience-shot-\(UUID()).json")
        try JSONEncoder().encode(BoxDexFixture.state(language: .ko)).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let store = CompanionStore(provider: Provider(), fileURL: file)
        for id in [25, 6, 95, 133] { await store.loadPokemonDetails(speciesID: id) }

        let shopFirst = try XCTUnwrap(store.shopEntries(in: nil).compactMap { entry -> ItemKind? in
            if case .item(let kind) = entry, store.canBuy(kind) { return kind } else { return nil }
        }.first)
        XCTAssertTrue(store.buy(shopFirst))
        try await capture(ShopView(store: store, nav: PopoverNavigation()),
                          to: directory.appendingPathComponent("convenience-shop-after-buy.png"))

        let stone = try XCTUnwrap(MegaStone.all.first { store.canBuy($0) })
        XCTAssertTrue(store.buy(stone))
        try await capture(ShopView(store: store, nav: PopoverNavigation(), initialCategory: .megaStone),
                          to: directory.appendingPathComponent("convenience-shop-megastone-after-buy.png"))

        let defaults = try XCTUnwrap(UserDefaults(suiteName: "convenience-shot-\(UUID())"))
        let navigation = PopoverNavigation(boxFilters: BoxFilterStore(defaults: defaults))
        navigation.tab = .box
        var filter = BoxFilter()
        filter.types = [.fire, .electric]
        filter.rarity = .rare
        filter.level = .underFifty
        navigation.boxFilters.filter = filter
        let battle = BattleEntryStore(defaults: defaults)
        battle.add(BoxDexFixture.pikachuID)
        try await capture(BoxView(store: store, navigation: navigation, filtersOpen: true)
            .environment(battle).environment(store),
                          to: directory.appendingPathComponent("convenience-box-filter-menu.png"))
    }

    private func capture<V: View>(_ view: V, to file: URL) async throws {
        let size = NSSize(width: PopoverMetrics.contentWidth, height: 520)
        try await OffscreenRender.capture(view.frame(width: size.width, height: size.height)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .environment(\.locale, AppLanguage.ko.displayLocale),
            size: size, appearance: .aqua, scale: 2, settle: .seconds(2), to: file)
    }
}
