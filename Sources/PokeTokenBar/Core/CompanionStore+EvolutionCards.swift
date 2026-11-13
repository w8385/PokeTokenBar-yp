import Foundation

extension CompanionStore {
    /// One special evolution step for the dex detail: what the games ask for and what this app asks for.
    struct EvolutionCard: Identifiable {
        let rule: EvolutionRule
        /// Set when the raised Pokémon is on this step, so progress can be shown.
        let context: EvolutionContext?
        /// The raised Pokémon's next step, shown on the species it is now (not the species it becomes).
        let isNextStep: Bool
        /// The graduated individual a trade step is for, so its held item can be changed from the card.
        var individualID: String?
        var id: String { "\(rule.species)-\(isNextStep)" }
    }

    /// The cards name other species, and the index that holds their names is otherwise fetched only by a search.
    func loadEvolutionCardNames(for speciesID: Int, individual: DexEntry? = nil) async {
        guard !evolutionCards(for: speciesID, individual: individual).isEmpty else { return }
        await loadSpeciesIndexIfNeeded()
    }

    /// The step into `speciesID`, and the raised Pokémon's waiting step when it is `speciesID` right now.
    /// For a graduated `individual` of `speciesID`, also the trade steps it can take.
    func evolutionCards(for speciesID: Int, individual: DexEntry? = nil) -> [EvolutionCard] {
        let pending = pendingEvolutionGate()
        var cards: [EvolutionCard] = []
        if let rule = EvolutionRules.rule(for: speciesID),
           !rule.paths.isEmpty || rule.selector != nil || rule.trade != nil {
            let live = pending?.rule.species == speciesID ? pending?.context : nil
            cards.append(EvolutionCard(rule: rule, context: live, isNextStep: false))
        }
        if let pending, pending.rule.species != speciesID, state.active?.currentID == speciesID {
            cards.append(EvolutionCard(rule: pending.rule, context: pending.context, isNextStep: true))
        }
        if let individual, individual.releasedAt == nil, individual.profile != nil, individual.finalID == speciesID,
           !isActiveDexEntry(individual) {
            for rule in tradeSteps(from: speciesID) {
                cards.append(EvolutionCard(rule: rule, context: nil, isNextStep: true, individualID: individual.id))
            }
        }
        return cards
    }

    func tradeSteps(from speciesID: Int) -> [EvolutionRule] {
        EvolutionRules.table.filter { $0.trade != nil && $0.from == speciesID }
    }
}
