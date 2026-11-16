import Foundation
import Observation

/// One picked battle Pokémon.
struct BattleEntrySlot: Codable, Equatable, Sendable {
    var instanceID: String
}

/// The moves chosen for one owned Pokémon on its Box page. They belong to `pokemonID`, so a species change drops them.
struct MoveChoice: Codable, Equatable, Sendable {
    var pokemonID: Int
    var moves: [Int]
    /// The entries of `moves` that are TM moves; they only go to the bot while the TM is owned.
    var machine: [Int] = []
}

/// An owned Pokémon that can battle. `dexEntry` is nil for the line Pokémon; `isRaised` marks the one being
/// raised now, which is that line Pokémon or the raised graduate.
struct BattleCandidate: Sendable, Identifiable {
    let id: String
    let member: PartyMember
    let dexEntry: DexEntry?
    var isRaised = false
}

/// What the Battle tab's picker is choosing for.
enum BattlePickerTarget: Equatable {
    case add
    case slot(String)
}

enum BattleEntry {
    static let maxMoves = 4
    static let maxSlots = 6
    /// Slots 1–3 fight in PvP and are the only ones uploaded to the bot; 4–6 are for the gym.
    static let pvpSlots = 3
    /// The bot fights every Pokémon at this level or below; the app's growth is not capped.
    static let battleLevel = 50

    static func isLevelCapped(_ level: Int) -> Bool { level > battleLevel }
    /// Bulbasaur, Charmander, Squirtle.
    static let rentalSpeciesIDs = [1, 4, 7]
    /// Placeholder only: the bot levels a rental to its opponent.
    static let rentalLevel = 5

    static func candidates(in state: CompanionState) -> [BattleCandidate] {
        var owned: [BattleCandidate] = []
        // A parked line sits out: its Pokémon is not on this Mac's roster until it is raised again.
        if let active = state.active, state.raisedEntry == nil, let id = active.profile?.instanceID {
            owned.append(BattleCandidate(
                id: id,
                member: PartyBuilder.member(speciesID: active.currentID, form: active.form,
                                            shiny: active.displaysShiny, profile: active.profile,
                                            nature: active.nature, heldItem: state.heldItemSlug(of: id)),
                dexEntry: nil, isRaised: true))
        }
        for entry in state.dex where entry.releasedAt == nil {
            owned.append(BattleCandidate(
                id: entry.id,
                member: PartyBuilder.member(speciesID: entry.finalID, form: entry.form,
                                            shiny: entry.isShiny, profile: entry.profile,
                                            nature: entry.nature, heldItem: state.heldItemSlug(of: entry.id)),
                dexEntry: entry, isRaised: entry.id == state.raisedEntryID))
        }
        return owned.filter { PartyBuilder.isAcceptedPokemonID($0.member.pokemonID) }
    }

    /// The Pokémon being raised (the line Pokémon or the raised graduate), else (during an egg) the highest-level
    /// kept catch; nil when nothing is owned.
    static func autoFighter(state: CompanionState) -> BattleCandidate? {
        let owned = candidates(in: state)
        return owned.first(where: \.isRaised) ?? owned.max { $0.member.level < $1.member.level }
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

    /// The PvP party (the first `pvpSlots` of the lineup) with each member's chosen moves, or the rental starter
    /// when nothing is owned yet. A later member holding the same item as an earlier one goes without it.
    static func party(state: CompanionState, slots: [BattleEntrySlot], moveChoices: [String: MoveChoice],
                      rentalSpeciesID: Int) -> [PartyMember] {
        let lineup = lineup(state: state, slots: slots)
        let duplicates = duplicateItemHolders(state: state, slots: slots)
        guard !lineup.isEmpty else {
            return [PartyMember(pokemonID: rentalSpeciesID, level: rentalLevel, shiny: false, ivs: nil, rental: true)]
        }
        let ownedMachines = MachineMove.ownedIDs(in: state.inventory)
        return lineup.prefix(pvpSlots).map { candidate in
            var member = candidate.member
            if duplicates.contains(candidate.id) { member.heldItem = nil }
            if let choice = moveChoices[candidate.id], choice.pokemonID == member.pokemonID {
                let usable = choice.moves.filter { !choice.machine.contains($0) || ownedMachines.contains($0) }
                if !usable.isEmpty { member.moves = usable }
            }
            return member
        }
    }
}

/// The battle Pokémon chosen on this Mac, up to six in battle order. No picks means the Pokémon
/// being raised. Stored under the old key; a one-element older list loads as one slot.
@MainActor
@Observable
final class BattleEntryStore {
    static let defaultsKey = "battleEntrySlots"
    static let rentalDefaultsKey = "battleRentalSpeciesID"
    static let moveChoicesDefaultsKey = "battleMoveChoices"

    /// A slot as an older build stored it, with the moves it carried.
    private struct SavedSlot: Decodable {
        var instanceID: String
        var pokemonID: Int?
        var moves: [Int]?
    }

    private(set) var slots: [BattleEntrySlot] {
        didSet { defaults.set(try? JSONEncoder().encode(slots), forKey: Self.defaultsKey) }
    }

    /// Picked at random on first launch and kept until the user switches it.
    private(set) var rentalSpeciesID: Int {
        didSet { defaults.set(rentalSpeciesID, forKey: Self.rentalDefaultsKey) }
    }

    /// Moves chosen per owned Pokémon, whether or not it is in the lineup.
    private(set) var moveChoices: [String: MoveChoice] {
        didSet { defaults.set(try? JSONEncoder().encode(moveChoices), forKey: Self.moveChoicesDefaultsKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode([SavedSlot].self, from: $0) } ?? []
        var seen = Set<String>()
        let kept = saved.filter { seen.insert($0.instanceID).inserted }.prefix(BattleEntry.maxSlots)
        let keptSlots = kept.map { BattleEntrySlot(instanceID: $0.instanceID) }
        slots = keptSlots
        var choices = defaults.data(forKey: Self.moveChoicesDefaultsKey)
            .flatMap { try? JSONDecoder().decode([String: MoveChoice].self, from: $0) } ?? [:]
        // Slots saved before moves moved to the Box carry their own moves; adopt them once.
        for slot in saved where choices[slot.instanceID] == nil {
            if let pokemonID = slot.pokemonID, let moves = slot.moves, !moves.isEmpty {
                choices[slot.instanceID] = MoveChoice(pokemonID: pokemonID, moves: moves)
            }
        }
        moveChoices = choices
        if saved.contains(where: { $0.pokemonID != nil || $0.moves != nil }) {
            defaults.set(try? JSONEncoder().encode(keptSlots), forKey: Self.defaultsKey)
            defaults.set(try? JSONEncoder().encode(choices), forKey: Self.moveChoicesDefaultsKey)
        }
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

    /// Puts `instanceID` where `old` stands. Does nothing if it is already picked.
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

    /// Forgets picks and move choices of Pokémon that are no longer owned.
    func prune(owned: Set<String>) {
        let kept = slots.filter { owned.contains($0.instanceID) }
        if kept != slots { slots = kept }
        let choices = moveChoices.filter { owned.contains($0.key) }
        if choices != moveChoices { moveChoices = choices }
    }

    /// The moves chosen for `instanceID` as `pokemonID`; empty means the bot's defaults.
    func chosenMoves(for instanceID: String, pokemonID: Int) -> [Int] {
        guard let choice = moveChoices[instanceID], choice.pokemonID == pokemonID else { return [] }
        return choice.moves
    }

    /// Puts `moveID` at move position `index` (0-based) of `instanceID`, starting from `current` (what is shown:
    /// the choice, or the bot's defaults). A move already in the list swaps places with the one it replaces;
    /// a position past the end appends. Nothing changes at four moves with a position past the end.
    func chooseMove(_ moveID: Int, at index: Int, for instanceID: String, pokemonID: Int, current: [Int],
                    isMachine: Bool = false) {
        var moves = current
        if let found = moves.firstIndex(of: moveID) {
            guard found != index else { return }
            if moves.indices.contains(index) { moves.swapAt(found, index) } else { moves.remove(at: found); moves.append(moveID) }
        } else if moves.indices.contains(index) {
            moves[index] = moveID
        } else if moves.count < BattleEntry.maxMoves {
            moves.append(moveID)
        } else {
            return
        }
        var machine = (moveChoices[instanceID].flatMap { $0.pokemonID == pokemonID ? $0.machine : nil } ?? [])
            .filter(moves.contains)
        if isMachine, !machine.contains(moveID) { machine.append(moveID) }
        moveChoices[instanceID] = MoveChoice(pokemonID: pokemonID, moves: moves, machine: machine)
    }

    func resetMoves(for instanceID: String) {
        moveChoices[instanceID] = nil
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
