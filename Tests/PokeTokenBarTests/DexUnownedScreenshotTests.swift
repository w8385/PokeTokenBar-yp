import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct SyntheticIndexProvider: PokeProviding, SpeciesIndexProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func speciesIndex() async throws -> SpeciesIndex {
        SpeciesIndex(entries: try [13, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139].map {
            try SpeciesFacts.indexEntry($0)
        })
    }
}

/// Opt-in captures for the PR: synthetic save and index, real views.
///
///     PTB_DEXSEARCH_SCREENSHOT_DIR=/tmp/shots swift test --filter DexUnownedScreenshotTests
@MainActor
final class DexUnownedScreenshotTests: XCTestCase {
    func testCaptureSearchResultsAndDetailPages() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_DEXSEARCH_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_DEXSEARCH_SCREENSHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("dexsearch-shot-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        var state = CompanionState()
        state.language = .ko
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        state.dex = [
            DexEntry(baseID: 129, finalID: 130, chainOrder: [129, 130], rarity: .common, caughtAt: when,
                     names: [129: ["ko": "잉어킹"], 130: ["ko": "갸라도스"]]),
            DexEntry(baseID: 133, finalID: 133, chainOrder: [133], rarity: .rare, caughtAt: when,
                     names: [133: ["ko": "이브이"]]),
            DexEntry(baseID: 133, finalID: 134, chainOrder: [133, 134], rarity: .rare, caughtAt: when,
                     names: [133: ["ko": "이브이"], 134: ["ko": "샤미드"]]),
        ]
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: SyntheticIndexProvider(), fileURL: file)
        await store.loadSpeciesIndexIfNeeded()

        try await capture(CollectionView(store: store, navigation: PopoverNavigation(), initialSearch: "13"),
                          to: directory.appendingPathComponent("dexsearch-results.png"))
        try await capture(CollectionView(store: store, navigation: PopoverNavigation()),
                          to: directory.appendingPathComponent("dexfilter-off.png"))
        try await capture(CollectionView(store: store, navigation: PopoverNavigation(), initialIncludeUnowned: true),
                          to: directory.appendingPathComponent("dexfilter-on.png"))
        let evolved = try XCTUnwrap(store.unownedDexSpecies.first { $0.id == 135 })
        try await capture(UnownedSpeciesDetailView(store: store, species: evolved, onOpen: { _ in }, onBack: {}),
                          to: directory.appendingPathComponent("dexsearch-detail-evolve.png"))
        let hatch = try XCTUnwrap(store.unownedDexSpecies.first { $0.id == 131 })
        try await capture(UnownedSpeciesDetailView(store: store, species: hatch, onOpen: { _ in }, onBack: {}),
                          to: directory.appendingPathComponent("dexsearch-detail-egg.png"))
    }

    private func capture<V: View>(_ view: V, to file: URL) async throws {
        let size = NSSize(width: PopoverMetrics.contentWidth, height: 520)
        try await OffscreenRender.capture(view.frame(width: size.width, height: size.height)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .environment(\.locale, AppLanguage.ko.displayLocale),
            size: size, appearance: .aqua, settle: .seconds(6), to: file)
    }
}
