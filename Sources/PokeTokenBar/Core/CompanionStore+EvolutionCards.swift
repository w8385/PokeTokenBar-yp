import Foundation

extension CompanionStore {
    /// One special evolution step for the dex detail: what the games ask for and what this app asks for.
    struct EvolutionCard: Identifiable {
        let rule: EvolutionRule
        /// Set when the raised Pokémon is on this step, so progress can be shown.
        let context: EvolutionContext?
        /// The raised Pokémon's next step, shown on the species it is now (not the species it becomes).
        let isNextStep: Bool
        var id: String { "\(rule.species)-\(isNextStep)" }
    }

    /// The step into `speciesID`, and the raised Pokémon's waiting step when it is `speciesID` right now.
    func evolutionCards(for speciesID: Int) -> [EvolutionCard] {
        let pending = pendingEvolutionGate()
        var cards: [EvolutionCard] = []
        if let rule = EvolutionRules.rule(for: speciesID), !rule.paths.isEmpty || rule.selector != nil {
            let live = pending?.rule.species == speciesID ? pending?.context : nil
            cards.append(EvolutionCard(rule: rule, context: live, isNextStep: false))
        }
        if let pending, pending.rule.species != speciesID, state.active?.currentID == speciesID {
            cards.append(EvolutionCard(rule: pending.rule, context: pending.context, isNextStep: true))
        }
        return cards
    }
}
