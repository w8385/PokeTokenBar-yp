import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class ForgetMoveTests: XCTestCase {
    private func party(_ rig: TrainingRig) -> [PartyMember] {
        BattleEntry.party(state: rig.store.state, slots: [BattleEntrySlot(instanceID: "pikachu")],
                          moveChoices: rig.battle.moveChoices, rentalSpeciesID: 4)
    }

    /// The Forget buttons top to bottom, one per filled slot, found by their size on the cards' right edge.
    private func forgetButtons(_ rig: TrainingRig, in host: NSView, count: Int) async throws -> [NSButton] {
        let isForget: (NSButton) -> Bool = { button in
            let frame = rig.frame(of: button, in: host)
            return frame.minX > 250 && frame.width == 20 && frame.height == 20
        }
        return try await rig.buttons(in: host, until: { $0.filter(isForget).count == count }).filter(isForget)
    }

    func testForgettingFromTheDefaultsSavesTheRestInOrder() async throws {
        let rig = try await TrainingRig()
        defer { rig.close() }

        rig.battle.forgetMove(at: 1, for: "pikachu", pokemonID: 25, current: [84, 209, 85, 89])

        XCTAssertEqual(rig.battle.chosenMoves(for: "pikachu", pokemonID: 25), [84, 85, 89])
    }

    func testTheLastMoveCannotBeForgotten() async throws {
        let rig = try await TrainingRig()
        defer { rig.close() }

        rig.battle.forgetMove(at: 0, for: "pikachu", pokemonID: 25, current: [84, 209, 85])
        rig.battle.forgetMove(at: 1, for: "pikachu", pokemonID: 25, current: [209, 85])
        XCTAssertEqual(rig.battle.chosenMoves(for: "pikachu", pokemonID: 25), [209])

        rig.battle.forgetMove(at: 0, for: "pikachu", pokemonID: 25, current: [209])

        XCTAssertEqual(rig.battle.chosenMoves(for: "pikachu", pokemonID: 25), [209])
        XCTAssertEqual(party(rig).first?.moves, [209])
    }

    func testAPositionOutsideTheListChangesNothing() async throws {
        let rig = try await TrainingRig()
        defer { rig.close() }

        rig.battle.forgetMove(at: 2, for: "pikachu", pokemonID: 25, current: [84, 209])

        XCTAssertEqual(rig.battle.chosenMoves(for: "pikachu", pokemonID: 25), [])
    }

    func testPickingAfterForgettingFillsTheEnd() async throws {
        let rig = try await TrainingRig()
        defer { rig.close() }
        rig.store.grantTM(moveID: 89)
        rig.battle.forgetMove(at: 0, for: "pikachu", pokemonID: 25, current: [84, 209])

        rig.battle.chooseMove(89, at: 1, for: "pikachu", pokemonID: 25, current: [209], isMachine: true)

        XCTAssertEqual(rig.battle.chosenMoves(for: "pikachu", pokemonID: 25), [209, 89])
        XCTAssertEqual(rig.battle.moveChoices["pikachu"]?.machine, [89])
    }

    func testForgettingATMMoveDropsItsMarkButKeepsTheTM() async throws {
        let rig = try await TrainingRig()
        defer { rig.close() }
        rig.store.grantTM(moveID: 85)
        rig.battle.chooseMove(85, at: 2, for: "pikachu", pokemonID: 25, current: [84, 209], isMachine: true)

        rig.battle.forgetMove(at: 2, for: "pikachu", pokemonID: 25, current: [84, 209, 85])

        XCTAssertEqual(rig.battle.chosenMoves(for: "pikachu", pokemonID: 25), [84, 209])
        XCTAssertEqual(rig.battle.moveChoices["pikachu"]?.machine, [])
        XCTAssertTrue(rig.store.ownsTM(85), "the TM can be taught again")
    }

    func testResetAfterForgettingGoesBackToTheDefaults() async throws {
        let rig = try await TrainingRig()
        defer { rig.close() }
        let defaults = party(rig).first?.moves
        rig.battle.forgetMove(at: 0, for: "pikachu", pokemonID: 25, current: [84, 209])

        rig.battle.resetMoves(for: "pikachu")

        XCTAssertEqual(rig.battle.chosenMoves(for: "pikachu", pokemonID: 25), [])
        XCTAssertEqual(party(rig).first?.moves, defaults)
    }

    func testTheUploadCarriesTheMovesLeftAfterForgetting() async throws {
        let rig = try await TrainingRig()
        defer { rig.close() }
        rig.store.grantTM(moveID: 85)
        rig.store.grantTM(moveID: 89)
        rig.battle.chooseMove(85, at: 2, for: "pikachu", pokemonID: 25, current: [84, 209], isMachine: true)
        rig.battle.chooseMove(89, at: 3, for: "pikachu", pokemonID: 25, current: [84, 209, 85], isMachine: true)

        rig.battle.forgetMove(at: 1, for: "pikachu", pokemonID: 25, current: [84, 209, 85, 89])
        XCTAssertEqual(party(rig).first?.moves, [84, 85, 89])
        rig.battle.forgetMove(at: 0, for: "pikachu", pokemonID: 25, current: [84, 85, 89])
        XCTAssertEqual(party(rig).first?.moves, [85, 89])
        rig.battle.forgetMove(at: 1, for: "pikachu", pokemonID: 25, current: [85, 89])
        XCTAssertEqual(party(rig).first?.moves, [85])
    }

    func testEachFilledSlotHasForgetAndTheLastMoveIsLocked() async throws {
        let rig = try await TrainingRig()
        defer { rig.close() }
        rig.battle.add("pikachu")
        let host = try await rig.mount(rig.section("pikachu", editing: nil), height: 600)

        let before = try await forgetButtons(rig, in: host, count: 2)
        XCTAssertEqual(before.map(\.isEnabled), [true, true], "the two default moves; the empty slots have none")

        try await rig.press(before[0], in: host, until: { !rig.posts.all.isEmpty })

        XCTAssertEqual(rig.battle.chosenMoves(for: "pikachu", pokemonID: 25), [209])
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(rig.posts.all[0].utf8)) as? [String: Any])
        let sent = try XCTUnwrap((body["party"] as? [[String: Any]])?.first)
        XCTAssertEqual(sent["moves"] as? [Int], [209], rig.posts.all[0])
        let after = try await forgetButtons(rig, in: host, count: 1)
        XCTAssertEqual(after.map(\.isEnabled), [false], "the last move stays")
        _ = try await rig.autoReset(in: host, enabled: true)
    }

    func testForgetHasItsOwnLabel() {
        for language in [AppLanguage.ko, .en] {
            let l = L(language)
            XCTAssertFalse(l.moveSlotForget.isEmpty, "\(language)")
            XCTAssertNotEqual(l.moveSlotForget, l.moveSlotUp, "\(language)")
        }
    }
}

/// Writes the Forget PR screenshots from synthetic data (nothing is read from or written to the real save):
///
///     PTB_TM_SCREENSHOT_DIR=/tmp/shots swift test --filter ForgetMoveScreenshotTests
@MainActor
final class ForgetMoveScreenshotTests: XCTestCase {
    func testTheSlotsBeforeAndAfterForgetting() async throws {
        guard let path = ProcessInfo.processInfo.environment["PTB_TM_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_TM_SCREENSHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (language, suffix) in [(AppLanguage.ko, "ko"), (.en, "en")] {
            for forgetting in [false, true] {
                let rig = try await TrainingRig(language: language)
                rig.store.grantTM(moveID: 85)
                rig.store.grantTM(moveID: 89)
                rig.battle.chooseMove(85, at: 2, for: "pikachu", pokemonID: 25, current: [84, 209], isMachine: true)
                rig.battle.chooseMove(89, at: 3, for: "pikachu", pokemonID: 25, current: [84, 209, 85],
                                      isMachine: true)
                if forgetting {
                    rig.battle.forgetMove(at: 1, for: "pikachu", pokemonID: 25, current: [84, 209, 85, 89])
                }
                let host = try await rig.mount(rig.section("pikachu", editing: nil), height: 340)
                _ = try await rig.autoReset(in: host, enabled: true)
                try OffscreenRender.writePNG(of: host, to: directory.appendingPathComponent(
                    "forget-moves-\(forgetting ? "after" : "before")-\(suffix).png"), scale: 2)
                rig.close()
            }
        }
    }
}
