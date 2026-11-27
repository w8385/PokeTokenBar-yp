import Foundation

enum TowerMode: String, CaseIterable, Codable, Sendable {
    case entry, rental
}

/// One mode's record as the bot last reported it.
struct TowerModeRecord: Codable, Equatable, Sendable {
    var streak = 0
    var best = 0
    var trophies: [String] = []

    init(streak: Int = 0, best: Int = 0, trophies: [String] = []) {
        self.streak = streak
        self.best = best
        self.trophies = trophies
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        streak = max(0, (try? c.decode(Int.self, forKey: .streak)) ?? 0)
        best = max(streak, (try? c.decode(Int.self, forKey: .best)) ?? 0)
        trophies = (try? c.decode([String].self, forKey: .trophies)) ?? []
    }

    private enum CodingKeys: String, CodingKey { case streak, best, trophies }
}

/// The battle tower in the save: BP to spend, the team `entry` mode fights with, and each mode's record. The bot owns
/// the runs; the records mirror its replies.
struct TowerProgress: Codable, Equatable, Sendable {
    static let teamSize = 3
    static let maxBP = 999_999

    var bp = 0
    /// Instance ids of the tower entry, apart from the Slack and gym entry.
    var entry: [String] = []
    var records: [String: TowerModeRecord] = [:]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bp = min(max((try? c.decode(Int.self, forKey: .bp)) ?? 0, 0), Self.maxBP)
        var seen = Set<String>()
        let ids = (try? c.decode([String].self, forKey: .entry)) ?? []
        entry = Array(ids.filter { seen.insert($0).inserted }.prefix(Self.teamSize))
        records = (try? c.decode([String: TowerModeRecord].self, forKey: .records)) ?? [:]
    }

    private enum CodingKeys: String, CodingKey { case bp, entry, records }

    func record(_ mode: TowerMode) -> TowerModeRecord { records[mode.rawValue] ?? TowerModeRecord() }

    /// A live `entry` run keeps its team until it ends.
    var entryLocked: Bool { record(.entry).streak > 0 }

    mutating func mirror(_ run: TowerRun) {
        guard TowerMode(rawValue: run.mode) != nil else { return }
        records[run.mode] = TowerModeRecord(streak: run.streak, best: run.best, trophies: run.trophies)
    }

    mutating func earn(_ points: Int) { bp = min(bp + max(points, 0), Self.maxBP) }
}

/// A rental as the bot builds it: fixed moves and item, IVs of the battle it fights.
struct TowerRental: Decodable, Equatable, Sendable {
    let pokemonId: Int
    let moves: [Int]
    let heldItem: String?
    let ivs: Int
    let nature: String?
}

/// A run as every tower reply carries it.
struct TowerRun: Decodable, Equatable, Sendable {
    struct Next: Decodable, Equatable, Sendable {
        let battle: Int
        let set: Int
        let owner: Bool
    }

    let mode: String
    let streak: Int
    let best: Int
    let trophies: [String]
    let next: Next
    /// `rental` only: the six on offer before a pick, the three picked, the three just beaten while a swap is open.
    var offer: [TowerRental]? = nil
    var team: [TowerRental]? = nil
    var beaten: [TowerRental]? = nil

    static func decode(_ data: Data) throws -> TowerRun { try TowerJSON.decoder.decode(TowerRun.self, from: data) }
}

/// What one battle paid, read from the reply's `tower` next to the run.
struct TowerGain: Decodable, Equatable, Sendable {
    let battle: Int
    let set: Int
    let bp: Int
    /// The trophy this win earned for the first time.
    let trophy: String?
}

/// The reply of `POST /v1/tower/battle`.
struct TowerOutcome: Equatable, Sendable {
    let battle: GymBattleOutcome
    let opponent: GymOpponent
    let run: TowerRun
    let gain: TowerGain

    static func decode(_ data: Data) throws -> TowerOutcome {
        struct Body: Decodable {
            let opponent: GymOpponent
            let tower: TowerRun
        }
        struct Paid: Decodable { let tower: TowerGain }
        let body = try TowerJSON.decoder.decode(Body.self, from: data)
        return TowerOutcome(battle: try GymBattleOutcome.decode(data), opponent: body.opponent, run: body.tower,
                            gain: try TowerJSON.decoder.decode(Paid.self, from: data).tower)
    }
}

struct TowerRank: Decodable, Equatable, Hashable, Sendable {
    let name: String?
    let best: Int
}

/// The reply of `GET /v1/tower/record`.
struct TowerRecord: Decodable, Equatable, Sendable {
    let modes: [String: TowerRun]
    let ranking: [String: [TowerRank]]

    static func decode(_ data: Data) throws -> TowerRecord { try TowerJSON.decoder.decode(TowerRecord.self, from: data) }
}

struct TowerBattleRequest: Encodable, Equatable, Sendable {
    let mode: String
    let team: [PartyMember]?

    func encoded() throws -> Data { try TowerJSON.encoder.encode(self) }
}

enum TowerJSON {
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = .sortedKeys
        return encoder
    }
}

/// The tower entry: three owned Pokémon of different species.
enum TowerEntry {
    /// The owned members of `ids`, in order.
    static func members(state: CompanionState, ids: [String]) -> [BattleCandidate] {
        let owned = BattleEntry.candidates(in: state)
        return ids.compactMap { id in owned.first { $0.id == id } }
    }

    /// The team the bot gets, nil unless all three are owned and of different species.
    static func team(state: CompanionState, ids: [String], moveChoices: [String: MoveChoice]) -> [PartyMember]? {
        let picked = members(state: state, ids: ids)
        guard picked.count == TowerProgress.teamSize, Set(picked.map(\.speciesID)).count == picked.count else { return nil }
        return BattleEntry.party(state: state, slots: picked.map { BattleEntrySlot(instanceID: $0.id) },
                                 moveChoices: moveChoices, rentalSpeciesID: BattleEntry.rentalSpeciesIDs[0])
    }

    /// Candidates the picker must not offer for slot `replacing`: another slot already has their species.
    static func sameSpecies(state: CompanionState, ids: [String], replacing: String?) -> Set<String> {
        let all = BattleEntry.candidates(in: state)
        let taken = Set(members(state: state, ids: ids).filter { $0.id != replacing }.map(\.speciesID))
        return Set(all.filter { !ids.contains($0.id) && taken.contains($0.speciesID) }.map(\.id))
    }

    /// `ids` with slot `slot` (0-based) set to `id`, or emptied when `id` is nil.
    static func setting(_ id: String?, at slot: Int, in ids: [String]) -> [String] {
        var slots: [String?] = (0..<TowerProgress.teamSize).map { $0 < ids.count ? ids[$0] : nil }
        guard slots.indices.contains(slot) else { return ids }
        slots[slot] = id
        return slots.compactMap { $0 }
    }
}
