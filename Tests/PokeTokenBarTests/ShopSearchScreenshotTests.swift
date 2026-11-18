import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct SearchShotProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 4, tree: EvoNode(speciesID: 4, children: [EvoNode(speciesID: 5, children: [])]),
                rarity: .common, names: [4: ["ko": "파이리"], 5: ["ko": "리자드"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// Opt-in captures for the PR: a synthetic save, the real shop view.
///
///     PTB_SHOP_SEARCH_SHOT_DIR=/tmp/shots swift test --filter ShopSearchScreenshotTests
@MainActor
final class ShopSearchScreenshotTests: XCTestCase {
    func testCaptureShopSearchAndSubTabs() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_SHOP_SEARCH_SHOT_DIR"] else {
            throw XCTSkip("Set PTB_SHOP_SEARCH_SHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (language, query) in [(AppLanguage.ko, "life orb"), (.en, "orb")] {
            let store = try makeStore(language)
            let tag = language.rawValue
            try await capture(ShopView(store: store, nav: PopoverNavigation(), searchQuery: query), language,
                              to: directory.appendingPathComponent("after-shop-search-\(tag).png"))
            try await capture(ShopView(store: store, nav: PopoverNavigation(), initialCategory: .heldItem, heldGroup: .bulk),
                              language, to: directory.appendingPathComponent("after-shop-held-bulk-\(tag).png"))
            try await capture(ShopView(store: store, nav: PopoverNavigation(), initialCategory: .heldItem), language,
                              to: directory.appendingPathComponent("after-shop-held-\(tag).png"))
            try await capture(ShopView(store: store, nav: PopoverNavigation(), searchQuery: "zzqxv"), language,
                              to: directory.appendingPathComponent("after-shop-search-empty-\(tag).png"))
            try await capture(ShopView(store: store, nav: PopoverNavigation()), language,
                              to: directory.appendingPathComponent("after-shop-all-\(tag).png"))
        }
    }

    private func makeStore(_ language: AppLanguage) throws -> CompanionStore {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("shop-search-shot-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: scratch) }
        var state = CompanionState()
        state.language = language
        state.installBaselineSet = true
        state.usedSinceInstall = 9_000_000_000
        state.active = MonState(baseID: 4, pathIDs: [4, 5], stageIndex: 0, usedAtStage: 0,
                                rarity: .common, totalForms: 2,
                                profile: PokemonProfile.generate(seed: 5, instanceID: "raised"))
        state.inventory = ["rareCandy": 2, "mint": 1]
        let file = scratch.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        return CompanionStore(provider: SearchShotProvider(), fileURL: file,
                              defaults: UserDefaults(suiteName: "shop-search-shot-\(UUID())")!)
    }

    private func capture<V: View>(_ view: V, _ language: AppLanguage, to file: URL) async throws {
        let size = NSSize(width: PopoverMetrics.contentWidth, height: 520)
        try await OffscreenRender.capture(view.frame(width: size.width, height: size.height)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .environment(\.locale, language.displayLocale),
            size: size, appearance: .aqua, scale: 2, to: file)
    }
}
