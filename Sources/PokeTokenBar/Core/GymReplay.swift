import Foundation
import Observation

/// A finished gym battle played back from the bot's `events`: about a second a turn, 20 to 30 seconds for a battle
/// of 20 turns or more.
struct GymReplay: Equatable, Sendable {
    static let length: ClosedRange<Double> = 20...30

    struct Move: Equatable, Sendable {
        let side: Int
        let member: Int
        let name: String
        var id: Int? = nil
    }

    /// Both sides after some events: who is out, each member's HP share (nil until it comes out) and status.
    struct Frame: Equatable, Sendable {
        var turn = 0
        var active: [Int?] = [nil, nil]
        var hp: [[Int?]]
        var status: [[String?]]
        /// The `/pokemon` id a member fights as after a `form` event; nil shows its roster id.
        var form: [[Int?]]
        var lastMove: Move?
        /// The champion's hidden member came out this turn.
        var finale = false

        func spriteID(side: Int, member: Int, roster: [GymFighter]) -> Int {
            form[side][member] ?? roster[member].pokemonId
        }
    }

    let events: [GymBattleEvent]
    let turns: Int
    private let sizes: [Int]
    private let eventsPerTurn: [Int: Int]

    init?(_ outcome: GymBattleOutcome) {
        let sizes = [outcome.playerTeam.count, outcome.foeTeam.count]
        let known = (outcome.events ?? []).filter { event in
            Self.types.contains(event.type) && (0...1).contains(event.side) && sizes[event.side] > event.member
                && event.member >= 0
        }
        guard !known.isEmpty else { return nil }
        events = known
        turns = outcome.turns
        self.sizes = sizes
        eventsPerTurn = Dictionary(known.map { ($0.turn, 1) }, uniquingKeysWith: +)
    }

    private static let types: Set<String> = ["switch", "move", "damage", "faint", "status", GymBattleEvent.finale,
                                             GymBattleEvent.form]

    /// Both sides when the battle ended: each member's last HP share and the form it ended in.
    var last: Frame { frame(after: events.count) }

    func frame(after count: Int) -> Frame {
        var frame = Frame(hp: sizes.map { Array(repeating: nil, count: $0) },
                          status: sizes.map { Array(repeating: nil, count: $0) },
                          form: sizes.map { Array(repeating: nil, count: $0) })
        for event in events.prefix(count) {
            if event.turn != frame.turn { frame.finale = false }
            frame.turn = event.turn
            switch event.type {
            case GymBattleEvent.finale:
                frame.finale = true
            case GymBattleEvent.form:
                if let id = event.pokemonId, !MegaStone.missingSpriteIDs.contains(id) {
                    frame.form[event.side][event.member] = id
                }
            case "switch":
                frame.active[event.side] = event.member
                frame.hp[event.side][event.member] = event.hp ?? 100
                frame.status[event.side][event.member] = event.status
            case "move":
                frame.lastMove = Move(side: event.side, member: event.member, name: event.move ?? "", id: event.moveId)
            case "damage":
                frame.hp[event.side][event.member] = event.hp
            case "faint":
                frame.hp[event.side][event.member] = 0
            default:
                frame.status[event.side][event.member] = event.status
            }
        }
        return frame
    }

    /// The wait before event `index` shows: a turn's share of the whole length, split among its events.
    /// The opening send-outs show at once.
    func delay(before index: Int) -> Duration {
        let turn = events[index].turn
        return turn == 0 ? .zero : .seconds(secondsPerTurn / Double(eventsPerTurn[turn] ?? 1))
    }

    /// A short battle plays at `slowestTurn` a turn; a long one is squeezed into `length`.
    var secondsPerTurn: Double {
        let total = min(max(Double(turns), Self.length.lowerBound), Self.length.upperBound)
        return min(total / Double(max(eventsPerTurn.keys.filter { $0 > 0 }.count, 1)), Self.slowestTurn)
    }

    static let slowestTurn = 1.5
}

/// Plays a replay forward: `shown` events so far, at normal speed or `fastSpeed` times faster.
@MainActor
@Observable
final class GymReplayPlayer {
    static let fastSpeed = 3

    let replay: GymReplay
    private(set) var shown: Int
    private(set) var fast = false

    /// Starts with the opening send-outs already shown, so the first frame is never empty.
    init(_ replay: GymReplay, shown: Int? = nil) {
        self.replay = replay
        self.shown = min(shown ?? replay.events.prefix { $0.turn == 0 }.count, replay.events.count)
    }

    var finished: Bool { shown >= replay.events.count }
    var frame: GymReplay.Frame { replay.frame(after: shown) }

    func advance() { if !finished { shown += 1 } }
    func skip() { shown = replay.events.count }
    func toggleSpeed() { fast.toggle() }

    func play(advance step: @MainActor () -> Void) async {
        while !finished {
            let wait = replay.delay(before: shown) / (fast ? Self.fastSpeed : 1)
            do { try await Task.sleep(for: wait) } catch { return }
            step()
        }
    }
}
