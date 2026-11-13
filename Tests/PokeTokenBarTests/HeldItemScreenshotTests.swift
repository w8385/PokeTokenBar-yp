import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct HeldShotProvider: PokeProviding, PokemonDetailProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 4, tree: EvoNode(speciesID: 4, children: [EvoNode(speciesID: 5, children: [])]),
                rarity: .common, names: [4: ["ko": "파이리"], 5: ["ko": "리자드"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        PokemonDetails(speciesID: speciesID, name: "synthetic", height: 10, weight: 60,
            baseExperience: 112, genderRate: 4, types: ["electric"],
            baseStats: ["hp": 35, "attack": 55, "defense": 40, "special-attack": 50, "special-defense": 50, "speed": 90],
            abilities: [], moves: [])
    }
}

private let heldMovesJSON = """
{"moves":[
 {"id":85,"name":"10만볼트","type":"electric","power":90,"damage_class":"special","accuracy":100,"level":26,"pp":15},
 {"id":98,"name":"전광석화","type":"normal","power":40,"damage_class":"physical","accuracy":100,"level":10,"pp":30}
],"default":[85,98]}
"""

/// Opt-in captures for the PR: a synthetic save, the real views.
///
///     PTB_HELD_SCREENSHOT_DIR=/tmp/shots swift test --filter HeldItemScreenshotTests
@MainActor
final class HeldItemScreenshotTests: XCTestCase {
    func testCaptureShopAndBattleTab() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_HELD_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_HELD_SCREENSHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("held-shot-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        var state = CompanionState()
        state.language = .ko
        state.installBaselineSet = true
        state.usedSinceInstall = 9_000_000_000
        state.active = MonState(baseID: 4, pathIDs: [4, 5], stageIndex: 0, usedAtStage: 0,
                                rarity: .common, totalForms: 2,
                                profile: PokemonProfile.generate(seed: 5, instanceID: "raised"))
        var pikachuProfile = PokemonProfile.generate(seed: 25, instanceID: "pikachu")
        pikachuProfile.level = 42
        var pikachu = DexEntry(baseID: 25, finalID: 25, chainOrder: [25], rarity: .rare,
                               caughtAt: Date(timeIntervalSince1970: 1_700_000_000), profile: pikachuProfile,
                               names: [25: ["ko": "피카츄", "en": "Pikachu"]])
        pikachu.id = "pikachu"
        state.dex = [pikachu]
        state.inventory = ["leftovers": 1, "focusSash": 1, "lifeOrb": 1]
        state.heldItems = ["pikachu": "choiceScarf"]
        let file = scratch.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: HeldShotProvider(), fileURL: file)
        await store.loadPokemonDetails(speciesID: 25)

        let defaults = UserDefaults(suiteName: "held-shot-\(UUID())")!
        let battle = BattleEntryStore(defaults: defaults)
        battle.choose("pikachu")
        let uploader = PartyUploader(
            tokenStore: PartyTokenStore(fileURL: scratch.appendingPathComponent("token")), defaults: defaults,
            appVersion: "shot", send: { _ in 200 },
            fetch: { _ in (Data(heldMovesJSON.utf8), 200) }, partySource: { [] })
        uploader.saveToken("synthetic-token")
        uploader.serverURL = "http://bot-host:8790"
        let nav = PopoverNavigation()

        try await capture(ShopView(store: store, nav: nav, initialCategory: ItemCategory.heldItem).environment(store),
                          to: directory.appendingPathComponent("shop-held-items.png"))
        try await capture(BattleView(store: store, navigation: nav, initialPickerQuery: "")
            .environment(uploader).environment(battle).environment(store),
                          to: directory.appendingPathComponent("battle-tab-held-item.png"))
    }

    private func capture<V: View>(_ view: V, to file: URL) async throws {
        let size = NSSize(width: PopoverMetrics.contentWidth, height: 620)
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
        try await Task.sleep(for: .seconds(5))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: file)
    }
}
