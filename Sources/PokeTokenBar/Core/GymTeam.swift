import Foundation

/// The lineup as a gym request sends it, with the ids a run uses to check it is still the same team.
enum GymTeam {
    struct Team: Equatable, Sendable {
        /// What stands for each member when a run checks it is still the same team: the instance id, or the rental species.
        let ids: [String]
        let members: [PartyMember]
    }

    static func rentalID(_ speciesID: Int) -> String { "rental:\(speciesID)" }

    /// The same members a Slack battle gets: see `BattleEntry.party`.
    static func team(state: CompanionState, slots: [BattleEntrySlot], moveChoices: [String: MoveChoice],
                     rentalSpeciesID: Int) -> Team {
        let ids = BattleEntry.lineup(state: state, slots: slots).map(\.id)
        let members = BattleEntry.party(state: state, slots: slots, moveChoices: moveChoices, rentalSpeciesID: rentalSpeciesID)
        return Team(ids: ids.isEmpty ? [rentalID(rentalSpeciesID)] : ids, members: members)
    }
}
