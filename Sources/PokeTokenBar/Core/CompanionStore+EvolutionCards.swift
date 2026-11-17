import Foundation

extension CompanionStore {
    /// One special evolution step: what the games ask for and what this app asks for.
    struct EvolutionCard: Identifiable {
        let rule: EvolutionRule
        /// Set when the raised Pokémon is on this step, so progress can be shown.
        let context: EvolutionContext?
        /// The raised Pokémon's next step, shown on the species it is now (not the species it becomes).
        let isNextStep: Bool
        /// The graduated individual a trade step is for, so its held item is shown on the card.
        var individualID: String?
        /// The active Pokémon is ready but this step is held by a condition, so it may graduate as it is.
        var offersSkip = false
        var id: String { "\(rule.species)-\(isNextStep)" }
    }

    /// The cards name other species, and the index that holds their names is otherwise fetched only by a search.
    func loadEvolutionCardNames(for speciesID: Int, individual: DexEntry? = nil) async {
        guard !evolutionCards(for: speciesID, individual: individual).isEmpty else { return }
        await loadSpeciesIndexIfNeeded()
    }

    /// The step into `speciesID`. Without an `individual` that is all there is (the Pokédex page is about the
    /// species). For the raised Pokémon it also carries its progress and its waiting step; for a graduated
    /// individual, the trade steps it can take. A raised graduate whose form can still evolve gets its step too.
    func evolutionCards(for speciesID: Int, individual: DexEntry? = nil) -> [EvolutionCard] {
        let raised = individual.map {
            $0.finalID == speciesID && (isLineParked ? $0.id == state.raisedEntryID : isActiveDexEntry($0))
        } ?? false
        let pending = raised ? pendingEvolutionGate() : nil
        let skippable = raised && !isLineParked && canSkipEvolution
        var cards: [EvolutionCard] = []
        if let rule = EvolutionRules.rule(for: speciesID),
           !rule.paths.isEmpty || rule.selector != nil || rule.trade != nil {
            let live = pending?.rule.species == speciesID ? pending?.context : nil
            cards.append(EvolutionCard(rule: rule, context: live, isNextStep: false))
        }
        if let pending, pending.rule.species != speciesID {
            cards.append(EvolutionCard(rule: pending.rule, context: pending.context, isNextStep: true,
                                       offersSkip: skippable))
        }
        if let individual, individual.releasedAt == nil, state.storedLines[individual.id] == nil,
           individual.profile != nil, individual.finalID == speciesID,
           !isActiveDexEntry(individual), individual.id != state.raisedEntryID {
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
