import Foundation
import Observation

/// The chosen battle Pokémon. `moves` belong to `pokemonID`; empty means the bot's defaults.
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

enum BattleEntry {
    static let maxMoves = 4

    static func candidates(in state: CompanionState) -> [BattleCandidate] {
        var owned: [BattleCandidate] = []
        if let active = state.active, let id = active.profile?.instanceID {
            owned.append(BattleCandidate(
                id: id,
                member: PartyBuilder.member(speciesID: active.currentID, form: active.form,
                                            shiny: active.displaysShiny, profile: active.profile),
                dexEntry: nil))
        }
        for entry in state.dex where entry.releasedAt == nil {
            owned.append(BattleCandidate(
                id: entry.id,
                member: PartyBuilder.member(speciesID: entry.finalID, form: entry.form,
                                            shiny: entry.isShiny, profile: entry.profile),
                dexEntry: entry))
        }
        return owned.filter { PartyBuilder.isAcceptedPokemonID($0.member.pokemonID) }
    }

    /// The chosen Pokémon if still owned, else the one being raised; nil for an egg with nothing chosen.
    static func fighter(state: CompanionState, slot: BattleEntrySlot?) -> BattleCandidate? {
        let owned = candidates(in: state)
        return slot.flatMap { slot in owned.first { $0.id == slot.instanceID } } ?? owned.first { $0.dexEntry == nil }
    }

    /// One Pokémon with its chosen moves, or empty for an egg.
    static func party(state: CompanionState, slot: BattleEntrySlot?) -> [PartyMember] {
        guard let fighter = fighter(state: state, slot: slot) else { return [] }
        var member = fighter.member
        if let slot, slot.instanceID == fighter.id, slot.pokemonID == member.pokemonID, !slot.moves.isEmpty {
            member.moves = slot.moves
        }
        return [member]
    }
}

/// The battle Pokémon chosen on this Mac, kept as a one-element list under the old 3-slot key.
/// An older 3-slot entry loads as its first slot.
@MainActor
@Observable
final class BattleEntryStore {
    static let defaultsKey = "battleEntrySlots"

    private(set) var slot: BattleEntrySlot? {
        didSet { defaults.set(try? JSONEncoder().encode(slot.map { [$0] } ?? []), forKey: Self.defaultsKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        slot = defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode([BattleEntrySlot].self, from: $0) }?.first
    }

    /// Nil goes back to the Pokémon being raised.
    func choose(_ instanceID: String?) {
        guard instanceID != slot?.instanceID else { return }
        slot = instanceID.map { BattleEntrySlot(instanceID: $0) }
    }

    /// Adds or drops one move of `instanceID` and chooses it; starting from `current` turns the bot's
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
        slot = BattleEntrySlot(instanceID: instanceID, pokemonID: pokemonID, moves: moves)
    }

    func resetMoves() {
        guard let slot else { return }
        self.slot = BattleEntrySlot(instanceID: slot.instanceID)
    }
}
