import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct ScoutShotProvider: PokeProviding, SpeciesIndexProviding {
    static let picks: [(id: Int, ko: String, en: String, types: [String], capture: Int, legendary: Bool)] = [
        (4, "파이리", "Charmander", ["fire"], 45, false),
        (7, "꼬부기", "Squirtle", ["water"], 45, false),
        (23, "아보", "Ekans", ["poison"], 255, false),
        (37, "식스테일", "Vulpix", ["fire"], 190, false),
        (43, "뚜벅쵸", "Oddish", ["grass", "poison"], 255, false),
        (74, "꼬마돌", "Geodude", ["rock", "ground"], 255, false),
        (92, "고오스", "Gastly", ["ghost", "poison"], 190, false),
        (129, "잉어킹", "Magikarp", ["water"], 255, false),
        (147, "미뇽", "Dratini", ["dragon"], 45, false),
        (150, "뮤츠", "Mewtwo", ["psychic"], 3, true),
    ]
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { Self.picks.map { BaseSpecies(id: $0.id, captureRate: $0.capture) } }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func speciesIndex() async throws -> SpeciesIndex {
        SpeciesIndex(entries: Self.picks.map {
            SpeciesIndexEntry(id: $0.id, names: ["ko": $0.ko, "en": $0.en], types: $0.types,
                              captureRate: $0.capture, isLegendary: $0.legendary, isMythical: false, evolvesFromID: nil)
        })
    }
}

/// Opt-in captures for the PR: a synthetic save, the real views.
///
///     PTB_SCOUT_SCREENSHOT_DIR=/tmp/shots swift test --filter ScoutScreenshotTests
@MainActor
final class ScoutScreenshotTests: XCTestCase {
    private func owned(_ species: Int, ko: String, en: String, rarity: Rarity) -> DexEntry {
        var entry = DexEntry(baseID: species, finalID: species, chainOrder: [species], rarity: rarity,
                             caughtAt: Date(timeIntervalSince1970: 1_700_000_000), isShiny: false,
                             profile: PokemonProfile.generate(seed: UInt64(species), instanceID: "s\(species)"),
                             names: [species: ["ko": ko, "en": en]])
        entry.id = "s\(species)"
        return entry
    }

    func testCaptureShopSectionAndScoutSheet() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_SCOUT_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_SCOUT_SCREENSHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("scout-shot-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        var state = CompanionState()
        state.language = .ko
        state.installBaselineSet = true
        state.usedSinceInstall = 80_000_000_000
        state.inventory = ["scout.kanto": 1, "scout.national": 2]
        state.scoutDraws = ["kanto": ScoutShotProvider.picks.map(\.id)]
        state.active = MonState(baseID: 10, pathIDs: [10], stageIndex: 0, usedAtStage: 0,
                                rarity: .common, totalForms: 3)
        // Everything but Dratini is already in the dex, so exactly one pick carries the "not owned" badge.
        state.dex = ScoutShotProvider.picks.filter { $0.id != 147 }.map {
            owned($0.id, ko: $0.ko, en: $0.en, rarity: Rarity.from(captureRate: $0.capture, isLegendary: $0.legendary, isMythical: false))
        }
        let file = scratch.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let defaults = UserDefaults(suiteName: "scout-shot-\(UUID())")!
        let store = CompanionStore(provider: ScoutShotProvider(), fileURL: file, defaults: defaults)
        await store.loadSpeciesIndexIfNeeded()
        let nav = PopoverNavigation()

        try await capture(ScrollView { ShopScoutSection(store: store).reservesScrollerLane() }
            .frame(height: 560), height: 560, to: directory.appendingPathComponent("shop-scout-section.png"))
        try await capture(BagView(store: store, nav: nav), height: 520,
                          to: directory.appendingPathComponent("bag-scout-tickets.png"))
        try await capture(ScoutPickerView(store: store, pool: .region(.kanto), onPicked: {}, onBack: {}),
                          height: 520, to: directory.appendingPathComponent("scout-sheet.png"))
    }

    private func capture<V: View>(_ view: V, height: CGFloat, to file: URL) async throws {
        let size = NSSize(width: PopoverMetrics.contentWidth, height: height)
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
