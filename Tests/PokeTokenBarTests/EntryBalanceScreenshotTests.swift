import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct BalanceShotProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 4, tree: EvoNode(speciesID: 4, children: [EvoNode(speciesID: 5, children: [])]),
                rarity: .common, names: [4: ["en": "Charmander"], 5: ["en": "Charmeleon"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// Opt-in captures for the PR: the shop and the growth bar for the same synthetic save.
///
///     PTB_BALANCE_SHOT_DIR=/tmp/shots PTB_BALANCE_SHOT_TAG=after swift test --filter EntryBalanceScreenshotTests
@MainActor
final class EntryBalanceScreenshotTests: XCTestCase {
    func testCaptureShopAndGrowth() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_BALANCE_SHOT_DIR"] else {
            throw XCTSkip("Set PTB_BALANCE_SHOT_DIR to write the PR screenshots")
        }
        let tag = ProcessInfo.processInfo.environment["PTB_BALANCE_SHOT_TAG"] ?? "after"
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("balance-shot-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        var state = CompanionState()
        state.language = .en
        state.installBaselineSet = true
        state.usedSinceInstall = 400_000_000
        state.active = MonState(baseID: 4, pathIDs: [4], plannedPathIDs: [4, 5], stageIndex: 0,
                                usedAtStage: 40_000_000, rarity: .common, totalForms: 2,
                                profile: PokemonProfile.generate(seed: 5, instanceID: "raised"))
        let file = scratch.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let suite = try XCTUnwrap(UserDefaults(suiteName: "balance-shot-\(UUID())"))
        let store = CompanionStore(provider: BalanceShotProvider(), fileURL: file, defaults: suite)
        let sprites = SpriteStore(directory: scratch.appendingPathComponent("sprites"))

        try await capture(ShopView(store: store, nav: PopoverNavigation()).environment(store), height: 520,
                          to: directory.appendingPathComponent("entry-balance-shop-\(tag).png"))
        try await capture(CompanionHeader(store: store, spriteStore: sprites).padding(12), height: 300,
                          to: directory.appendingPathComponent("entry-balance-growth-\(tag).png"))
    }

    private func capture<V: View>(_ view: V, height: CGFloat, to file: URL) async throws {
        let size = NSSize(width: PopoverMetrics.contentWidth, height: height)
        try await OffscreenRender.capture(view.frame(width: size.width, height: size.height)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .environment(\.locale, AppLanguage.en.displayLocale),
            size: size, appearance: .aqua, to: file)
    }
}
