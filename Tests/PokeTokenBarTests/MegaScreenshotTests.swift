import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct MegaShotProvider: PokeProviding, PokemonDetailProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 4,
                tree: EvoNode(speciesID: 4, children: [EvoNode(speciesID: 5, children: [EvoNode(speciesID: 6, children: [])])]),
                rarity: .common, names: [4: ["ko": "파이리"], 5: ["ko": "리자드"], 6: ["ko": "리자몽"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        PokemonDetails(speciesID: speciesID, name: "synthetic", height: 17, weight: 905,
            baseExperience: 267, genderRate: 1, types: ["fire", "flying"],
            baseStats: ["hp": 78, "attack": 84, "defense": 78, "special-attack": 109, "special-defense": 85, "speed": 100],
            abilities: [], moves: [])
    }
}

private let megaMovesJSON = """
{"moves":[
 {"id":53,"name":"화염방사","type":"fire","power":90,"damage_class":"special","accuracy":100,"level":46,"pp":15},
 {"id":403,"name":"공중날기","type":"flying","power":75,"damage_class":"physical","accuracy":95,"level":36,"pp":15}
],"default":[53,403]}
"""

/// Opt-in captures for the PR: a synthetic save, the real views.
///
///     PTB_MEGA_SCREENSHOT_DIR=/tmp/shots swift test --filter MegaScreenshotTests
@MainActor
final class MegaScreenshotTests: XCTestCase {
    func testCaptureShopBattleAndHome() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_MEGA_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_MEGA_SCREENSHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("mega-shot-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let stone = try XCTUnwrap(MegaStone.stone(slug: "charizardite-x"))
        var state = CompanionState()
        state.language = .ko
        state.installBaselineSet = true
        state.usedSinceInstall = 9_000_000_000
        state.active = MonState(baseID: 4, pathIDs: [4, 5, 6], stageIndex: 2, usedAtStage: 0,
                                rarity: .common, totalForms: 3,
                                profile: PokemonProfile.generate(seed: 5, instanceID: "raised"))
        var profile = PokemonProfile.generate(seed: 6, instanceID: "zard")
        profile.level = 60
        var charizard = DexEntry(baseID: 4, finalID: 6, chainOrder: [4, 5, 6], rarity: .common,
                                 caughtAt: Date(timeIntervalSince1970: 1_700_000_000), profile: profile,
                                 names: [6: ["ko": "리자몽", "en": "Charizard"]])
        charizard.id = "zard"
        state.dex = [charizard]
        state.inventory = [stone.inventoryKey: 2]
        let file = scratch.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: MegaShotProvider(), fileURL: file)
        await store.loadPokemonDetails(speciesID: 6)
        let nav = PopoverNavigation()

        try await capture(ShopView(store: store, nav: nav, initialCategory: ItemCategory.megaStone).environment(store),
                          to: directory.appendingPathComponent("shop-mega-stone.png"), height: 620)

        XCTAssertTrue(store.equip(stone, to: "zard"))
        let defaults = UserDefaults(suiteName: "mega-shot-\(UUID())")!
        let battle = BattleEntryStore(defaults: defaults)
        _ = battle.add("zard")
        let uploader = PartyUploader(
            tokenStore: PartyTokenStore(fileURL: scratch.appendingPathComponent("token")), defaults: defaults,
            appVersion: "shot", send: { _ in 200 },
            fetch: { _ in (Data(megaMovesJSON.utf8), 200) }, partySource: { [] })
        uploader.saveToken("synthetic-token")
        uploader.serverURL = "http://bot-host:8790"
        try await capture(BattleView(store: store, navigation: nav, initialPickerQuery: "")
            .environment(uploader).environment(battle).environment(store),
                          to: directory.appendingPathComponent("battle-tab-mega-stone.png"), height: 620)

        XCTAssertTrue(store.equip(stone, to: "raised"))
        try await capture(CompanionHeader(store: store),
                          to: directory.appendingPathComponent("home-mega-form.png"), height: 300)
    }

    private func capture<V: View>(_ view: V, to file: URL, height: CGFloat) async throws {
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
        try await Task.sleep(for: .seconds(5))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: file)
    }
}
