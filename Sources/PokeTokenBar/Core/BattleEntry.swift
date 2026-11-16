import Foundation
import Observation

/// One picked battle Pokémon. `moves` belong to `pokemonID`; empty means the bot's defaults.
struct BattleEntrySlot: Codable, Equatable, Sendable {
    var instanceID: String
    var pokemonID: Int? = nil
    var moves: [Int] = []
}

/// An owned Pokémon that can battle. `dexEntry` is nil for the one being raised now.
struct BattleCandidate: Sendable, Identifiable {
    let id: String
    let member: PartyMember
    let dexEntry: DexEntry?
}

/// What the Battle tab's picker is choosing for.
enum BattlePickerTarget: Equatable {
    case add
    case slot(String)
}

enum BattleEntry {
    static let maxMoves = 4
    static let maxSlots = 3
    /// The bot fights every Pokémon at this level or below; the app's growth is not capped.
    static let battleLevel = 50

    static func isLevelCapped(_ level: Int) -> Bool { level > battleLevel }
    /// Bulbasaur, Charmander, Squirtle.
    static let rentalSpeciesIDs = [1, 4, 7]
    /// Placeholder only: the bot levels a rental to its opponent.
    static let rentalLevel = 5

    static func candidates(in state: CompanionState) -> [BattleCandidate] {
        var owned: [BattleCandidate] = []
        if let active = state.active, let id = active.profile?.instanceID {
            owned.append(BattleCandidate(
                id: id,
                member: PartyBuilder.member(speciesID: active.currentID, form: active.form,
                                            shiny: active.displaysShiny, profile: active.profile,
                                            nature: active.nature, heldItem: state.heldItemSlug(of: id)),
                dexEntry: nil))
        }
        for entry in state.dex where entry.releasedAt == nil {
            owned.append(BattleCandidate(
                id: entry.id,
                member: PartyBuilder.member(speciesID: entry.finalID, form: entry.form,
                                            shiny: entry.isShiny, profile: entry.profile,
                                            nature: entry.nature, heldItem: state.heldItemSlug(of: entry.id)),
                dexEntry: entry))
        }
        return owned.filter { PartyBuilder.isAcceptedPokemonID($0.member.pokemonID) }
    }

    /// The Pokémon being raised, else (during an egg) the highest-level kept catch; nil when nothing is owned.
    static func autoFighter(state: CompanionState) -> BattleCandidate? {
        let owned = candidates(in: state)
        return owned.first { $0.dexEntry == nil } ?? owned.max { $0.member.level < $1.member.level }
    }

    /// The picked Pokémon that are still owned, in slot order. With none of them owned (or none picked)
    /// it is the auto fighter alone, and empty only when nothing is owned.
    static func lineup(state: CompanionState, slots: [BattleEntrySlot]) -> [BattleCandidate] {
        let owned = candidates(in: state)
        var seen = Set<String>()
        let picked = slots.compactMap { slot in owned.first { $0.id == slot.instanceID } }
            .filter { seen.insert($0.id).inserted }
            .prefix(maxSlots)
        return picked.isEmpty ? autoFighter(state: state).map { [$0] } ?? [] : Array(picked)
    }

    /// Lineup members holding an item an earlier member already holds (a save from before the item clause).
    static func duplicateItemHolders(state: CompanionState, slots: [BattleEntrySlot]) -> Set<String> {
        var seen = Set<String>()
        var duplicates = Set<String>()
        for candidate in lineup(state: state, slots: slots) {
            guard let key = state.heldItems[candidate.id] else { continue }
            if !seen.insert(key).inserted { duplicates.insert(candidate.id) }
        }
        return duplicates
    }

    /// Whether `id` joining `ids` (taking over `replacing`'s place) would give two members the same item.
    /// A member already in `ids` only moves or leaves, so it never clashes.
    static func itemClash(_ id: String, replacing: String?, among ids: [String], state: CompanionState) -> Bool {
        guard !ids.contains(id), let key = state.heldItems[id] else { return false }
        return ids.contains { $0 != replacing && state.heldItems[$0] == key }
    }

    /// Whether giving `key` to `id` would match another lineup member's item; `id` outside the lineup never clashes.
    static func equipClash(_ key: String, onto id: String, state: CompanionState, slots: [BattleEntrySlot]) -> Bool {
        let ids = lineup(state: state, slots: slots).map(\.id)
        return ids.contains(id) && ids.contains { $0 != id && state.heldItems[$0] == key }
    }

    /// Candidates the picker must not offer: their item matches a lineup member who stays.
    static func itemBlockedCandidates(state: CompanionState, slots: [BattleEntrySlot], replacing: String?) -> Set<String> {
        let ids = lineup(state: state, slots: slots).map(\.id)
        return Set(candidates(in: state).map(\.id).filter { itemClash($0, replacing: replacing, among: ids, state: state) })
    }

    /// The lineup with each member's chosen moves, or the rental starter when nothing is owned yet.
    /// A later member holding the same item as an earlier one goes without it.
    static func party(state: CompanionState, slots: [BattleEntrySlot], rentalSpeciesID: Int) -> [PartyMember] {
        let lineup = lineup(state: state, slots: slots)
        let duplicates = duplicateItemHolders(state: state, slots: slots)
        guard !lineup.isEmpty else {
            return [PartyMember(pokemonID: rentalSpeciesID, level: rentalLevel, shiny: false, ivs: nil, rental: true)]
        }
        return lineup.map { candidate in
            var member = candidate.member
            if duplicates.contains(candidate.id) { member.heldItem = nil }
            if let slot = slots.first(where: { $0.instanceID == candidate.id }),
               slot.pokemonID == member.pokemonID, !slot.moves.isEmpty {
                member.moves = slot.moves
            }
            return member
        }
    }
}

/// The battle Pokémon chosen on this Mac, up to three in battle order. No picks means the Pokémon
/// being raised. Stored under the old key; a one-element older list loads as one slot.
@MainActor
@Observable
final class BattleEntryStore {
    static let defaultsKey = "battleEntrySlots"
    static let rentalDefaultsKey = "battleRentalSpeciesID"

    private(set) var slots: [BattleEntrySlot] {
        didSet { defaults.set(try? JSONEncoder().encode(slots), forKey: Self.defaultsKey) }
    }

    /// Picked at random on first launch and kept until the user switches it.
    private(set) var rentalSpeciesID: Int {
        didSet { defaults.set(rentalSpeciesID, forKey: Self.rentalDefaultsKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var seen = Set<String>()
        slots = (defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode([BattleEntrySlot].self, from: $0) } ?? [])
            .filter { seen.insert($0.instanceID).inserted }
            .prefix(BattleEntry.maxSlots).map { $0 }
        let stored = defaults.integer(forKey: Self.rentalDefaultsKey)
        rentalSpeciesID = BattleEntry.rentalSpeciesIDs.contains(stored) ? stored : BattleEntry.rentalSpeciesIDs.randomElement()!
        defaults.set(rentalSpeciesID, forKey: Self.rentalDefaultsKey)
    }

    func chooseRental(_ speciesID: Int) {
        guard BattleEntry.rentalSpeciesIDs.contains(speciesID) else { return }
        rentalSpeciesID = speciesID
    }

    /// Takes the first free slot. With nothing picked yet, `pinning` (the auto fighter shown in slot 1)
    /// is picked first so it keeps its place.
    @discardableResult
    func add(_ instanceID: String, pinning auto: String? = nil) -> Bool {
        var next = slots
        if next.isEmpty, let auto, auto != instanceID { next.append(BattleEntrySlot(instanceID: auto)) }
        guard next.count < BattleEntry.maxSlots, !next.contains(where: { $0.instanceID == instanceID }) else {
            return false
        }
        next.append(BattleEntrySlot(instanceID: instanceID))
        slots = next
        return true
    }

    /// Puts `instanceID` where `old` stands, dropping the old moves. Does nothing if it is already picked.
    func replace(_ old: String, with instanceID: String) {
        guard old != instanceID, !slots.contains(where: { $0.instanceID == instanceID }) else { return }
        if let index = slots.firstIndex(where: { $0.instanceID == old }) {
            slots[index] = BattleEntrySlot(instanceID: instanceID)
        } else if slots.isEmpty {
            slots = [BattleEntrySlot(instanceID: instanceID)]
        }
    }

    /// Dropping the last pick goes back to the Pokémon being raised.
    func remove(_ instanceID: String) {
        slots.removeAll { $0.instanceID == instanceID }
    }

    func move(_ instanceID: String, by offset: Int) {
        guard let index = slots.firstIndex(where: { $0.instanceID == instanceID }),
              slots.indices.contains(index + offset) else { return }
        slots.swapAt(index, index + offset)
    }

    /// Forgets picks that are no longer owned, so the slot order the user sees is the stored one.
    func prune(owned: Set<String>) {
        let kept = slots.filter { owned.contains($0.instanceID) }
        if kept != slots { slots = kept }
    }

    func slot(for instanceID: String) -> BattleEntrySlot? {
        slots.first { $0.instanceID == instanceID }
    }

    /// Adds or drops one move of `instanceID` and picks it; starting from `current` turns the bot's
    /// defaults into an explicit list.
    func toggleMove(_ moveID: Int, for instanceID: String, pokemonID: Int, current: [Int]) {
        var moves = current
        if let found = moves.firstIndex(of: moveID) {
            moves.remove(at: found)
        } else if moves.count < BattleEntry.maxMoves {
            moves.append(moveID)
        } else {
            return
        }
        let slot = BattleEntrySlot(instanceID: instanceID, pokemonID: pokemonID, moves: moves)
        if let index = slots.firstIndex(where: { $0.instanceID == instanceID }) {
            slots[index] = slot
        } else if slots.count < BattleEntry.maxSlots {
            slots.append(slot)
        }
    }

    func resetMoves(for instanceID: String) {
        guard let index = slots.firstIndex(where: { $0.instanceID == instanceID }) else { return }
        slots[index] = BattleEntrySlot(instanceID: instanceID)
    }

    /// Puts `entry` in battle slot `index` (0-based) of the lineup the Battle tab shows. Tapping its own slot
    /// takes it out (never the last member); a slot past the end appends. Another slot's holder swaps with it,
    /// a different holder of a slot it was not in leaves. The representative and the Pokémon being raised stay
    /// as they are. False when nothing changed.
    @discardableResult
    func place(_ entry: DexEntry, at index: Int, in store: CompanionStore) -> Bool {
        guard (0..<BattleEntry.maxSlots).contains(index), let candidate = store.battleCandidate(for: entry),
              !store.isTradeLocked(candidate.id) else { return false }
        prune(owned: Set(BattleEntry.candidates(in: store.state).map(\.id)))
        let current = slots.isEmpty
            ? BattleEntry.autoFighter(state: store.state).map { [BattleEntrySlot(instanceID: $0.id)] } ?? []
            : slots
        var next = current
        let replaced = index < current.count ? current[index].instanceID : nil
        if BattleEntry.itemClash(candidate.id, replacing: replaced, among: current.map(\.instanceID),
                                 state: store.state) { return false }
        if let from = current.firstIndex(where: { $0.instanceID == candidate.id }) {
            let to = min(index, current.count - 1)
            if from == to, index == to {
                guard current.count > 1 else { return false }
                next.remove(at: from)
            } else {
                next.swapAt(from, to)
            }
        } else if index < current.count {
            next[index] = BattleEntrySlot(instanceID: candidate.id)
        } else {
            next.append(BattleEntrySlot(instanceID: candidate.id))
        }
        guard next != current else { return false }
        slots = next
        return true
    }

    /// Where `entry` stands in the lineup the Battle tab shows, 0-based.
    func slotIndex(of entry: DexEntry, in store: CompanionStore) -> Int? {
        guard let candidate = store.battleCandidate(for: entry) else { return nil }
        return BattleEntry.lineup(state: store.state, slots: slots).firstIndex { $0.id == candidate.id }
    }
}
