import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class MoveSlotOrderTests: XCTestCase {
    private func party(_ rig: TrainingRig) -> [PartyMember] {
        BattleEntry.party(state: rig.store.state, slots: [BattleEntrySlot(instanceID: "pikachu")],
                          moveChoices: rig.battle.moveChoices, rentalSpeciesID: 4)
    }

    /// The ▲/▼ buttons top to bottom, ▲ then ▼ for each filled slot. SwiftUI gives them no identifier or label in
    /// the AppKit tree, so they are found by their size on the cards' right edge.
    private func orderButtons(_ rig: TrainingRig, in host: NSView, count: Int) async throws -> [NSButton] {
        let isOrder: (NSButton) -> Bool = { button in
            let frame = rig.frame(of: button, in: host)
            return frame.minX > 250 && frame.width == 18 && frame.height == 16
        }
        return try await rig.buttons(in: host, until: { $0.filter(isOrder).count == count }).filter(isOrder)
    }

    func testSwapWritesTheNewOrderToTheCustomList() async throws {
        let rig = try await TrainingRig()
        defer { rig.close() }
        rig.store.grantTM(moveID: 85)
        rig.battle.chooseMove(85, at: 2, for: "pikachu", pokemonID: 25, current: [84, 209], isMachine: true)

        rig.battle.swapMoves(0, 2, for: "pikachu", pokemonID: 25, current: [84, 209, 85])

        XCTAssertEqual(rig.battle.chosenMoves(for: "pikachu", pokemonID: 25), [85, 209, 84])
        XCTAssertEqual(rig.battle.moveChoices["pikachu"]?.machine, [85], "the TM mark follows the move")

        rig.battle.swapMoves(1, 3, for: "pikachu", pokemonID: 25, current: [85, 209, 84])
        rig.battle.swapMoves(1, 1, for: "pikachu", pokemonID: 25, current: [85, 209, 84])
        XCTAssertEqual(rig.battle.chosenMoves(for: "pikachu", pokemonID: 25), [85, 209, 84],
                       "an empty slot or the same slot changes nothing")
    }

    func testSwapFromTheDefaultListSavesACustomList() async throws {
        let rig = try await TrainingRig()
        defer { rig.close() }
        XCTAssertEqual(rig.battle.chosenMoves(for: "pikachu", pokemonID: 25), [])

        rig.battle.swapMoves(1, 0, for: "pikachu", pokemonID: 25, current: [84, 209])

        XCTAssertEqual(rig.battle.chosenMoves(for: "pikachu", pokemonID: 25), [209, 84])
        XCTAssertEqual(party(rig).first?.moves, [209, 84])
    }

    func testAnUnownedTMStaysOutOfTheUploadAfterASwap() async throws {
        let rig = try await TrainingRig()
        defer { rig.close() }
        rig.battle.chooseMove(85, at: 2, for: "pikachu", pokemonID: 25, current: [84, 209], isMachine: true)

        rig.battle.swapMoves(2, 0, for: "pikachu", pokemonID: 25, current: [84, 209, 85])

        XCTAssertEqual(rig.battle.chosenMoves(for: "pikachu", pokemonID: 25), [85, 209, 84])
        XCTAssertEqual(party(rig).first?.moves, [209, 84])
    }

    func testUpIsOffOnSlotOneDownIsOffOnTheLastFilledSlotAndEmptySlotsHaveNeither() async throws {
        let rig = try await TrainingRig()
        defer { rig.close() }
        let host = try await rig.mount(rig.section("pikachu", editing: nil), height: 600)

        let buttons = try await orderButtons(rig, in: host, count: 4)

        XCTAssertEqual(buttons.map(\.isEnabled), [false, true, true, false],
                       "slot 1 ▲ off, ▼ on; slot 2 ▲ on, ▼ off; the empty slots 3 and 4 have none")
    }

    func testOrderLabelsExistInEveryLanguage() {
        for language in AppLanguage.allCases {
            let l = L(language)
            XCTAssertFalse(l.moveSlotUp.isEmpty, "\(language)")
            XCTAssertNotEqual(l.moveSlotUp, l.moveSlotDown, "\(language)")
        }
    }

    func testDownOnSlotOneUploadsTheNewOrderWithoutOpeningThePicker() async throws {
        let rig = try await TrainingRig()
        defer { rig.close() }
        rig.battle.add("pikachu")
        let host = try await rig.mount(rig.section("pikachu", editing: nil), height: 600)
        let buttons = try await orderButtons(rig, in: host, count: 4)

        try await rig.press(buttons[1], in: host, until: { !rig.posts.all.isEmpty })

        XCTAssertEqual(rig.battle.chosenMoves(for: "pikachu", pokemonID: 25), [209, 84])
        XCTAssertEqual(rig.posts.all.count, 1)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(rig.posts.all[0].utf8)) as? [String: Any])
        let sent = try XCTUnwrap((body["party"] as? [[String: Any]])?.first)
        XCTAssertEqual(sent["pokemon_id"] as? Int, 25, rig.posts.all[0])
        XCTAssertEqual(sent["moves"] as? [Int], [209, 84], rig.posts.all[0])
        XCTAssertTrue(rig.buttons(in: host).filter { rig.frame(of: $0, in: host).width > 250 }.isEmpty,
                      "the order buttons never open the picker")
    }

    func testTheCardsLeftEdgeStillOpensThePicker() async throws {
        let rig = try await TrainingRig()
        defer { rig.close() }
        let host = try await rig.mount(rig.section("pikachu", editing: nil), height: 600)
        let up = rig.frame(of: try await orderButtons(rig, in: host, count: 4)[0], in: host)
        let window = try XCTUnwrap(host.window)

        // 4 pt inside the first card's left border, level with its ▲.
        try OffscreenRender.click(at: host.convert(NSPoint(x: 12 + 10 + 4, y: up.midY), to: nil), in: window)

        _ = try await rig.chooseRows(in: host, count: 2)
    }

    func testSlotCardsStandApart() {
        let card = Text("Thunder Shock").padding(Spacing.sm).moveSlotCard(editing: false)
        let one = LayoutMeasure.size(card, width: 300).height
        let four = LayoutMeasure.size(MoveSlotStack(count: 4) { _ in card }, width: 300).height

        XCTAssertGreaterThan(one, 0)
        XCTAssertGreaterThan((four - 4 * one) / 3, 0, "a gap between every two cards")
    }

    func testPickerRowsHaveADividerBetweenThem() async throws {
        let rig = try await TrainingRig()
        defer { rig.close() }
        rig.store.grantTM(moveID: 89)
        let host = try await rig.mount(rig.section("pikachu"), height: 700)
        // Spark and Thunder Shock (level-up), then the owned Earthquake under the locked Thunderbolt.
        let rows = try await rig.chooseRows(in: host, count: 3).map { rig.frame(of: $0, in: host) }
        let bitmap = try await OffscreenRender.stableBitmap(of: host)

        XCTAssertTrue(try divider(in: bitmap, between: rows[0].maxY, and: rows[1].minY, across: rows[0]),
                      "between two level-up rows")
        XCTAssertTrue(try divider(in: bitmap, between: rows[2].minY - 12, and: rows[2].minY, across: rows[2]),
                      "between the locked TM row and the next")
    }

    /// A pixel row in `top..<bottom` darker than the strip's background all the way across `row`.
    private func divider(in bitmap: NSBitmapImageRep, between top: CGFloat, and bottom: CGFloat,
                         across row: CGRect) throws -> Bool {
        let scale = CGFloat(bitmap.pixelsWide) / bitmap.size.width
        let xs = stride(from: row.minX + 20, through: row.maxX - 20, by: (row.width - 40) / 6).map { Int($0 * scale) }
        func brightness(_ x: Int, _ y: Int) throws -> CGFloat {
            try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)).brightnessComponent
        }
        let lines = try (Int(top * scale)..<Int(bottom * scale)).map { y in try xs.map { try brightness($0, y) } }
        let background = lines.flatMap { $0 }.max() ?? 0
        return lines.contains { line in line.allSatisfy { background - $0 > 0.02 } }
    }
}

/// Writes the slot-order PR screenshots from synthetic data (nothing is read from or written to the real save):
///
///     PTB_TM_SCREENSHOT_DIR=/tmp/shots swift test --filter MoveSlotOrderScreenshotTests
@MainActor
final class MoveSlotOrderScreenshotTests: XCTestCase {
    func testTheSlotListAndTheOpenPicker() async throws {
        guard let path = ProcessInfo.processInfo.environment["PTB_TM_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_TM_SCREENSHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = ProcessInfo.processInfo.environment["PTB_TM_SCREENSHOT_NAME"] ?? "after"
        for (language, suffix) in [(AppLanguage.ko, "ko"), (.en, "en")] {
            for (editing, view, height) in [(nil as Int?, "slots", CGFloat(300)), (0, "picker", CGFloat(500))] {
                let rig = try await TrainingRig(language: language)
                rig.store.grantTM(moveID: 89)
                rig.battle.chooseMove(89, at: 2, for: "pikachu", pokemonID: 25, current: [84, 209], isMachine: true)
                let host = try await rig.mount(rig.section("pikachu", editing: editing), height: height)
                _ = try await rig.autoReset(in: host, enabled: true)
                if editing != nil { _ = try await rig.chooseRows(in: host, count: 3) }
                try OffscreenRender.writePNG(of: host, to: directory.appendingPathComponent(
                    "move-slot-\(view)-\(name)-\(suffix).png"), scale: 2)
                rig.close()
            }
        }
    }
}
