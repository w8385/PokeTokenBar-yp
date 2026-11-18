import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private let syntheticReply = """
{"ok": true, "party_size": 3,
 "recent_battles": [
   {"opponent_name": "Alex", "my_pokemon_id": 25, "opponent_pokemon_id": 6, "result": "win", "turns": 6,
    "at": "2026-11-13T05:20:11+00:00"},
   {"opponent_name": "Sam", "my_pokemon_id": 94, "opponent_pokemon_id": 130, "result": "loss", "turns": 9,
    "at": "2026-11-12T03:02:40+00:00"},
   {"opponent_name": "Jordan", "my_pokemon_id": 6, "opponent_pokemon_id": 143, "result": "win", "turns": 12,
    "at": "2026-11-11T08:44:05+00:00"}],
 "coworkers": []}
"""

private struct OfflineProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// Opt-in captures of the Battle tab for the PR: a synthetic save, a synthetic bot reply and a seeded gym catalog.
///
///     PTB_BATTLESUBTABS_SCREENSHOT_DIR=/tmp/shots PTB_BATTLESUBTABS_SUFFIX=after swift test --filter BattleSubTabsShotTests
@MainActor
final class BattleSubTabsShotTests: XCTestCase {
    private final class ReplyHolder: @unchecked Sendable {
        let body: String
        init(_ body: String) { self.body = body }
    }

    func testCaptureBattleTab() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_BATTLESUBTABS_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_BATTLESUBTABS_SCREENSHOT_DIR to write the PR screenshots")
        }
        let suffix = ProcessInfo.processInfo.environment["PTB_BATTLESUBTABS_SUFFIX"] ?? "after"
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let originalArt = GymTrainerArt.directory
        GymTrainerArt.directory = GymRepo.trainerAssets
        GymTrainerArt.clearCache()
        defer { GymTrainerArt.directory = originalArt; GymTrainerArt.clearCache() }

        for language in [AppLanguage.ko, .en] {
            let rig = try await rig(language)
            defer { rig.cleanup() }
            for tab in BattleSubTab.allCases {
                rig.nav.battleSubTab = tab
                try await capture(BattleView(store: rig.store, navigation: rig.nav), rig: rig, language: language,
                                  to: directory.appendingPathComponent("battle-tab-\(tab.rawValue)-\(language.rawValue)-\(suffix).png"))
            }
        }

        let unlinked = try await rig(.ko, linked: false)
        defer { unlinked.cleanup() }
        unlinked.nav.battleSubTab = .entry
        try await capture(BattleView(store: unlinked.store, navigation: unlinked.nav), rig: unlinked, language: .ko,
                          to: directory.appendingPathComponent("battle-tab-entry-unlinked-ko-\(suffix).png"))
    }

    private struct Rig {
        let store: CompanionStore
        let entry: BattleEntryStore
        let uploader: PartyUploader
        let nav: PopoverNavigation
        let cleanup: () -> Void
    }

    private func dexEntry(_ species: Int, id: String, level: Int, names: [String: String]) -> DexEntry {
        var profile = PokemonProfile.generate(seed: UInt64(species), instanceID: id)
        profile.level = level
        var entry = DexEntry(baseID: species, finalID: species, chainOrder: [species], rarity: .rare,
                             caughtAt: Date(timeIntervalSince1970: 1_700_000_000), isShiny: false, profile: profile,
                             names: [species: names])
        entry.id = id
        return entry
    }

    private func rig(_ language: AppLanguage, linked: Bool = true) async throws -> Rig {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("battle-subtabs-shot-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        var state = CompanionState()
        state.language = language
        state.installBaselineSet = true
        state.dex = [dexEntry(25, id: "pikachu", level: 62, names: ["ko": "피카츄", "en": "Pikachu"]),
                     dexEntry(94, id: "gengar", level: 48, names: ["ko": "팬텀", "en": "Gengar"]),
                     dexEntry(6, id: "zard", level: 55, names: ["ko": "리자몽", "en": "Charizard"])]
        let file = scratch.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: OfflineProvider(), fileURL: file)
        let suite = "battle-subtabs-shot-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let entry = BattleEntryStore(defaults: defaults)
        ["pikachu", "gengar", "zard"].forEach { entry.add($0) }
        let reply = ReplyHolder(syntheticReply)
        let server = "http://bot-shot-\(UUID().uuidString.prefix(8).lowercased()):8790"
        let uploader = PartyUploader(
            tokenStore: PartyTokenStore(fileURL: scratch.appendingPathComponent("token")), defaults: defaults,
            appVersion: "shot", exchange: { _ in (Data(reply.body.utf8), 200) },
            fetch: { _ in (Data(#"{"moves":[],"default":[]}"#.utf8), 200) },
            partySource: { [PartyMember(pokemonID: 25, level: 62, shiny: false, ivs: nil)] })
        uploader.serverURL = server
        if linked {
            uploader.saveToken("synthetic-token")
            await uploader.tick()
            XCTAssertEqual(uploader.battleInfo?.recentBattles.count, 3)
        }
        GymSession.shared.setCatalog(GymFixtures.catalog(), for: server)
        return Rig(store: store, entry: entry, uploader: uploader, nav: PopoverNavigation(defaults: defaults)) {
            GymSession.shared.setCatalog(nil, for: server)
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: scratch)
        }
    }

    private func capture<V: View>(_ view: V, rig: Rig, language: AppLanguage, to file: URL) async throws {
        let size = NSSize(width: PopoverMetrics.contentWidth, height: 520)
        try await OffscreenRender.capture(
            view.environment(rig.uploader).environment(rig.entry).environment(rig.store).environment(rig.nav)
                .frame(width: size.width, height: size.height, alignment: .top)
                .background(Color.white)
                .environment(\.colorScheme, .light)
                .environment(\.locale, language.displayLocale),
            size: size, appearance: .aqua, scale: 2, to: file)
    }
}
