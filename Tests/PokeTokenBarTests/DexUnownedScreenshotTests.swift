import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private func fixture(_ id: Int, _ ko: String, _ en: String, _ types: [String], capture: Int = 255,
                     from parent: Int? = nil) -> SpeciesIndexEntry {
    SpeciesIndexEntry(id: id, names: ["ko": ko, "en": en], types: types, captureRate: capture,
                      isLegendary: false, isMythical: false, evolvesFromID: parent)
}

private struct SyntheticIndexProvider: PokeProviding, SpeciesIndexProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func speciesIndex() async throws -> SpeciesIndex {
        SpeciesIndex(entries: [
            fixture(13, "뿔충이", "Weedle", ["bug", "poison"]),
            fixture(129, "잉어킹", "Magikarp", ["water"]),
            fixture(130, "갸라도스", "Gyarados", ["water", "flying"], from: 129),
            fixture(131, "라프라스", "Lapras", ["water", "ice"], capture: 45),
            fixture(132, "메타몽", "Ditto", ["normal"], capture: 35),
            fixture(133, "이브이", "Eevee", ["normal"], capture: 45),
            fixture(134, "샤미드", "Vaporeon", ["water"], capture: 45, from: 133),
            fixture(135, "쥬피썬더", "Jolteon", ["electric"], capture: 45, from: 133),
            fixture(136, "부스터", "Flareon", ["fire"], capture: 45, from: 133),
            fixture(137, "폴리곤", "Porygon", ["normal"], capture: 45),
            fixture(138, "암나이트", "Omanyte", ["rock", "water"], capture: 45),
            fixture(139, "암스타", "Omastar", ["rock", "water"], capture: 45, from: 138),
        ])
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
        let evolved = try XCTUnwrap(store.unownedDexSpecies.first { $0.id == 135 })
        try await capture(UnownedSpeciesDetailView(store: store, species: evolved, onOpen: { _ in }, onBack: {}),
                          to: directory.appendingPathComponent("dexsearch-detail-evolve.png"))
        let hatch = try XCTUnwrap(store.unownedDexSpecies.first { $0.id == 131 })
        try await capture(UnownedSpeciesDetailView(store: store, species: hatch, onOpen: { _ in }, onBack: {}),
                          to: directory.appendingPathComponent("dexsearch-detail-egg.png"))
    }

    private func capture<V: View>(_ view: V, to file: URL) async throws {
        let size = NSSize(width: PopoverMetrics.contentWidth, height: 520)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .environment(\.locale, AppLanguage.ko.displayLocale))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .seconds(6))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: file)
    }
}
