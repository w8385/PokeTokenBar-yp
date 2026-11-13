import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private let syntheticReply = """
{"ok": true, "party_size": 1,
 "recent_battles": [
   {"opponent_name": "Alex", "my_pokemon_id": 25, "opponent_pokemon_id": 6, "result": "win", "turns": 6,
    "at": "2026-11-13T05:20:11+00:00"},
   {"opponent_name": "Sam", "my_pokemon_id": 25, "opponent_pokemon_id": 94, "result": "loss", "turns": 9,
    "at": "2026-11-13T03:02:40+00:00"},
   {"opponent_name": "Alex", "my_pokemon_id": 25, "opponent_pokemon_id": 143, "result": "win", "turns": 12,
    "at": "2026-11-12T08:44:05+00:00"},
   {"opponent_name": "Jordan", "my_pokemon_id": 6, "opponent_pokemon_id": 130, "result": "win", "turns": 5,
    "at": "2026-11-11T06:10:00+00:00"},
   {"opponent_name": "Sam", "my_pokemon_id": 6, "opponent_pokemon_id": 149, "result": "loss", "turns": 8,
    "at": "2026-11-10T01:30:00+00:00"}],
 "coworkers": [
   {"name": "Alex", "pokemon_id": 6, "level": 55, "shiny": true},
   {"name": "Sam", "pokemon_id": 94, "level": 38, "shiny": false},
   {"name": "Jordan", "pokemon_id": 130, "level": 33, "shiny": false},
   {"name": "Riley", "pokemon_id": 143, "level": 47, "shiny": false}]}
"""

/// Opt-in captures for the PR, from a synthetic reply and a synthetic save.
///
///     PTB_BATTLEINFO_SCREENSHOT_DIR=/tmp/shots swift test --filter BattleInfoScreenshotTests
@MainActor
final class BattleInfoScreenshotTests: XCTestCase {
    func testCaptureBattleTabWithRecentBattlesAndCoworkers() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_BATTLEINFO_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_BATTLEINFO_SCREENSHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("battleinfo-shot-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        var state = CompanionState()
        state.language = .ko
        var profile = PokemonProfile.generate(seed: 25, instanceID: "pikachu")
        profile.level = 62
        var entry = DexEntry(baseID: 25, finalID: 25, chainOrder: [25], rarity: .rare,
                             caughtAt: Date(timeIntervalSince1970: 1_700_000_000), isShiny: false, profile: profile,
                             names: [25: ["ko": "피카츄", "en": "Pikachu"]])
        entry.id = "pikachu"
        state.dex = [entry]
        let file = scratch.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(fileURL: file)

        let defaults = UserDefaults(suiteName: "battleinfo-shot-\(UUID())")!
        let battle = BattleEntryStore(defaults: defaults)
        battle.choose("pikachu")
        let reply = ReplyHolder(syntheticReply)
        let uploader = PartyUploader(
            tokenStore: PartyTokenStore(fileURL: scratch.appendingPathComponent("token")), defaults: defaults,
            appVersion: "shot", exchange: { _ in (Data(reply.body.utf8), 200) },
            fetch: { _ in (Data(#"{"moves":[],"default":[]}"#.utf8), 200) },
            partySource: { [PartyMember(pokemonID: 25, level: 62, shiny: false, ivs: nil)] })
        uploader.saveToken("synthetic-token")
        uploader.serverURL = "http://bot-host:8790"

        try await capture(BattleInfoSections(info: nil, l: store.l).padding(12),
                          height: 260, to: directory.appendingPathComponent("battle-info-pending.png"))
        await uploader.tick()
        XCTAssertEqual(uploader.battleInfo?.recentBattles.count, 5)
        try await capture(BattleInfoSections(info: uploader.battleInfo, l: store.l).padding(12),
                          height: 760, to: directory.appendingPathComponent("battle-info-lists.png"))
        try await capture(BattleInfoSections(info: BattleInfo(), l: store.l).padding(12),
                          height: 260, to: directory.appendingPathComponent("battle-info-empty.png"))
        let nav = PopoverNavigation()
        try await capture(BattleView(store: store, navigation: nav)
            .environment(uploader).environment(battle).environment(store),
                          height: 520, to: directory.appendingPathComponent("battle-tab-with-info.png"))
    }

    private final class ReplyHolder: @unchecked Sendable {
        let body: String
        init(_ body: String) { self.body = body }
    }

    private func capture<V: View>(_ view: V, height: CGFloat, to file: URL) async throws {
        let size = NSSize(width: PopoverMetrics.contentWidth, height: height)
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
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: file)
    }
}
