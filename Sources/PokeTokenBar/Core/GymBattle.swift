import Foundation

/// HP and status one team member keeps from one battle of a run into the next.
struct GymCarry: Codable, Equatable, Sendable {
    /// Share of max HP, 0...100.
    let hp: Int
    let status: String?

    init(hp: Int, status: String?) {
        self.hp = hp
        self.status = status
    }

    /// The bot wants an explicit `null` status, not a missing key.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hp, forKey: .hp)
        try container.encode(status, forKey: .status)
    }

    private enum CodingKeys: String, CodingKey { case hp, status }
}

/// The body of `POST /v1/gym/battle`.
struct GymBattleRequest: Encodable, Equatable, Sendable {
    let gymId: String
    let team: [PartyMember]
    /// One entry per `team` member (nil is full HP, no status); only for a battle in a run.
    var carried: [GymCarry?]? = nil

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
    let run: GymRunStep?
    /// Ready to send back as the next `carried`; nil unless the battle was in a run, won, and not the last.
    let carry: [GymCarry?]?

    static func decode(_ data: Data) throws -> GymBattleOutcome {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(GymBattleOutcome.self, from: data)
    }
}
