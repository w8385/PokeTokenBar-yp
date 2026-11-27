import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private let syntheticCoworkers = """
{"ok": true, "recent_battles": [],
 "coworkers": [
   {"id": "c1", "name": "Alex", "pokemon_id": 6, "level": 55, "shiny": true},
   {"id": "c2", "name": "Sam", "pokemon_id": 94, "level": 38, "shiny": false},
   {"id": "c3", "name": null, "pokemon_id": 130, "level": 33, "shiny": false}]}
"""

/// Opt-in captures for the PR, from a synthetic reply and a synthetic save.
///
///     PTB_GHOST_SCREENSHOT_DIR=/tmp/shots swift test --filter CoworkerGhostScreenshotTests
@MainActor
final class CoworkerGhostScreenshotTests: XCTestCase {
    func testCaptureTheNamedSectionTheTrophyResultAndTheCoworkersList() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_GHOST_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_GHOST_SCREENSHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("ghost-shot-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        for language in [AppLanguage.ko, .en] {
            var state = CompanionState()
            state.language = language
            state.coworkerTrophies = ["c2"]
            var profile = PokemonProfile.generate(seed: 25, instanceID: "pikachu")
            profile.level = 62
            var pikachu = DexEntry(baseID: 25, finalID: 25, chainOrder: [25], rarity: .rare,
                                   caughtAt: Date(timeIntervalSince1970: 1_700_000_000), isShiny: false,
                                   profile: profile, names: [25: ["ko": "피카츄", "en": "Pikachu"]])
            pikachu.id = "pikachu"
            state.dex = [pikachu]
            let file = scratch.appendingPathComponent("state-\(language.rawValue).json")
            try JSONEncoder().encode(state).write(to: file)
            let store = CompanionStore(fileURL: file)
            let entry = BattleEntryStore(defaults: UserDefaults(suiteName: "ghost-shot-\(UUID())")!)
            entry.add("pikachu")
            let info = try XCTUnwrap(BattleInfo.decode(Data(syntheticCoworkers.utf8)))
            let suffix = language == .ko ? "-ko" : ""

            let idle = GymService(link: { nil }, badges: { GymBadges() }, ownedTMs: { [] }, applyReward: { _, _, _ in },
                                  session: GymSession())
            try await capture(section(store, info: info, entry: entry, service: idle), language: language,
                              height: 250, to: directory.appendingPathComponent("named-section\(suffix).png"))

            let reply = GymFixtures.outcomeData(gymID: GymOpponent.ghostID, kind: GymOpponent.ghostID, won: true)
            let fought = GymService(link: { GymService.Link(server: "http://bot-host:8790", token: "synthetic-token") },
                                    exchange: { _ in (reply, 200) }, badges: { GymBadges() }, ownedTMs: { [] },
                                    applyReward: { _, _, _ in }, claimCoworkerTrophy: { store.claimCoworkerTrophy($0) },
                                    session: GymSession())
            await fought.fightCoworker(info.coworkers[0], l: store.l, team: GymTeam.Team(ids: ["pikachu"], members: [
                PartyMember(pokemonID: 25, level: 50, shiny: false, ivs: nil, moves: [85]),
            ]))
            XCTAssertEqual(fought.last?.trophy, true)
            try await capture(section(store, info: info, entry: entry, service: fought), language: language,
                              height: 620, to: directory.appendingPathComponent("named-result-trophy\(suffix).png"))

            let replayed = GymFixtures.outcomeData(gymID: GymOpponent.ghostID, kind: GymOpponent.ghostID, won: true,
                                                   events: GymFixtures.replayEvents)
            let replaying = GymService(link: { GymService.Link(server: "http://bot-host:8790", token: "synthetic-token") },
                                       exchange: { _ in (replayed, 200) }, badges: { GymBadges() }, ownedTMs: { [] },
                                       applyReward: { _, _, _ in }, session: GymSession())
            await replaying.fightCoworker(info.coworkers[1], l: store.l, team: GymTeam.Team(ids: ["pikachu"], members: [
                PartyMember(pokemonID: 25, level: 50, shiny: false, ivs: nil, moves: [85]),
            ]))
            XCTAssertNotNil(replaying.last.flatMap { GymReplay($0.outcome) }, "a ghost reply with events replays")
            try await capture(section(store, info: info, entry: entry, service: replaying), language: language,
                              height: 420, to: directory.appendingPathComponent("named-replay\(suffix).png"))

            try await capture(BattleInfoSections(info: info, l: store.l, parts: [.coworkers]).padding(12),
                              language: language, height: 200,
                              to: directory.appendingPathComponent("coworkers-before\(suffix).png"))
            try await capture(BattleInfoSections(info: info, l: store.l, parts: [.coworkers],
                                                 trophies: store.state.coworkerTrophies).padding(12),
                              language: language, height: 200,
                              to: directory.appendingPathComponent("coworkers-trophies\(suffix).png"))
        }
    }

    private func section(_ store: CompanionStore, info: BattleInfo, entry: BattleEntryStore,
                         service: GymService) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(store.l.ghostTitle)
                .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                .textCase(.uppercase).padding(.leading, 4)
            VStack(spacing: 0) { CoworkerGhostSection(store: store, info: info, entry: entry, service: service) }
                .ptbCard()
        }
        .padding(12)
    }

    private func capture<V: View>(_ view: V, language: AppLanguage, height: CGFloat, to file: URL) async throws {
        let size = NSSize(width: PopoverMetrics.contentWidth, height: height)
        try await OffscreenRender.capture(view.frame(width: size.width, height: size.height, alignment: .top)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .environment(\.locale, language.displayLocale),
            size: size, appearance: .aqua, to: file)
    }
}
