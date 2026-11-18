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

    /// The step into `speciesID`. Without an `individual` (the Pokédex page) also the steps out of it, with the raised
    /// Pokémon's progress on the step it waits for. For the raised Pokémon's Box page it also carries its progress
    /// and its waiting step; for a graduated individual, the trade steps it can take. A raised graduate whose form
    /// can still evolve gets its step too, and so does a stored Exp. Share holder.
    func evolutionCards(for speciesID: Int, individual: DexEntry? = nil) -> [EvolutionCard] {
        guard let individual else { return speciesEvolutionCards(for: speciesID) }
        let raised = individual.finalID == speciesID
            && (isLineParked ? individual.id == state.raisedEntryID : isActiveDexEntry(individual))
        let pending = raised ? pendingEvolutionGate() : nil
        let skippable = raised && !isLineParked && canSkipEvolution
        var cards: [EvolutionCard] = []
        if let rule = EvolutionRules.rule(for: speciesID), rule.hasCard {
            let live = pending?.rule.species == speciesID ? pending?.context : nil
            cards.append(EvolutionCard(rule: rule, context: live, isNextStep: false))
        }
        if let pending, pending.rule.species != speciesID {
            cards.append(EvolutionCard(rule: pending.rule, context: pending.context, isNextStep: true,
                                       offersSkip: skippable))
        }
        if state.storedLines[individual.id] != nil, individual.finalID == speciesID,
           let gate = storedLineGate(id: individual.id), gate.rule.species != speciesID {
            cards.append(EvolutionCard(rule: gate.rule, context: gate.context, isNextStep: true))
        }
        if individual.releasedAt == nil, state.storedLines[individual.id] == nil,
           individual.profile != nil, individual.finalID == speciesID,
           !isActiveDexEntry(individual), individual.id != state.raisedEntryID {
            for rule in tradeSteps(from: speciesID) {
                cards.append(EvolutionCard(rule: rule, context: nil, isNextStep: true, individualID: individual.id))
            }
        }
        return cards
    }

    private func speciesEvolutionCards(for speciesID: Int) -> [EvolutionCard] {
        let pending = pendingEvolutionGate()
        let live = { (rule: EvolutionRule) in pending?.rule.species == rule.species ? pending?.context : nil }
        var cards: [EvolutionCard] = []
        if let rule = EvolutionRules.rule(for: speciesID), rule.hasCard {
            cards.append(EvolutionCard(rule: rule, context: live(rule), isNextStep: false))
        }
        for rule in EvolutionRules.all where rule.from == speciesID && rule.hasCard {
            cards.append(EvolutionCard(rule: rule, context: live(rule), isNextStep: true))
        }
        return cards
    }

    func tradeSteps(from speciesID: Int) -> [EvolutionRule] {
        EvolutionRules.table.filter { $0.trade != nil && $0.from == speciesID }
    }
}

private extension EvolutionRule {
    var hasCard: Bool { !paths.isEmpty || selector != nil || trade != nil }
}
