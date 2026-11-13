import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct GhostProvider: PokeProviding, PokemonDetailProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 92, tree: EvoNode(speciesID: 92, children: [
            EvoNode(speciesID: 93, children: [
                EvoNode(speciesID: 94, children: [], methods: [EvoMethod(trigger: "trade", item: nil)])],
                    methods: [EvoMethod(trigger: "level-up", item: nil)])]),
                rarity: .rare, names: [92: ["ko": "고오스"], 93: ["ko": "고우스트"], 94: ["ko": "팬텀"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        PokemonDetails(speciesID: speciesID, name: "synthetic", height: 10, weight: 295,
            baseExperience: 142, genderRate: 4, types: ["ghost", "poison"],
            baseStats: ["hp": 60, "attack": 65, "defense": 60, "special-attack": 130, "special-defense": 75, "speed": 110],
            abilities: [], moves: [])
    }
}

/// Opt-in captures of screens that exist before and after the trade feature, for the PR's before/after pairs.
///
///     PTB_TRADE_BASELINE_DIR=/tmp/shots swift test --filter TradeBeforeAfterShotTests
@MainActor
final class TradeBeforeAfterShotTests: XCTestCase {
    func testCaptureBattleTabDexDetailAndShop() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_TRADE_BASELINE_DIR"] else {
            throw XCTSkip("Set PTB_TRADE_BASELINE_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("trade-base-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        var state = CompanionState()
        state.language = .ko
        state.installBaselineSet = true
        state.usedSinceInstall = 6_000_000_000
        var raised = PokemonProfile.generate(seed: 5, instanceID: "raised")
        raised.level = 24
        state.active = MonState(baseID: 4, pathIDs: [4, 5, 6], stageIndex: 1, usedAtStage: 0,
                                rarity: .common, totalForms: 3, profile: raised)
        var haunter = PokemonProfile.generate(seed: 93, instanceID: "haunter")
        haunter.level = 41
        state.dex = [DexEntry(id: "haunter", baseID: 92, finalID: 93, chainOrder: [92, 93], rarity: .rare,
                              caughtAt: Date(timeIntervalSince1970: 1_700_000_000), nature: .adamant,
                              profile: haunter, names: [93: ["ko": "고우스트"]])]
        let file = scratch.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: GhostProvider(), fileURL: file, dittoDisguiseRollingEnabled: false)
        await store.loadPokemonDetails(speciesID: 93)

        let defaults = UserDefaults(suiteName: "trade-base-\(UUID())")!
        let battle = BattleEntryStore(defaults: defaults)
        let uploader = PartyUploader(
            tokenStore: PartyTokenStore(fileURL: scratch.appendingPathComponent("token")), defaults: defaults,
            appVersion: "shot", fetch: { _ in (Data(), 200) }, partySource: { [] })
        uploader.saveToken("synthetic-token")
        uploader.serverURL = "http://bot-host:8790"

        try await capture(BattleView(store: store, navigation: PopoverNavigation(), initialPickerQuery: "")
            .environment(uploader).environment(battle).environment(store),
                          to: directory.appendingPathComponent("battle-tab.png"))
        let species = try XCTUnwrap(store.dexSpecies.first { $0.id == 93 })
        try await capture(PokemonDetailView(store: store, species: species, onBack: {})
            .environment(uploader).environment(battle).environment(store).environment(PopoverNavigation()),
                          to: directory.appendingPathComponent("dex-detail.png"))
        try await capture(ShopView(store: store, nav: PopoverNavigation()), scrollToBottom: true,
                          to: directory.appendingPathComponent("shop-bottom.png"))
    }

    private func capture<V: View>(_ view: V, scrollToBottom: Bool = false, to file: URL) async throws {
        let size = NSSize(width: PopoverMetrics.contentWidth, height: 520)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height, alignment: .top)
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
        try await Task.sleep(for: .seconds(5))
        host.layoutSubtreeIfNeeded()
        if scrollToBottom, let scroll = Self.scrollView(in: host), let doc = scroll.documentView {
            doc.scroll(NSPoint(x: 0, y: max(0, doc.bounds.height - size.height)))
            scroll.reflectScrolledClipView(scroll.contentView)
            try await Task.sleep(for: .seconds(1))
        }
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: file)
    }

    private static func scrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for sub in view.subviews { if let found = scrollView(in: sub) { return found } }
        return nil
    }
}
