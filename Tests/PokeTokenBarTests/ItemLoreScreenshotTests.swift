import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct LoreShotProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 4, tree: EvoNode(speciesID: 4, children: [EvoNode(speciesID: 5, children: [])]),
                rarity: .common, names: [4: ["ko": "파이리"], 5: ["ko": "리자드"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// Opt-in captures for the PR: a synthetic save, the real shop and bag views.
///
///     PTB_ITEM_LORE_SCREENSHOT_DIR=/tmp/shots swift test --filter ItemLoreScreenshotTests
@MainActor
final class ItemLoreScreenshotTests: XCTestCase {
    func testCaptureShopAndBag() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_ITEM_LORE_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_ITEM_LORE_SCREENSHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("lore-shot-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        for language in [AppLanguage.ko, .en] {
            var state = CompanionState()
            state.language = language
            state.installBaselineSet = true
            state.usedSinceInstall = 9_000_000_000
            state.active = MonState(baseID: 4, pathIDs: [4, 5], stageIndex: 0, usedAtStage: 0,
                                    rarity: .common, totalForms: 2,
                                    profile: PokemonProfile.generate(seed: 5, instanceID: "raised"))
            state.inventory = ["rareCandy": 3, "fireStone": 1, "leftovers": 1, "shinyCharm": 1, "linkingCord": 1, "scout.national": 1]
            let file = scratch.appendingPathComponent("state-\(language.rawValue).json")
            try JSONEncoder().encode(state).write(to: file)
            let store = CompanionStore(provider: LoreShotProvider(), fileURL: file)
            let nav = PopoverNavigation()

            try await capture(ShopView(store: store, nav: nav, initialCategory: ItemCategory.growth).environment(store),
                              language: language, to: directory.appendingPathComponent("shop-growth-\(language.rawValue).png"))
            try await capture(ShopView(store: store, nav: nav, initialCategory: ItemCategory.heldItem).environment(store),
                              language: language, to: directory.appendingPathComponent("shop-held-\(language.rawValue).png"))
            try await capture(BagView(store: store, nav: nav).environment(store),
                              language: language, to: directory.appendingPathComponent("bag-\(language.rawValue).png"))
        }
    }

    private func capture<V: View>(_ view: V, language: AppLanguage, to file: URL) async throws {
        let size = NSSize(width: PopoverMetrics.contentWidth, height: 520)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .environment(\.locale, language.displayLocale))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .seconds(4))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: file)
    }
}
