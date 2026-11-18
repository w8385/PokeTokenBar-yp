import Foundation
import XCTest
@testable import PokeTokenBar

@MainActor
final class GymReplayTests: XCTestCase {
    private func outcome(turns: Int = 5, events: [[String: Any]]? = GymFixtures.replayEvents) throws -> GymBattleOutcome {
        try GymBattleOutcome.decode(GymFixtures.outcomeData(
            gymID: "kanto-1", kind: "gym", won: true, hps: [0, 100, nil], foeHps: [0, 0], turns: turns, events: events))
    }

    private func replay(turns: Int = 5, events: [[String: Any]]? = GymFixtures.replayEvents) throws -> GymReplay {
        try XCTUnwrap(GymReplay(try outcome(turns: turns, events: events)))
    }

    func testAReplyWithoutEventsDecodesAndHasNoReplay() throws {
        let old = try outcome(events: nil)

        XCTAssertNil(old.events)
        XCTAssertNil(GymReplay(old))
        XCTAssertNil(GymReplay(try outcome(events: [])))
    }

    func testEventsDecodeWithTheirOptionalFields() throws {
        let events = try XCTUnwrap(try outcome().events)

        XCTAssertEqual(events.count, GymFixtures.replayEvents.count)
        XCTAssertEqual(events[0], GymBattleEvent(turn: 0, type: "switch", side: 0, member: 0, hp: 100))
        XCTAssertEqual(events[2], GymBattleEvent(turn: 1, type: "move", side: 0, member: 0, move: "10만볼트"))
        XCTAssertEqual(events[12], GymBattleEvent(turn: 3, type: "status", side: 0, member: 0, status: "burn"))
    }

    func testUnknownTypesAndMembersOutsideTheRostersAreSkipped() throws {
        let extra = GymFixtures.replayEvents + [
            GymFixtures.event(5, "weather", side: 0, member: 0),
            GymFixtures.event(5, "damage", side: 1, member: 2, hp: 10),
            GymFixtures.event(5, "damage", side: 2, member: 0, hp: 10),
        ]

        XCTAssertEqual(try replay(events: extra).events.count, GymFixtures.replayEvents.count)
    }

    func testTheFirstFrameShowsNobodyAndTheLastMatchesTheRosters() throws {
        let replay = try replay()
        let start = replay.frame(after: 0)
        let end = replay.frame(after: replay.events.count)

        XCTAssertEqual(start.active, [nil, nil])
        XCTAssertEqual(end.turn, 5)
        XCTAssertEqual(end.active, [1, 1])
        XCTAssertEqual(end.hp, [[0, 100, nil], [0, 0]])
        XCTAssertEqual(end.lastMove, GymReplay.Move(side: 0, member: 1, name: "파도타기"))
    }

    func testAStatusShowsUntilItsHolderFaints() throws {
        let replay = try replay()

        let burned = replay.frame(after: 13)
        XCTAssertEqual(burned.status[0][0], "burn")
        XCTAssertEqual(burned.hp[0][0], 30)
        XCTAssertEqual(replay.frame(after: 16).hp[0][0], 24)
        XCTAssertEqual(replay.frame(after: 19).hp[0][0], 0)
    }

    func testAShortBattleTakesTheSlowestPacePerTurn() throws {
        let replay = try replay(turns: 5)

        XCTAssertEqual(total(replay), 5 * GymReplay.slowestTurn, accuracy: 0.001)
        XCTAssertEqual(replay.delay(before: 1), .zero)
    }

    func testALongBattleFitsTheLengthWhateverItsTurnCount() throws {
        for (turns, seconds) in [(25, 25.0), (60, 30.0), (20, 20.0)] {
            let events = (1...turns).map { GymFixtures.event($0, "move", side: 0, member: 0, move: "몸통박치기") }

            XCTAssertEqual(total(try replay(turns: turns, events: events)), seconds, accuracy: 0.001, "\(turns) turns")
        }
    }

    func testSkipShowsTheEndAndAdvanceStopsThere() throws {
        let player = GymReplayPlayer(try replay())
        XCTAssertEqual(player.shown, 2)
        XCTAssertEqual(player.frame.active, [0, 0])

        player.advance()
        XCTAssertEqual(player.shown, 3)
        player.skip()
        XCTAssertTrue(player.finished)
        player.advance()
        XCTAssertEqual(player.shown, player.replay.events.count)
    }

    func testFastForwardToggles() throws {
        let player = GymReplayPlayer(try replay())

        player.toggleSpeed()
        XCTAssertTrue(player.fast)
        player.toggleSpeed()
        XCTAssertFalse(player.fast)
    }

    func testTheFinaleEventFlagsOnlyTheTurnTheHiddenMemberComesOut() throws {
        let events = GymFixtures.replayEvents.dropLast() + [
            GymFixtures.event(5, "faint", side: 1, member: 1),
            GymFixtures.event(5, GymBattleEvent.finale, side: 1, member: 2),
            GymFixtures.event(5, "switch", side: 1, member: 2, hp: 100),
            GymFixtures.event(6, "move", side: 0, member: 1, move: "파도타기"),
            GymFixtures.event(6, "damage", side: 1, member: 2, hp: 0),
            GymFixtures.event(6, "faint", side: 1, member: 2),
        ]
        let outcome = try GymBattleOutcome.decode(GymFixtures.outcomeData(
            gymID: "kanto-champion", kind: "champion", won: true, hps: [0, 100, nil], foeHps: [0, 0, 0], turns: 6,
            events: Array(events)))
        let replay = try XCTUnwrap(GymReplay(outcome))
        let entrance = try XCTUnwrap(replay.events.firstIndex { $0.type == GymBattleEvent.finale })

        XCTAssertFalse(replay.frame(after: entrance).finale)
        XCTAssertTrue(replay.frame(after: entrance + 1).finale)
        XCTAssertTrue(replay.frame(after: entrance + 2).finale)
        XCTAssertEqual(replay.frame(after: entrance + 2).active[1], 2)
        XCTAssertFalse(replay.frame(after: entrance + 3).finale)
    }

    func testAFormEventDecodesItsIdAndAnOldBotsReplayShowsEveryRosterId() throws {
        let mega = try replay(events: GymFixtures.megaReplayEvents)
        let old = try replay()

        XCTAssertEqual(mega.events[10], GymBattleEvent(turn: 2, type: "form", side: 1, member: 1, pokemonId: 10034))
        for count in 0...old.events.count {
            XCTAssertEqual(old.frame(after: count).form, [[nil, nil, nil], [nil, nil]], "after \(count)")
        }
        XCTAssertEqual(old.last.spriteID(side: 1, member: 1, roster: try outcome().foeTeam), 2)
    }

    func testAFormEventChangesOnlyItsMembersSprite() throws {
        let replay = try replay(events: GymFixtures.megaReplayEvents)
        let roster = try outcome(events: GymFixtures.megaReplayEvents)

        let before = replay.frame(after: 10)
        XCTAssertEqual(before.active[1], 1)
        XCTAssertEqual(before.spriteID(side: 1, member: 1, roster: roster.foeTeam), 2)
        let after = replay.frame(after: 11)
        XCTAssertEqual(after.spriteID(side: 1, member: 1, roster: roster.foeTeam), 10034)
        XCTAssertEqual(after.spriteID(side: 0, member: 0, roster: roster.playerTeam), 25)
        XCTAssertEqual(after.spriteID(side: 1, member: 0, roster: roster.foeTeam), 1)
        XCTAssertEqual(replay.last.form, [[nil, nil, nil], [nil, 10034]])
    }

    func testAFormEventKeepsItsHoldersHPAndStatus() throws {
        let events = Array(GymFixtures.replayEvents.prefix(13)) + [GymFixtures.form(3, side: 0, member: 0, id: 10034)]
        let replay = try replay(events: events)
        let frame = replay.last

        XCTAssertEqual(frame.form[0][0], 10034)
        XCTAssertEqual(frame.status[0][0], "burn")
        XCTAssertEqual(frame.hp[0][0], 30)
    }

    func testANewMemberShowsItsRosterIdAndAPivotedMegaComesBackMega() throws {
        let events = [
            GymFixtures.event(0, "switch", side: 0, member: 0, hp: 100),
            GymFixtures.event(0, "switch", side: 1, member: 0, hp: 100),
            GymFixtures.form(1, side: 1, member: 0, id: 10034),
            GymFixtures.event(1, "switch", side: 1, member: 1, hp: 100),
            GymFixtures.event(2, "switch", side: 1, member: 0, hp: 100),
        ]
        let replay = try replay(events: events)
        let foes = try outcome(events: events).foeTeam

        let swapped = replay.frame(after: 4)
        XCTAssertEqual(swapped.active[1], 1)
        XCTAssertEqual(swapped.spriteID(side: 1, member: 1, roster: foes), 2)
        let back = replay.frame(after: 5)
        XCTAssertEqual(back.active[1], 0)
        XCTAssertEqual(back.spriteID(side: 1, member: 0, roster: foes), 10034)
    }

    func testAMegaWithNoSpriteKeepsTheBaseSprite() throws {
        let missing = try XCTUnwrap(MegaStone.missingSpriteIDs.first)
        let events = GymFixtures.replayEvents.prefix(2) + [GymFixtures.form(1, side: 1, member: 0, id: missing)]
        let replay = try replay(events: Array(events))

        XCTAssertEqual(replay.events.count, 3)
        XCTAssertEqual(replay.last.spriteID(side: 1, member: 0, roster: try outcome().foeTeam), 1)
    }

    private func total(_ replay: GymReplay) -> Double {
        replay.events.indices.map { replay.delay(before: $0) / .seconds(1) }.reduce(0, +)
    }
}
