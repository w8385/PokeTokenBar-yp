import Foundation

/// Wire types for the bot's trade endpoints (`bot/API.md`). Keys are explicit and the coders are plain:
/// the party body's snake-case strategy would rename the keys inside the nested `DexEntry`.
///
/// One tradable individual. `entry` is the whole `DexEntry`; the bot stores it as opaque JSON and hands the
/// other side's copy back unchanged, so the receiver gets species, form, shiny, nature, IVs and level as sent.
struct TradePoolEntry: Codable, Sendable {
    let id: String
    let pokemonID: Int
    let level: Int
    let shiny: Bool
    let name: String
    let entry: DexEntry
    /// The party member it would battle as, so Slack can put it in the lineup. `TradePool.encode` sends it in
    /// the party's snake-case keys; deliveries never carry it.
    var member: PartyMember? = nil

    enum CodingKeys: String, CodingKey {
        case id, level, shiny, name, entry
        case pokemonID = "pokemon_id"
    }
}

/// A completed trade this app has not acknowledged yet.
struct TradeDelivery: Decodable, Sendable {
    let tradeID: String
    /// The id of this app's individual that went out.
    let giveID: String
    let fromName: String
    let receive: TradePoolEntry
    /// The trade item that left with `giveID`, as the bot settled it. Nil with `reportsGiveHeldItem` false means
    /// an older bot that does not say.
    let giveHeldItem: String?
    let reportsGiveHeldItem: Bool

    enum CodingKeys: String, CodingKey {
        case receive
        case tradeID = "trade_id"
        case giveID = "give_id"
        case fromName = "from_name"
        case giveHeldItem = "give_held_item"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tradeID = try c.decode(String.self, forKey: .tradeID)
        giveID = try c.decode(String.self, forKey: .giveID)
        fromName = try c.decode(String.self, forKey: .fromName)
        receive = try c.decode(TradePoolEntry.self, forKey: .receive)
        reportsGiveHeldItem = c.contains(.giveHeldItem)
        giveHeldItem = try? c.decodeIfPresent(String.self, forKey: .giveHeldItem)
    }
}

/// The player's open miracle trade offer (`GET /v1/miracle`).
struct MiracleOffer: Decodable, Equatable, Sendable {
    let offerID: String
    let giveID: String
    let name: String
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case name
        case offerID = "offer_id"
        case giveID = "give_id"
        case expiresAt = "expires_at"
    }
}

struct MiracleReply: Decodable, Sendable {
    let offer: MiracleOffer?
}

enum MiracleStatus: Equatable, Sendable {
    /// The bot has no battle channel, or predates miracle trades.
    case unavailable
    case nothingListed
    case open(MiracleOffer)
}

enum MiraclePost: Equatable, Sendable {
    case posted(MiracleOffer)
    /// The bot said no; the text is its short reason.
    case refused(String)
    case unavailable
    case failed
}

struct TradeCoworker: Decodable, Equatable, Sendable, Identifiable {
    let id: String
    let name: String
}

/// `GET /v1/trades`. A delivery that cannot be decoded is dropped, not acknowledged, so the bot offers it
/// again after an update; one bad entry never hides the others.
struct TradeSyncReply: Sendable {
    let deliveries: [TradeDelivery]
    /// Individuals in open trades. Empty from an older bot, which leaves nothing locked.
    let lockedIDs: Set<String>

    static func decode(_ data: Data) -> TradeSyncReply {
        struct Root: Decodable { let trades: Inner? }
        struct Inner: Decodable {
            let deliveries: [Lossy<TradeDelivery>]?
            let lockedIDs: [String]?
            enum CodingKeys: String, CodingKey { case deliveries, lockedIDs = "locked_ids" }
        }
        let inner = (try? JSONDecoder().decode(Root.self, from: data))?.trades
        return TradeSyncReply(deliveries: (inner?.deliveries ?? []).compactMap(\.value),
                              lockedIDs: Set(inner?.lockedIDs ?? []))
    }

    private struct Lossy<Value: Decodable>: Decodable {
        let value: Value?
        init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
    }
}

enum TradeRefusal: Equatable, Sendable {
    /// The Pokémon being raised.
    case raising
    /// The line (or egg) set aside while a graduate is raised: resume it first.
    case parked
    /// The battle pick: move it first.
    case fighting
    /// Arrived by trade and has not finished evolving.
    case arriving
    /// Released, traded away, or a species this build cannot show.
    case unavailable
    /// Past the newest `TradePool.maxEntries` tradable ones, so the bot never gets it.
    case poolFull
}

enum TradePool {
    static let maxEntries = 2_000
    static let maxEntryBytes = 2_000
    static let maxBytes = 2 + maxEntries * (maxEntryBytes + 1)

    /// Everyone in the battle lineup (up to six), which also covers the auto fighter when nothing is picked.
    static func fightingIDs(state: CompanionState, slots: [BattleEntrySlot]) -> Set<String> {
        Set(BattleEntry.lineup(state: state, slots: slots).map(\.id))
    }

    /// `activeID` is the line Pokémon's synthetic Box id (never in the dex); `raisedID` is the raised graduate.
    static func refusal(for entry: DexEntry, fightingIDs: Set<String>, activeID: String?,
                        raisedID: String? = nil, lineParked: Bool = false) -> TradeRefusal? {
        if entry.id == raisedID { return .raising }
        if entry.id == activeID { return lineParked ? .parked : .raising }
        if entry.releasedAt != nil || entry.profile == nil || !isSendable(entry) { return .unavailable }
        if fightingIDs.contains(entry.id) { return .fighting }
        if entry.tradeEvolutionPending == true { return .arriving }
        return nil
    }

    /// The tradable individuals newest first, cut at `maxEntries`: who `build` sends.
    static func listed(state: CompanionState, fightingIDs: Set<String>) -> [DexEntry] {
        Array(state.dex
            .filter { refusal(for: $0, fightingIDs: fightingIDs, activeID: nil, raisedID: state.raisedEntryID) == nil }
            .sorted { ($0.caughtAt ?? .distantPast) > ($1.caughtAt ?? .distantPast) }
            .prefix(maxEntries))
    }

    static func build(state: CompanionState, fightingIDs: Set<String>, moveChoices: [String: MoveChoice] = [:],
                      name: (DexEntry) -> String) -> [TradePoolEntry] {
        let ownedMachines = MachineMove.ownedIDs(in: state.inventory)
        return listed(state: state, fightingIDs: fightingIDs).compactMap { entry in
            wire(for: entry, state: state, name: name, choice: moveChoices[entry.id], ownedMachines: ownedMachines)
        }
    }

    static func listingRefusal(for entry: DexEntry, state: CompanionState, fightingIDs: Set<String>) -> TradeRefusal? {
        listed(state: state, fightingIDs: fightingIDs).contains { $0.id == entry.id } ? nil : .poolFull
    }

    static func encode(_ pool: [TradePoolEntry]) throws -> Data {
        guard pool.contains(where: { $0.member != nil }) else { return try encoder.encode(pool) }
        let objects = try pool.map { item -> Any in
            var object = try JSONSerialization.jsonObject(with: encoder.encode(item)) as? [String: Any] ?? [:]
            if let member = item.member {
                object["member"] = try JSONSerialization.jsonObject(with: memberEncoder.encode(member))
            }
            return object
        }
        return try JSONSerialization.data(withJSONObject: objects, options: .sortedKeys)
    }

    /// An entry too big with its battle member goes without it rather than leave the pool.
    private static func wire(for entry: DexEntry, state: CompanionState, name: (DexEntry) -> String,
                             choice: MoveChoice?, ownedMachines: Set<Int>) -> TradePoolEntry? {
        let held = state.heldItems[entry.id].flatMap(ItemKind.init(rawValue:))?.tradeItemKey
        guard var item = poolEntry(for: entry, name: name(entry), heldItem: held),
              let size = try? encoder.encode(item).count, size <= maxEntryBytes else { return nil }
        let base = PartyBuilder.member(speciesID: entry.finalID, form: entry.form, shiny: entry.isShiny,
                                       profile: entry.profile, nature: entry.nature,
                                       heldItem: state.heldItemSlug(of: entry.id))
        let member = BattleEntry.uploaded(base, id: entry.id, state: state, choice: choice, ownedMachines: ownedMachines)
        if let extra = try? memberEncoder.encode(member).count, size + extra + memberSlack <= maxEntryBytes {
            item.member = member
        }
        return item
    }

    /// Room for the `"member":` key and `encode`'s re-serialization of the entry.
    private static let memberSlack = 64

    /// The entry as it travels: without what the receiver replaces on arrival (`receivedEntry`). `instanceID` stays
    /// as an empty string because older apps cannot decode a profile without it.
    private static func poolEntry(for entry: DexEntry, name: String, heldItem: String?) -> TradePoolEntry? {
        var wire = entry
        wire.names = nil
        wire.namesVersion = nil
        wire.tradedTo = nil
        wire.tradeHeldItem = heldItem
        wire.tradePartnerID = nil
        wire.caughtAt = nil
        wire.originalTrainer = nil
        wire.profile?.instanceID = ""
        guard let profile = wire.profile, isSendable(wire) else { return nil }
        let pokemonID = PartyBuilder.member(speciesID: wire.finalID, form: wire.form, shiny: wire.isShiny,
                                            profile: profile, nature: wire.nature).pokemonID
        return TradePoolEntry(id: wire.id, pokemonID: pokemonID, level: min(100, max(1, profile.level)),
                              shiny: wire.isShiny, name: String(name.prefix(40)), entry: wire)
    }

    private static func isSendable(_ entry: DexEntry) -> Bool {
        !entry.id.isEmpty && entry.id.count <= 64 && !entry.id.contains("|")
            && PokemonAssets.isSupported(speciesID: entry.finalID)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    private static let memberEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()
}

/// What the uploader needs from the store; nil keeps the uploader a plain battle-party sender.
struct TradeSync: Sendable {
    let pool: @MainActor @Sendable () -> [TradePoolEntry]
    /// Applies the deliveries and returns the trade ids to acknowledge.
    let apply: @MainActor @Sendable ([TradeDelivery]) -> [String]
    /// The individuals the bot reports in open trades, replacing the previous set.
    var setLocked: @MainActor @Sendable (Set<String>) -> Void = { _ in }
    /// An offer the bot just accepted: its individual is locked before the next sync says so.
    var lock: @MainActor @Sendable (String) -> Void = { _ in }
}
