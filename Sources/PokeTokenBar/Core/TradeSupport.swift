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
    /// The battle pick: move it first.
    case fighting
    /// Arrived by trade and has not finished evolving.
    case arriving
    /// Released, traded away, or a species this build cannot show.
    case unavailable
}

enum TradePool {
    static let maxEntries = 100
    /// The bot refuses a body over 64 KB; the party itself needs a few hundred bytes.
    static let maxBytes = 48_000
    static let maxEntryBytes = 4_000

    /// Everyone in the battle lineup (up to three), which also covers the auto fighter when nothing is picked.
    static func fightingIDs(state: CompanionState, slots: [BattleEntrySlot]) -> Set<String> {
        Set(BattleEntry.lineup(state: state, slots: slots).map(\.id))
    }

    static func refusal(for entry: DexEntry, fightingIDs: Set<String>, activeID: String?) -> TradeRefusal? {
        if entry.id == activeID { return .raising }
        if entry.releasedAt != nil || entry.profile == nil || !isSendable(entry) { return .unavailable }
        if fightingIDs.contains(entry.id) { return .fighting }
        if entry.tradeEvolutionPending == true { return .arriving }
        return nil
    }

    /// The individuals this player may offer, newest first and trimmed to what the bot accepts.
    static func build(state: CompanionState, fightingIDs: Set<String>, name: (DexEntry) -> String) -> [TradePoolEntry] {
        var entries: [TradePoolEntry] = []
        var bytes = 2
        let owned = state.dex.sorted { ($0.caughtAt ?? .distantPast) > ($1.caughtAt ?? .distantPast) }
        for entry in owned where refusal(for: entry, fightingIDs: fightingIDs, activeID: nil) == nil {
            let held = state.heldItems[entry.id].flatMap(ItemKind.init(rawValue:))?.tradeItemKey
            guard entries.count < maxEntries, let item = poolEntry(for: entry, name: name(entry), heldItem: held),
                  let size = try? encoder.encode(item).count, size <= maxEntryBytes,
                  bytes + size + 1 <= maxBytes else { continue }
            entries.append(item)
            bytes += size + 1
        }
        return entries
    }

    static func encode(_ pool: [TradePoolEntry]) throws -> Data { try encoder.encode(pool) }

    /// The entry as it travels: no per-language name table (the receiver refetches it).
    private static func poolEntry(for entry: DexEntry, name: String, heldItem: String?) -> TradePoolEntry? {
        var wire = entry
        wire.names = nil
        wire.namesVersion = nil
        wire.tradedTo = nil
        wire.tradeHeldItem = heldItem
        wire.tradePartnerID = nil
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
