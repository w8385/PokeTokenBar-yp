import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// Plain `Text` has no native view, so a rendered name is checked by pixels against the same section drawn from a
/// bot that already sent that name.
@MainActor
final class MoveNameTests: XCTestCase {
    private let pikachuMoveIDs: Set<String> = ["84", "209", "85", "14", "86", "281", "433", "446"]

    private func png(_ bitmap: NSBitmapImageRep) -> Data? { bitmap.representation(using: .png, properties: [:]) }

    /// The section with its picker open on slot 1, every row's name settled.
    private func render(_ json: String, provider: any PokemonNameProviding,
                        loaded: Set<String> = []) async throws -> (TrainingRig, NSView, NSBitmapImageRep) {
        let rig = try await TrainingRig(movesJSON: json, language: .en, nameProvider: provider)
        let host = try await rig.mount(rig.section("pikachu"), height: 830)
        _ = try await rig.chooseRows(in: host, count: 5)
        try await OffscreenRender.settle(host) { Set(rig.names.names.keys.map(\.name)).isSuperset(of: loaded) }
        return (rig, host, try await OffscreenRender.stableBitmap(of: host))
    }

    func testAnEnglishUIShowsTheEnglishNameInASlotAndAPickerRow() async throws {
        let (translated, _, shown) = try await render(statusMovesJSON, provider: StubMoveNames(),
                                                      loaded: pikachuMoveIDs)
        defer { translated.close() }
        let (english, _, expected) = try await render(MoveNameFixtures.englishStatusMovesJSON,
                                                      provider: FailingMoveNames())
        defer { english.close() }
        let (korean, _, untranslated) = try await render(statusMovesJSON, provider: FixedMoveNames(code: "ko"),
                                                         loaded: pikachuMoveIDs)
        defer { korean.close() }
        XCTAssertNotEqual(png(expected), png(untranslated), "the English and Korean references must differ")
        XCTAssertEqual(png(shown), png(expected), "slots and picker rows draw the English names")
    }

    func testTheBotsNameShowsUntilTheTranslationArrivesThenTheTranslatedOne() async throws {
        let provider = GatedMoveNames()
        let rig = try await TrainingRig(movesJSON: statusMovesJSON, language: .en, nameProvider: provider)
        defer { rig.close() }
        let host = try await rig.mount(rig.section("pikachu"), height: 830)
        _ = try await rig.chooseRows(in: host, count: 5)
        try await waitUntil("every row to ask for its name by id") {
            await provider.requested == pikachuMoveIDs
        }
        let (korean, _, untranslated) = try await render(statusMovesJSON, provider: FixedMoveNames(code: "ko"),
                                                         loaded: pikachuMoveIDs)
        defer { korean.close() }
        let before = try await OffscreenRender.stableBitmap(of: host)
        XCTAssertEqual(png(before), png(untranslated), "the bot's names, not a placeholder, while loading")

        await provider.release()
        try await OffscreenRender.settle(host) { rig.names.names.count == pikachuMoveIDs.count }
        let (english, _, expected) = try await render(MoveNameFixtures.englishStatusMovesJSON,
                                                      provider: FailingMoveNames())
        defer { english.close() }
        let after = try await OffscreenRender.stableBitmap(of: host)
        XCTAssertEqual(png(after), png(expected), "the translated names once they arrive")
    }

    func testAReplayMoveWithAnIdShowsTheLocalizedNameAndOneWithoutShowsTheGivenString() throws {
        let withIDs = try outcome(MoveNameFixtures.replayEvents)
        let withoutIDs = try outcome(GymFixtures.replayEvents)
        let localized = try XCTUnwrap(GymReplay(withIDs)).frame(after: 3).lastMove
        let given = try XCTUnwrap(GymReplay(withoutIDs)).frame(after: 3).lastMove
        let names = StubMoveNames.table.reduce(into: [PokemonNameResource: [String: String]]()) {
            $0[MoveName.resource(id: $1.key)!] = $1.value
        }
        for (language, name) in [(AppLanguage.en, "Thunderbolt"), (.ja, "10まんボルト"), (.ko, "10만볼트")] {
            XCTAssertEqual(GymReplayView.moveText(localized, outcome: withIDs, language: language, names: names),
                           "피카츄 › \(name)")
            XCTAssertEqual(GymReplayView.moveText(given, outcome: withoutIDs, language: language, names: names),
                           "피카츄 › 10만볼트")
        }
    }

    func testTheReplayAsksForEveryMoveIdOnceAndNothingWithoutIds() async throws {
        let provider = GatedMoveNames()
        let names = PokemonNameDisplayStore()
        let host = try await MoveNameReplayRig.mount(language: .en, events: MoveNameFixtures.replayEvents,
                                                     provider: provider, names: names, settle: false)
        try await waitUntil("the replay to ask for its moves") {
            host.layoutSubtreeIfNeeded()
            return await provider.requested == ["85", "22", "53", "231", "57"]
        }
        await provider.release()
        try await OffscreenRender.waitUntil("the names to load", in: host) { names.names.count == 5 }

        let oldBot = GatedMoveNames()
        _ = try await MoveNameReplayRig.mount(language: .en, events: GymFixtures.replayEvents, provider: oldBot,
                                              names: PokemonNameDisplayStore())
        let asked = await oldBot.requested
        XCTAssertTrue(asked.isEmpty, "a replay without move_id asks for nothing: \(asked)")
    }

    func testTheReplayDecodesTheBotsMoveID() throws {
        let replay = try XCTUnwrap(GymReplay(try outcome(MoveNameFixtures.replayEvents)))
        XCTAssertEqual(replay.frame(after: 3).lastMove, GymReplay.Move(side: 0, member: 0, name: "10만볼트", id: 85))
        let old = try XCTUnwrap(GymReplay(try outcome(GymFixtures.replayEvents)))
        XCTAssertEqual(old.frame(after: 3).lastMove, GymReplay.Move(side: 0, member: 0, name: "10만볼트"))
    }

    func testTheBotsNameStandsInForAMissingIdAFailedLoadAndAnUntranslatedLanguage() throws {
        let thunderbolt = try XCTUnwrap(MoveName.resource(id: 85))
        XCTAssertEqual(MoveName.text(id: 85, botName: "10만볼트", language: .en,
                                     names: [thunderbolt: ["en": "Thunderbolt"]]), "Thunderbolt")
        XCTAssertEqual(MoveName.text(id: nil, botName: "10만볼트", language: .en,
                                     names: [thunderbolt: ["en": "Thunderbolt"]]), "10만볼트")
        XCTAssertEqual(MoveName.text(id: 85, botName: "10만볼트", language: .en, names: [:]), "10만볼트")
        XCTAssertEqual(MoveName.text(id: 85, botName: "10만볼트", language: .ru,
                                     names: [thunderbolt: ["ja": "10まんボルト"]]), "10만볼트")
        XCTAssertNil(MoveName.resource(id: 0))
    }

    private func outcome(_ events: [[String: Any]]) throws -> GymBattleOutcome {
        try GymBattleOutcome.decode(GymFixtures.outcomeData(
            gymID: "kanto-1", kind: "gym", won: true, turns: 5, events: events,
            teams: ([(25, "피카츄"), (131, "라프라스")].map { GymFixtures.fighter($0.0, name: $0.1, hp: 100) },
                    [(3, "이상해꽃"), (6, "리자몽")].map { GymFixtures.fighter($0.0, name: $0.1, hp: 100) })))
    }
}
