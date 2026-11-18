import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// Where the result screen's next step shows, read from pixels: the first row where two renders that differ only
/// in that button part ways. Sprite ids 0 have no image, so nothing loads between two renders.
@MainActor
final class GymReplayNextButtonTests: XCTestCase {
    private let l = L(.ko)

    func testAFinishedReplayShowsTheNextStepInItsHeaderRowWhereSkipWas() async throws {
        let replay = try XCTUnwrap(GymReplay(try outcome(events: GymFixtures.replayEvents)))
        let next = GymReplayView.Next(title: l.gymRestartRun, busy: false, action: {})
        func render(shown: Int, next: GymReplayView.Next?) async throws -> NSBitmapImageRep {
            let player = GymReplayPlayer(replay, shown: shown)
            return try await bitmap(GymReplayView(player: player, outcome: try outcome(events: GymFixtures.replayEvents),
                                                  l: l, autoplay: false, next: next), height: 240)
        }
        let done = replay.events.count
        let bare = try await render(shown: done, next: nil)
        let withNext = try await render(shown: done, next: next)
        let playing = try await render(shown: 2, next: next)
        let header = try XCTUnwrap(Self.firstDifferingRow(bare, withNext))
        let skip = try XCTUnwrap(Self.firstDifferingRow(bare, playing))

        XCTAssertLessThan(header, 12)
        XCTAssertLessThan(skip, 12)
    }

    func testASkippedResultShowsTheNextStepAboveTheReplayPanelAndNoneMidReplay() async throws {
        let events = GymFixtures.replayEvents
        let (with, height) = try await result(events: events, shown: Int.max, primary: l.gymRestartRun)
        let (without, _) = try await result(events: events, shown: Int.max, primary: nil)
        let first = try XCTUnwrap(Self.firstDifferingRow(with, without))

        XCTAssertLessThan(first, height * 0.3, "the top copy of the next step sits in the replay header")
        let (playing, _) = try await result(events: events, shown: nil, primary: l.gymRestartRun)
        let (playingBare, _) = try await result(events: events, shown: nil, primary: nil)
        XCTAssertNil(Self.firstDifferingRow(playing, playingBare), "nothing of the next step shows mid-replay")
    }

    func testAResultWithoutAReplayKeepsItsOneNextStepAtTheBottom() async throws {
        let (with, height) = try await result(events: nil, shown: nil, primary: l.gymRestartRun)
        let (without, _) = try await result(events: nil, shown: nil, primary: nil)
        let first = try XCTUnwrap(Self.firstDifferingRow(with, without))

        XCTAssertGreaterThan(first, height * 0.75)
    }

    private func outcome(events: [[String: Any]]?) throws -> GymBattleOutcome {
        let blank = { (count: Int) in (0..<count).map { GymFixtures.fighter(0, name: "M\($0)", hp: 0) } }
        return try GymBattleOutcome.decode(GymFixtures.outcomeData(
            gymID: "kanto-elite-2", kind: "elite", won: false, turns: 5, events: events, teams: (blank(3), blank(2))))
    }

    /// The finished-or-playing result screen and its height in points.
    private func result(events: [[String: Any]]?, shown: Int?, primary: String?) async throws -> (NSBitmapImageRep, CGFloat) {
        let catalog = try GymCatalog.decode(GymFixtures.catalogData())
        let opponent = try XCTUnwrap(catalog.region("kanto")?.elite.battles[1])
        let view = GymResultView(record: GymFightRecord(opponent: opponent, outcome: try outcome(events: events), reward: nil),
                                 language: .ko, l: l, regionName: "Kanto", tmName: { _ in nil },
                                 primaryTitle: primary, busy: false, onPrimary: {}, onClose: {}, replayShown: shown)
        let height = LayoutMeasure.size(view, width: PopoverMetrics.contentWidth).height
        return (try await bitmap(view, height: height), height)
    }

    private func bitmap<V: View>(_ view: V, height: CGFloat) async throws -> NSBitmapImageRep {
        let size = CGSize(width: PopoverMetrics.contentWidth, height: height)
        let host = OffscreenRender.host(view.frame(width: size.width, height: size.height, alignment: .top)
            .background(Color.white).environment(\.colorScheme, .light), size: size, appearance: .aqua)
        try await OffscreenRender.settle(host)
        return try OffscreenRender.bitmap(of: host, scale: 1)
    }

    /// The first row, in points from the top, where `a` and `b` differ; nil when they are the same.
    static func firstDifferingRow(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> CGFloat? {
        guard let left = a.bitmapData, let right = b.bitmapData else { return 0 }
        let rows = min(a.pixelsHigh, b.pixelsHigh)
        for row in 0..<rows where memcmp(left + row * a.bytesPerRow, right + row * b.bytesPerRow,
                                         min(a.bytesPerRow, b.bytesPerRow)) != 0 {
            return CGFloat(row) * a.size.height / CGFloat(a.pixelsHigh)
        }
        return a.pixelsHigh == b.pixelsHigh ? nil : CGFloat(rows)
    }
}
