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
