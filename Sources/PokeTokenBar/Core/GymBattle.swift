import Foundation

/// The body of `POST /v1/gym/battle`. It never sends `carried`, so every battle of a run starts fully healed.
struct GymBattleRequest: Encodable, Equatable, Sendable {
    let gymId: String
    let team: [PartyMember]

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(self)
    }
}

/// One member of either side at the end of a battle.
struct GymFighter: Decodable, Equatable, Sendable {
    let pokemonId: Int
    let name: String
    let level: Int
    let types: [String]
    let shiny: Bool
    /// Share of max HP left, 0...100. 0 fainted; nil was never sent out.
    let hp: Int?
}

struct GymLogLine: Decodable, Equatable, Sendable {
    /// 0 the player, 1 the trainer, nil a line that names no side.
    let side: Int?
    let text: String
}

struct GymTurn: Decodable, Equatable, Sendable {
    let turn: Int
    let lines: [GymLogLine]
}

struct GymRunStep: Decodable, Equatable, Sendable {
    let id: String
    let step: Int
    let steps: Int
    let first: String
    /// The battle to send after a win; nil after a loss and on the last step.
    let next: String?
}

/// One step of the battle for the replay: `switch`, `move`, `damage`, `faint` or `status`. `member` indexes that
/// side's roster; `hp` and `status` come with `switch`, `hp` with `damage`, `status` (nil when it ends) with `status`.
struct GymBattleEvent: Decodable, Equatable, Sendable {
    let turn: Int
    let type: String
    let side: Int
    let member: Int
    var hp: Int?
    var status: String?
    var move: String?
}

/// The reply of `POST /v1/gym/battle`.
struct GymBattleOutcome: Decodable, Equatable, Sendable {
    let gymId: String
    let kind: String
    let won: Bool
    let turns: Int
    let seed: Int
    let trainer: GymTrainer
    let playerTeam: [GymFighter]
    let foeTeam: [GymFighter]
    let log: [GymTurn]
    /// Nil from a bot older than the replay.
    let events: [GymBattleEvent]?
    let run: GymRunStep?

    static func decode(_ data: Data) throws -> GymBattleOutcome {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(GymBattleOutcome.self, from: data)
    }
}
