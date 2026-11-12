import Foundation
import Observation

/// One chosen entry slot. `moves` belong to `pokemonID`; empty means the bot's defaults.
struct BattleEntrySlot: Codable, Equatable, Sendable {
    var instanceID: String
    var pokemonID: Int? = nil
    var moves: [Int] = []
}

/// An owned Pokémon that can join the entry. `dexEntry` is nil for the one being raised now.
struct BattleCandidate: Sendable, Identifiable {
    let id: String
    let member: PartyMember
    let dexEntry: DexEntry?
}

enum BattleEntry {
    static let maxSize = 3
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

    /// The chosen slots that are still owned, in order; the Pokémon being raised when none are.
    static func party(state: CompanionState, slots: [BattleEntrySlot]) -> [PartyMember] {
        let owned = candidates(in: state)
        let chosen = slots.compactMap { slot -> PartyMember? in
            guard var member = owned.first(where: { $0.id == slot.instanceID })?.member else { return nil }
            if slot.pokemonID == member.pokemonID, !slot.moves.isEmpty {
                member.moves = slot.moves
            }
            return member
        }
        return chosen.isEmpty ? PartyBuilder.party(from: state) : chosen
    }
}

/// The battle entry chosen on this Mac.
@MainActor
@Observable
final class BattleEntryStore {
    static let defaultsKey = "battleEntrySlots"

    private(set) var slots: [BattleEntrySlot] {
        didSet { defaults.set(try? JSONEncoder().encode(slots), forKey: Self.defaultsKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        slots = defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode([BattleEntrySlot].self, from: $0) } ?? []
    }

    var isFull: Bool { slots.count >= BattleEntry.maxSize }

    func contains(_ instanceID: String) -> Bool {
        slots.contains { $0.instanceID == instanceID }
    }

    func add(_ instanceID: String) {
        guard !isFull, !contains(instanceID) else { return }
        slots.append(BattleEntrySlot(instanceID: instanceID))
    }

    func remove(_ instanceID: String) {
        slots.removeAll { $0.instanceID == instanceID }
    }

    func move(_ instanceID: String, by offset: Int) {
        guard let from = slots.firstIndex(where: { $0.instanceID == instanceID }) else { return }
        let to = from + offset
        guard slots.indices.contains(to) else { return }
        slots.swapAt(from, to)
    }

    /// Adds or drops one move; starting from `current` turns the bot's defaults into an explicit list.
    func toggleMove(_ moveID: Int, for instanceID: String, pokemonID: Int, current: [Int]) {
        guard let index = slots.firstIndex(where: { $0.instanceID == instanceID }) else { return }
        var moves = current
        if let found = moves.firstIndex(of: moveID) {
            moves.remove(at: found)
        } else if moves.count < BattleEntry.maxMoves {
            moves.append(moveID)
        } else {
            return
        }
        slots[index].pokemonID = pokemonID
        slots[index].moves = moves
    }

    func resetMoves(for instanceID: String) {
        guard let index = slots.firstIndex(where: { $0.instanceID == instanceID }) else { return }
        slots[index].pokemonID = nil
        slots[index].moves = []
    }
}
