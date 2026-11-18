import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// Writes the move-name PR screenshots from synthetic data (nothing is read from or written to the real save):
///
///     PTB_MOVE_NAME_SCREENSHOT_DIR=/tmp/shots swift test --filter MoveNameScreenshotTests
@MainActor
final class MoveNameScreenshotTests: XCTestCase {
    func testMoveTrainingAndAReplayFrameInEachLanguage() async throws {
        guard let path = ProcessInfo.processInfo.environment["PTB_MOVE_NAME_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_MOVE_NAME_SCREENSHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for species in [25, 131] { _ = await SpriteLoader.image(speciesID: species, back: true) }
        for species in [3, 6] { _ = await SpriteLoader.image(speciesID: species) }
        for language in [AppLanguage.en, .ja, .ko] {
            let rig = try await TrainingRig(movesJSON: statusMovesJSON, language: language)
            let host = try await rig.mount(rig.section("pikachu"), height: 830)
            _ = try await rig.chooseRows(in: host, count: 5)
            try await OffscreenRender.settle(host) { rig.names.names.count == 8 }
            try OffscreenRender.writePNG(of: host, to: directory.appendingPathComponent(
                "move-training-\(language.rawValue).png"), scale: 2)
            rig.close()

            let names = PokemonNameDisplayStore()
            let replay = try await MoveNameReplayRig.mount(language: language, events: MoveNameFixtures.replayEvents,
                                                           provider: StubMoveNames(), names: names, settle: false)
            try await OffscreenRender.settle(replay) { names.names.count == 5 }
            try OffscreenRender.writePNG(of: replay, to: directory.appendingPathComponent(
                "gym-replay-move-\(language.rawValue).png"), scale: 2)
        }
    }
}

@MainActor
enum MoveNameReplayRig {
    /// The first frame with a move: Pikachu's Thunderbolt (85).
    static func mount(language: AppLanguage, events: [[String: Any]], provider: any PokemonNameProviding,
                      names: PokemonNameDisplayStore, settle: Bool = true) async throws -> NSView {
        let outcome = try GymBattleOutcome.decode(GymFixtures.outcomeData(
            gymID: "kanto-1", kind: "gym", won: true, turns: 5, events: events,
            teams: ([(25, "피카츄"), (131, "라프라스")].map { GymFixtures.fighter($0.0, name: $0.1, hp: 100) },
                    [(3, "이상해꽃"), (6, "리자몽")].map { GymFixtures.fighter($0.0, name: $0.1, hp: 100) })))
        let player = GymReplayPlayer(try XCTUnwrap(GymReplay(outcome)), shown: 3)
        let size = CGSize(width: PopoverMetrics.contentWidth, height: 260)
        let host = OffscreenRender.host(
            GymReplayView(player: player, outcome: outcome, l: L(language), autoplay: false).padding(Spacing.lg)
                .frame(width: size.width, height: size.height, alignment: .top)
                .background(Color.white).environment(\.colorScheme, .light)
                .environment(\.locale, language.displayLocale)
                .environment(\.pokemonNameProvider, provider).environment(\.pokemonNameStore, names),
            size: size, appearance: .aqua)
        if settle { try await OffscreenRender.settle(host) }
        return host
    }
}
