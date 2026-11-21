import Foundation

/// The `train` remote op: one training-tab action done in Slack on one individual (`bot/API.md` "The `train` op").
/// It runs the app's own training on the current state, all of it or nothing.
enum RemoteTrain {
    static let kind = "train"

    enum Reason {
        static let gone = "gone"
        static let evolved = "evolved"
        static let tradeLocked = "trade_locked"
        static let noItem = "no_item"
        static let noTokens = "no_tokens"
        static let priceChanged = "price_changed"
        static let unchanged = "unchanged"
        static let notApplicable = "not_applicable"
        static let noMachine = "no_machine"
        static let noHerb = "no_herb"
        static let noData = "no_data"
        static let invalid = "invalid"
        static let wrongTarget = "wrong_target"
        static let notReady = "not_ready"
        static let everstone = "everstone"
    }

    static let evolveAction = "evolve"

    struct Ability: Decodable, Equatable {
        let name: String
        let slot: Int
        let hidden: Bool
    }

    struct Payload: Decodable, Equatable {
        let action: String
        let id: String
        let pokemonID: Int
        var nature: String? = nil
        /// The token price the player saw; nil when the bag had the item.
        var price: Int? = nil
        var stat: String? = nil
        var ability: Ability? = nil
        var form: String? = nil
        var toPokemonID: Int? = nil
        var moves: [Int]? = nil
        var machine: [Int]? = nil
        var egg: [Int]? = nil
        var item: String? = nil

        enum CodingKeys: String, CodingKey {
            case action, id, nature, price, stat, ability, form, moves, machine, egg, item
            case pokemonID = "pokemon_id"
            case toPokemonID = "to_pokemon_id"
        }
    }

    /// Nil when applied; otherwise the reason it was cancelled with nothing changed.
    @MainActor
    static func apply(_ data: Data, store: CompanionStore, battleEntry: BattleEntryStore) -> String? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return Reason.invalid }
        if let refusal = ownerRefusal(payload, store) { return refusal }
        guard let individual = store.trainable(id: payload.id) else { return Reason.notApplicable }
        switch payload.action {
        case "nature": return nature(payload, individual, store)
        case "herb": return herb(payload, individual, store)
        case "capsule", "patch": return ability(payload, individual, store)
        case "cap": return bottleCap(payload, store)
        case "gold_cap":
            guard store.itemCount(.goldBottleCap) > 0 else { return Reason.noItem }
            return reason(store.useGoldBottleCap(on: payload.id))
        case "form": return form(payload, individual, store)
        case "moves": return moves(payload, individual, store, battleEntry)
        case evolveAction: return RemoteOpReason.unsupported
        default: return Reason.invalid
        }
    }

    @MainActor
    private static func ownerRefusal(_ payload: Payload, _ store: CompanionStore) -> String? {
        guard let candidate = BattleEntry.candidates(in: store.state).first(where: { $0.id == payload.id })
        else { return Reason.gone }
        guard !store.isTradeLocked(payload.id) else { return Reason.tradeLocked }
        guard candidate.member.pokemonID == payload.pokemonID else { return Reason.evolved }
        return nil
    }

    static func isEvolution(_ op: RemoteOp) -> Bool {
        op.kind == kind && (try? JSONDecoder().decode(Payload.self, from: op.payload))?.action == evolveAction
    }

    /// The `evolve` action: the box detail's Linking Cord, on the target the player saw in Slack.
    @MainActor
    static func evolve(_ data: Data, store: CompanionStore) async -> String? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data), payload.action == evolveAction
        else { return Reason.invalid }
        if let refusal = ownerRefusal(payload, store) { return refusal }
        guard payload.item == ItemKind.linkingCord.rawValue, payload.toPokemonID != nil else { return Reason.invalid }
        guard store.itemCount(.linkingCord) > 0 else { return Reason.noItem }
        guard cordEvolution(of: payload.id, store: store)?.pokemonID == payload.toPokemonID
        else { return Reason.notApplicable }
        return reason(await store.useLinkingCord(on: payload.id))
    }

    static func reason(_ result: CompanionStore.CordUseResult) -> String? {
        switch result {
        case .evolved: nil
        case .wrongTarget: Reason.wrongTarget
        case .notReady: Reason.notReady
        case .everstone: Reason.everstone
        case .listed: Reason.tradeLocked
        case .unavailable: Reason.noData
        }
    }

    /// The step a Linking Cord would take on a Box graduate (not the raised one), read from the rule table so the
    /// upload needs no evolution line. Whether a cord is in the bag is left to Slack's replayed bag.
    @MainActor
    static func cordEvolution(of id: String, store: CompanionStore) -> RemoteEvolution? {
        let state = store.state
        guard id != state.raisedEntryID,
              let entry = state.dex.first(where: { $0.id == id && $0.releasedAt == nil && $0.profile != nil })
        else { return nil }
        let held = store.heldItem(of: id)
        let partners = Set(state.friendEntryIDs.compactMap { store.friendEntry(forKey: $0)?.finalID })
        guard let rule = EvolutionRules.table.first(where: { rule in
            guard rule.from == entry.finalID, let trade = rule.trade else { return false }
            switch trade {
            case .plain: return true
            case .holding(let kind): return held == kind
            case .partner(let species): return partners.contains(species)
            }
        }) else { return nil }
        let pokemonID = PartyBuilder.member(speciesID: rule.species, form: entry.form, shiny: false, profile: nil).pokemonID
        var evolution = RemoteEvolution(item: ItemKind.linkingCord.rawValue, pokemonID: pokemonID)
        if case .holding? = rule.trade { evolution.heldItem = state.heldItemSlug(of: id) }
        return evolution
    }

    /// Every Box graduate a cord could evolve now, by individual id: not in a trade and not holding an Everstone.
    @MainActor
    static func evolutions(store: CompanionStore) -> [String: RemoteEvolution] {
        var hints: [String: RemoteEvolution] = [:]
        for entry in store.state.dex where !store.isTradeLocked(entry.id) && !store.holdsEverstone(entry.id) {
            hints[entry.id] = cordEvolution(of: entry.id, store: store)
        }
        return hints
    }

    /// The species whose ability options a Capsule or Patch op needs loaded before it is applied.
    @MainActor
    static func detailsNeeded(for ops: [RemoteOp], store: CompanionStore) -> Set<Int> {
        Set(ops.compactMap { op in
            guard op.kind == kind, let payload = try? JSONDecoder().decode(Payload.self, from: op.payload),
                  ["capsule", "patch"].contains(payload.action) else { return nil }
            return store.trainable(id: payload.id)?.speciesID
        })
    }

    @MainActor
    private static func nature(_ payload: Payload, _ individual: TrainableIndividual, _ store: CompanionStore) -> String? {
        guard let nature = payload.nature.flatMap(PokemonNature.init(rawValue:)) else { return Reason.invalid }
        guard individual.nature != nature else { return Reason.unchanged }
        if let refusal = payment(store.mintPayment, seen: payload.price) { return refusal }
        return reason(store.changeNature(of: payload.id, to: nature))
    }

    @MainActor
    private static func herb(_ payload: Payload, _ individual: TrainableIndividual, _ store: CompanionStore) -> String? {
        guard individual.profile.mirrorHerb != true else { return Reason.unchanged }
        guard store.canUseMirrorHerb(on: individual) else { return Reason.notApplicable }
        if let refusal = payment(store.mirrorHerbPayment, seen: payload.price) { return refusal }
        return reason(store.useMirrorHerb(on: payload.id))
    }

    /// Nil when the payment the app would make now is the one the player saw: the bag's item, or a buy at that price.
    private static func payment(_ payment: MintPayment, seen price: Int?) -> String? {
        switch payment {
        case .stock: nil
        case .buy(let now): price == nil ? Reason.noItem : now == price ? nil : Reason.priceChanged
        case .short(let now): price == nil ? Reason.noItem : now == price ? Reason.noTokens : Reason.priceChanged
        }
    }

    @MainActor
    private static func ability(_ payload: Payload, _ individual: TrainableIndividual, _ store: CompanionStore) -> String? {
        guard let seen = payload.ability else { return Reason.invalid }
        let capsule = payload.action == "capsule"
        guard store.itemCount(capsule ? .abilityCapsule : .abilityPatch) > 0 else { return Reason.noItem }
        guard store.abilityOptions(of: individual) != nil else { return Reason.noData }
        guard let target = capsule ? store.capsuleTarget(of: individual) : store.patchTarget(of: individual),
              target == PokemonAbilityOption(name: seen.name, slot: seen.slot, isHidden: seen.hidden)
        else { return Reason.notApplicable }
        return reason(capsule ? store.useAbilityCapsule(on: payload.id) : store.useAbilityPatch(on: payload.id))
    }

    @MainActor
    private static func bottleCap(_ payload: Payload, _ store: CompanionStore) -> String? {
        guard let stat = payload.stat, PokemonStatCalculator.order.contains(stat) else { return Reason.invalid }
        guard store.itemCount(.bottleCap) > 0 else { return Reason.noItem }
        return reason(store.useBottleCap(on: payload.id, stat: stat))
    }

    @MainActor
    private static func form(_ payload: Payload, _ individual: TrainableIndividual, _ store: CompanionStore) -> String? {
        let speciesID = individual.speciesID
        guard let entry = PokemonForm.entries(speciesID: speciesID).first(where: { $0.form.rawValue == payload.form }),
              FormTool.tool(forSpecies: speciesID) != nil, (entry.pokemonID ?? speciesID) == payload.toPokemonID
        else { return Reason.notApplicable }
        guard store.ownedFormTool(speciesID: speciesID) != nil else { return Reason.noItem }
        return reason(store.changeForm(of: payload.id, to: entry.form))
    }

    @MainActor
    private static func moves(_ payload: Payload, _ individual: TrainableIndividual, _ store: CompanionStore,
                              _ battleEntry: BattleEntryStore) -> String? {
        let moves = payload.moves ?? [], machine = payload.machine ?? [], egg = payload.egg ?? []
        guard moves.count <= BattleEntry.maxMoves, Set(moves).count == moves.count,
              Set(machine).isSubset(of: moves), Set(egg).isSubset(of: moves) else { return Reason.invalid }
        guard Set(machine).isSubset(of: MachineMove.ownedIDs(in: store.state.inventory)) else { return Reason.noMachine }
        guard egg.isEmpty || individual.profile.mirrorHerb == true else { return Reason.noHerb }
        let current = battleEntry.moveChoices[payload.id].flatMap { $0.pokemonID == payload.pokemonID ? $0 : nil }
        let next = moves.isEmpty ? nil : MoveChoice(pokemonID: payload.pokemonID, moves: moves, machine: machine)
        guard next != current else { return Reason.unchanged }
        battleEntry.setMoves(next, for: payload.id)
        return nil
    }

    private static func reason(_ result: TrainingResult) -> String? {
        switch result {
        case .changed: nil
        case .unchanged: Reason.unchanged
        case .short: Reason.noTokens
        case .unavailable: Reason.notApplicable
        }
    }
}

extension PartyMember {
    /// Adds what `/트레이닝` reads: the ability slot, whether egg moves exist, and the forms a form-tool species has.
    mutating func addTrainingHints(_ individual: TrainableIndividual) {
        let profile = individual.profile
        abilitySlot = profile.abilitySlot
        abilityHidden = profile.abilityIsHidden ? true : nil
        eggMoves = EggMoves.hasAttacking(speciesID: individual.speciesID) ? true : nil
        let speciesID = individual.speciesID
        guard let tool = FormTool.tool(forSpecies: speciesID) else { return }
        form = PokemonForm.resolved(speciesID: speciesID, form: individual.form)?.rawValue
        formTool = tool.rawValue
        ownAbility = profile.abilityName
        forms = PokemonForm.entries(speciesID: speciesID).map { entry in
            RemoteFormOption(form: entry.form.rawValue, pokemonID: entry.pokemonID ?? speciesID,
                             ability: FormBattleData.of(speciesID: speciesID, form: entry.form)?.abilities.first?.name)
        }
    }
}
