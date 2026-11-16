import Foundation

/// The six-slot lineup as a gym request sends it: every member, not only the three that fight in PvP.
enum GymTeam {
    struct Team: Equatable, Sendable {
        /// What stands for each member when a run checks it is still the same team: the instance id, or the rental species.
        let ids: [String]
        let members: [PartyMember]
    }

    static func rentalID(_ speciesID: Int) -> String { "rental:\(speciesID)" }

    /// The owned lineup with each member's chosen moves (a TM move only while the TM is owned) and an item
    /// an earlier member already holds left off. With nothing owned it is the rental starter.
    static func team(state: CompanionState, slots: [BattleEntrySlot], moveChoices: [String: MoveChoice],
                     rentalSpeciesID: Int) -> Team {
        let lineup = BattleEntry.lineup(state: state, slots: slots)
        guard !lineup.isEmpty else {
            return Team(ids: [rentalID(rentalSpeciesID)], members: [
                PartyMember(pokemonID: rentalSpeciesID, level: BattleEntry.rentalLevel, shiny: false, ivs: nil, rental: true),
            ])
        }
        let duplicates = BattleEntry.duplicateItemHolders(state: state, slots: slots)
        let ownedMachines = MachineMove.ownedIDs(in: state.inventory)
        let members = lineup.map { candidate -> PartyMember in
            var member = candidate.member
            if duplicates.contains(candidate.id) { member.heldItem = nil }
            if let choice = moveChoices[candidate.id], choice.pokemonID == member.pokemonID {
                let usable = choice.moves.filter { !choice.machine.contains($0) || ownedMachines.contains($0) }
                if !usable.isEmpty { member.moves = usable }
            }
            return member
        }
        return Team(ids: lineup.map(\.id), members: members)
    }
}
