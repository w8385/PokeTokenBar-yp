import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class NaturePickerTests: XCTestCase {
    private let boxID = "onix-graduate"

    func testGridRowsRaiseAndColumnsLowerInStatOrderWithNeutralNaturesOnTheDiagonal() {
        XCTAssertEqual(NatureGrid.stats, ["attack", "defense", "special-attack", "special-defense", "speed"])
        XCTAssertEqual(NatureGrid.rows.indices.map { NatureGrid.rows[$0][$0] },
                       [.hardy, .docile, .bashful, .quirky, .serious])
        XCTAssertEqual(NatureGrid.rows[0], [.hardy, .lonely, .adamant, .naughty, .brave])
        XCTAssertEqual(NatureGrid.rows.map(\.[0]), [.hardy, .bold, .modest, .calm, .timid])
        XCTAssertEqual(Set(NatureGrid.rows.joined()), Set(PokemonNature.allCases))
        for (i, row) in NatureGrid.rows.enumerated() {
            for (j, nature) in row.enumerated() where i != j {
                XCTAssertGreaterThan(nature.modifier(for: NatureGrid.stats[i]), 1, "\(nature)")
                XCTAssertLessThan(nature.modifier(for: NatureGrid.stats[j]), 1, "\(nature)")
            }
        }
    }

    func testCellsShowTheRaisedAndLoweredStat() {
        let l = L(.en)
        XCTAssertEqual(NaturePicker.changeLabel(.adamant, l: l),
                       "↑\(l.statName("attack")) ↓\(l.statName("special_attack"))")
        XCTAssertEqual(NaturePicker.changeLabel(.serious, l: l), "—")
    }

    func testOnlyTheCurrentNatureCellIsMarkedCurrent() {
        for nature in PokemonNature.allCases {
            let mark = NaturePicker.mark(nature, current: .lonely, picked: .timid)
            XCTAssertEqual(mark, nature == .lonely ? .current : nature == .timid ? .picked : .none, "\(nature)")
        }
    }

    /// Green points of the current-nature outline, and where they sit across the grid (0…1).
    private func greenOutline(current: PokemonNature?) async throws -> (points: Int, centerX: CGFloat) {
        let fixture = try TrainingFixture(self)
        let s = try await fixture.store(TrainingFixture.state(dex: [TrainingFixture.graduate(boxID, speciesID: 95)]))
        let width = PopoverMetrics.scrollContentWidth
        let picker = NaturePicker(store: s, individualID: boxID, pokemonName: "Onix", current: current,
                                  onClose: {}, onChange: {})
            .frame(width: width).background(Color.white).environment(\.colorScheme, .light)
        let host = OffscreenRender.host(picker, size: CGSize(width: width, height: 320), appearance: .aqua)
        try await OffscreenRender.settle(host)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: OffscreenRender.png(of: host, scale: 2)))
        var count = 0
        var sumX = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if c.greenComponent > 0.6, c.redComponent < 0.45, c.blueComponent < 0.55 {
                    count += 1
                    sumX += x
                }
            }
        }
        let center = count == 0 ? 0 : CGFloat(sumX) / CGFloat(count) / CGFloat(bitmap.pixelsWide)
        return (count / 4, center)
    }

    func testTheCurrentNatureIsOutlinedInItsGridCell() async throws {
        let none = try await greenOutline(current: nil)
        XCTAssertLessThan(none.points, 10, "no outline without a current nature")
        let lonely = try await greenOutline(current: .lonely)
        XCTAssertGreaterThan(lonely.points, 100)
        XCTAssertEqual(lonely.centerX, 0.3, accuracy: 0.1, "Lonely sits in the second column")
        let brave = try await greenOutline(current: .brave)
        XCTAssertEqual(brave.centerX, 0.9, accuracy: 0.1, "Brave sits in the last column")
    }

    private func documentHeight(_ root: NSView) -> CGFloat {
        NativeControls.descendants(root).compactMap { ($0 as? NSClipView)?.documentView?.frame.height }.max() ?? 0
    }

    private func boxPageHeight(_ s: CompanionStore, nav: PopoverNavigation) async throws -> CGFloat {
        let width = PopoverMetrics.contentWidth
        let host = OffscreenRender.host(BoxView(store: s, navigation: nav).frame(width: width),
                                        size: CGSize(width: width, height: 700), appearance: .aqua)
        let window = OffscreenRender.windowHosting(host, appearance: .aqua)
        defer { window.close() }
        try await OffscreenRender.settle(host) { self.documentHeight(host) > 0 }
        return documentHeight(host)
    }

    func testTheBagPathReachesThePickerForABoxPokemon() async throws {
        let fixture = try TrainingFixture(self)
        let s = try await fixture.store(TrainingFixture.state(dex: [TrainingFixture.graduate(boxID, speciesID: 95)],
                                                              inventory: ["mint": 1]),
                                        loadDetailsFor: [95])
        let target = try XCTUnwrap(s.trainingTargets(for: .mint).first { $0.id == boxID })

        let plain = PopoverNavigation()
        plain.openBoxDetail(id: boxID)
        let withoutPicker = try await boxPageHeight(s, nav: plain)

        let nav = PopoverNavigation()
        TrainingTargetPicker.use(.mint, on: target, nav: nav)
        XCTAssertEqual(nav.tab, .box)
        XCTAssertEqual(nav.boxDetailID, boxID)
        XCTAssertTrue(nav.boxDetailOpensNaturePicker)
        let withPicker = try await boxPageHeight(s, nav: nav)
        XCTAssertGreaterThan(withPicker - withoutPicker, 150, "the 5×5 picker is open on the Box page")
        XCTAssertFalse(nav.boxDetailOpensNaturePicker, "the next Box page opens without it")

        let capsule = PopoverNavigation()
        TrainingTargetPicker.use(.abilityCapsule, on: target, nav: capsule)
        XCTAssertFalse(capsule.boxDetailOpensNaturePicker)
    }
}
