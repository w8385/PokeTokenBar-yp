import Foundation

/// The `lineup` remote op: the whole battle lineup set in Slack, in order, with each member's moves and held item
/// (`bot/API.md` "The `lineup` op"). It applies all of it or nothing.
enum RemoteLineup {
    static let kind = "lineup"

    enum Reason {
        static let gone = "gone"
        static let evolved = "evolved"
        static let tradeLocked = "trade_locked"
        static let noItem = "no_item"
        static let noMachine = "no_machine"
        static let speciesClause = "species_clause"
        static let itemClause = "item_clause"
        static let invalid = "invalid"
    }

    struct Member: Decodable, Equatable {
        let id: String
        let pokemonID: Int
        let moves: [Int]
        let machine: [Int]
        let item: String?

        enum CodingKeys: String, CodingKey {
            case id, moves, machine, item
            case pokemonID = "pokemon_id"
        }
    }

    struct Payload: Decodable, Equatable {
        let members: [Member]
    }

    /// Nil when applied; otherwise the reason it was cancelled with nothing changed.
    @MainActor
    static func apply(_ data: Data, store: CompanionStore, battleEntry: BattleEntryStore) -> String? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return Reason.invalid }
        if let reason = refusal(payload.members, state: store.state, isTradeLocked: store.isTradeLocked) {
            return reason
        }
        store.moveHeldItems(payload.members.map { ($0.id, $0.item) })
        battleEntry.adopt(payload.members)
        return nil
    }

    /// Why the app cannot take this lineup, checked in the order the bot checks it; nil when it can.
    static func refusal(_ members: [Member], state: CompanionState, isTradeLocked: (String) -> Bool) -> String? {
        guard (1...BattleEntry.maxSlots).contains(members.count), Set(members.map(\.id)).count == members.count,
              members.allSatisfy({ $0.moves.count <= BattleEntry.maxMoves && Set($0.machine).isSubset(of: $0.moves) })
        else { return Reason.invalid }
        let owned = Dictionary(BattleEntry.candidates(in: state).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard members.allSatisfy({ owned[$0.id] != nil }) else { return Reason.gone }
        guard members.allSatisfy({ owned[$0.id]?.member.pokemonID == $0.pokemonID }) else { return Reason.evolved }
        guard !members.contains(where: { isTradeLocked($0.id) }) else { return Reason.tradeLocked }
        let machines = MachineMove.ownedIDs(in: state.inventory)
        guard members.allSatisfy({ Set($0.machine).isSubset(of: machines) }) else { return Reason.noMachine }
        guard hasItems(for: members, state: state) else { return Reason.noItem }
        let species = members.compactMap { owned[$0.id]?.speciesID }
        guard Set(species).count == species.count else { return Reason.speciesClause }
        let items = members.compactMap { member in member.item.flatMap { countedItem($0, holder: member.pokemonID) } }
        return Set(items).count == items.count ? nil : Reason.itemClause
    }

    /// Whether the bag has a copy of every new item once the changing holders gave theirs back.
    private static func hasItems(for members: [Member], state: CompanionState) -> Bool {
        let changing = members.filter { state.heldItems[$0.id] != $0.item }
        var bag = state.inventory
        for member in changing {
            if let previous = state.heldItems[member.id] { bag[previous, default: 0] += 1 }
        }
        for member in changing {
            guard let key = member.item else { continue }
            guard isEquippable(key) else { return false }
            bag[key, default: 0] -= 1
            if bag[key, default: 0] < 0 { return false }
        }
        return true
    }

    /// A species-bound item on another species does nothing, so it does not count for the item clause.
    private static func countedItem(_ key: String, holder pokemonID: Int) -> String? {
        if let species = ItemKind(rawValue: key)?.holderSpeciesID, species != pokemonID { return nil }
        return key
    }

    static func isEquippable(_ key: String) -> Bool {
        ItemKind(rawValue: key)?.isEquippable == true || MegaStone.stone(inventoryKey: key) != nil
    }

    /// The Korean name the bot shows for a held or holdable inventory key.
    static func itemName(_ key: String) -> String? {
        let ko = L(.ko)
        if let kind = ItemKind(rawValue: key) { return ko.itemName(kind) }
        return MegaStone.stone(inventoryKey: key).map(ko.megaStoneName)
    }
}
