import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// Opt-in captures for the PR: the replay at its start, middle and end, and the result screen while it plays.
///
///     PTB_GYM_SCREENSHOT_DIR=/tmp/shots swift test --filter GymReplayScreenshotTests
@MainActor
final class GymReplayScreenshotTests: XCTestCase {
    private let mine = [(25, "피카츄"), (131, "라프라스"), (94, "팬텀")]
    private let theirs = [(3, "이상해꽃"), (6, "리자몽")]

    func testCaptureTheReplay() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_GYM_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_GYM_SCREENSHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (species, _) in mine { _ = await SpriteLoader.image(speciesID: species, back: true) }
        for (species, _) in theirs { _ = await SpriteLoader.image(speciesID: species) }
        let original = GymTrainerArt.directory
        GymTrainerArt.directory = GymRepo.trainerAssets
        GymTrainerArt.clearCache()
        defer {
            GymTrainerArt.directory = original
            GymTrainerArt.clearCache()
        }

        let outcome = try GymBattleOutcome.decode(GymFixtures.outcomeData(
            gymID: "kanto-1", kind: "gym", won: true, turns: 5, events: GymFixtures.replayEvents,
            teams: (fighters(mine, hp: [0, 100, nil]), fighters(theirs, hp: [0, 0]))))
        let replay = try XCTUnwrap(GymReplay(outcome))
        let catalog = try GymCatalog.decode(GymFixtures.catalogData())
        let opponent = try XCTUnwrap(catalog.region("kanto")?.gyms.first)
        for language in [AppLanguage.ko, .en] {
            let l = L(language)
            for (name, shown) in [("start", 2), ("mid", 13), ("end", replay.events.count)] {
                let player = GymReplayPlayer(replay, shown: shown)
                try write(GymReplayView(player: player, outcome: outcome, l: l, autoplay: false).padding(Spacing.lg),
                          language: language, height: 260,
                          to: directory.appendingPathComponent("gym-replay-\(name)-\(language.rawValue).png"))
            }
            let record = GymFightRecord(opponent: opponent, outcome: outcome, reward: nil)
            try write(GymResultView(record: record, language: language, l: l, regionName: "Kanto", tmName: { _ in nil },
                                    primaryTitle: l.gymRematch, busy: false, onPrimary: {}, onClose: {}),
                      language: language, height: 470,
                      to: directory.appendingPathComponent("gym-replay-screen-\(language.rawValue).png"))
        }
        try await captureTheBotsKantoLineups(to: directory)
    }

    /// The foe's Charizard right after it Mega Evolves: "before" drops the `form` event, as an app without forms shows it.
    func testCaptureTheMegaReplay() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_GYM_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_GYM_SCREENSHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (species, _) in mine { _ = await SpriteLoader.image(speciesID: species, back: true) }
        for species in theirs.map(\.0) + [10034] { _ = await SpriteLoader.image(speciesID: species) }
        let teams = (fighters(mine, hp: [0, 100, nil]), fighters(theirs, hp: [0, 0]))
        for (name, events, shown) in [("before", GymFixtures.replayEvents, 10), ("after", GymFixtures.megaReplayEvents, 11)] {
            let outcome = try GymBattleOutcome.decode(GymFixtures.outcomeData(
                gymID: "kanto-1", kind: "gym", won: true, turns: 5, events: events, teams: teams))
            let player = GymReplayPlayer(try XCTUnwrap(GymReplay(outcome)), shown: shown)
            for language in [AppLanguage.ko, .en] {
                try write(GymReplayView(player: player, outcome: outcome, l: L(language), autoplay: false)
                    .padding(Spacing.lg),
                          language: language, height: 260,
                          to: directory.appendingPathComponent("gym-replay-mega-\(name)-\(language.rawValue).png"))
            }
        }
    }

    /// The foe's Ditto right after Imposter turns it into the player's Pikachu: "before" drops the `form` event.
    func testCaptureTheImposterReplay() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_GYM_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_GYM_SCREENSHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let foes = [(3, "이상해꽃"), (132, "메타몽")]
        for (species, _) in mine { _ = await SpriteLoader.image(speciesID: species, back: true) }
        for species in foes.map(\.0) + [25] { _ = await SpriteLoader.image(speciesID: species) }
        let teams = (fighters(mine, hp: [0, 100, nil]), fighters(foes, hp: [0, 0]))
        for (name, events) in [("before", GymFixtures.replayEvents), ("after", GymFixtures.imposterReplayEvents)] {
            let outcome = try GymBattleOutcome.decode(GymFixtures.outcomeData(
                gymID: "kanto-1", kind: "gym", won: true, turns: 5, events: events, teams: teams))
            let player = GymReplayPlayer(try XCTUnwrap(GymReplay(outcome)), shown: name == "before" ? 10 : 11)
            for language in [AppLanguage.ko, .en] {
                try write(GymReplayView(player: player, outcome: outcome, l: L(language), autoplay: false)
                    .padding(Spacing.lg),
                          language: language, height: 260,
                          to: directory.appendingPathComponent("gym-replay-imposter-\(name)-\(language.rawValue).png"))
            }
        }
    }

    /// A lost Elite Four step right after Skip: the replay's last frame and its next step.
    func testCaptureTheLostRunStepAfterSkip() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_GYM_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_GYM_SCREENSHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (species, _) in mine { _ = await SpriteLoader.image(speciesID: species, back: true) }
        for (species, _) in theirs { _ = await SpriteLoader.image(speciesID: species) }
        let catalog = try GymCatalog.decode(GymFixtures.catalogData())
        let opponent = try XCTUnwrap(catalog.region("kanto")?.elite.battles[1])
        let outcome = try GymBattleOutcome.decode(GymFixtures.outcomeData(
            gymID: opponent.id, kind: "elite", won: false, run: ("kanto-elite", 2, 5, "kanto-elite-1", "kanto-elite-3"), turns: 5,
            events: GymFixtures.replayEvents,
            teams: (fighters(mine, hp: [0, 0, 0]), fighters(theirs, hp: [0, 40]))))
        for language in [AppLanguage.ko, .en] {
            let l = L(language)
            try write(GymResultView(record: GymFightRecord(opponent: opponent, outcome: outcome, reward: nil),
                                    language: language, l: l, regionName: "Kanto", tmName: { _ in nil },
                                    primaryTitle: l.gymRestartRun, busy: false, onPrimary: {}, onClose: {},
                                    replayShown: Int.max),
                      language: language, height: 560,
                      to: directory.appendingPathComponent("gym-run-lost-skipped-\(language.rawValue).png"))
        }
    }

    /// The bot's gym 1 (three foes) as a result, and a champion loss with the hidden partner unseen.
    private func captureTheBotsKantoLineups(to directory: URL) async throws {
        let kanto = try XCTUnwrap(try GymCatalog.decode(Data(contentsOf: GymRepo.kantoCatalog)).region("kanto"))
        let gym = kanto.gyms[0]
        let champion = try XCTUnwrap(kanto.elite.battles.last)
        let three = [(8, "어니부기"), (117, "시드라"), (119, "왕콘치")]
        let six = zip(champion.team, ["썬더", "파이어", "망나뇽", "리자몽", "팬텀", "갸라도스"]).map { ($0, $1) }
        for species in three.map(\.0) + champion.team { _ = await SpriteLoader.image(speciesID: species) }
        let small = try GymBattleOutcome.decode(GymFixtures.outcomeData(
            gymID: gym.id, kind: "gym", won: true, turns: 7,
            teams: (fighters(mine, hp: [0, 100, nil]), fighters(three, hp: [0, 0, 0]))))
        let lost = try GymBattleOutcome.decode(GymFixtures.outcomeData(
            gymID: champion.id, kind: "champion", won: false, turns: 9,
            teams: (fighters(mine, hp: [0, 0, 0]),
                    fighters(six + [(150, "뮤츠")], hp: [0, 0, 64, 100, 100, 100, nil]))))
        for language in [AppLanguage.ko, .en] {
            let l = L(language)
            for (name, opponent, outcome) in [("gym-1-result", gym, small), ("champion-result", champion, lost)] {
                try write(GymResultView(record: GymFightRecord(opponent: opponent, outcome: outcome, reward: nil),
                                        language: language, l: l, regionName: l.gymRegionName(kanto),
                                        tmName: { _ in nil }, primaryTitle: l.gymRematch, busy: false,
                                        onPrimary: {}, onClose: {}),
                          language: language, height: 330,
                          to: directory.appendingPathComponent("\(name)-\(language.rawValue).png"))
            }
        }
    }

    private func fighters(_ team: [(Int, String)], hp: [Int?]) -> [[String: Any]] {
        zip(team, hp).map { GymFixtures.fighter($0.0, name: $0.1, hp: $1) }
    }

    /// No wait after hosting: the sprites are cached already, and the replay's own task never gets a turn to run.
    private func write<V: View>(_ view: V, language: AppLanguage, height: CGFloat, to file: URL) throws {
        let size = NSSize(width: PopoverMetrics.contentWidth, height: height)
        let host = OffscreenRender.host(
            view.frame(width: size.width, height: size.height, alignment: .top)
                .background(Color.white).environment(\.colorScheme, .light)
                .environment(\.locale, language.displayLocale),
            size: size, appearance: .aqua)
        try OffscreenRender.writePNG(of: host, to: file, scale: 2)
    }
}
