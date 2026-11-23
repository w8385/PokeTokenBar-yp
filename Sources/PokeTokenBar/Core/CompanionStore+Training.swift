import Foundation

/// What a training item did. Nothing is used up or paid unless the result is `changed`.
enum TrainingResult: Equatable {
    case changed
    /// The Pokémon already has what was picked.
    case unchanged
    /// No Mint in the bag and not enough tokens to buy one.
    case short
    case unavailable
}

/// How a nature change would be paid.
enum MintPayment: Equatable {
    case stock(Int)
    case buy(price: Int)
    case short(price: Int)
}

/// One individual's trainable values, wherever it lives in the save.
struct TrainableIndividual: Equatable {
    let speciesID: Int
    var nature: PokemonNature?
    var profile: PokemonProfile
    var form: PokemonForm?

    static func find(id: String, in state: CompanionState) -> TrainableIndividual? {
        if let active = state.active, active.profile?.instanceID == id, let profile = active.profile {
            if active.dittoDisguise != nil, !active.dittoRevealed { return nil }
            return TrainableIndividual(speciesID: active.currentID, nature: active.nature, profile: profile, form: active.form)
        }
        if let mon = state.storedLines[id]?.mon, let profile = mon.profile {
            return TrainableIndividual(speciesID: mon.currentID, nature: mon.nature, profile: profile, form: mon.form)
        }
        if let entry = state.dex.first(where: { $0.id == id && !$0.isReleased }), let profile = entry.profile {
            return TrainableIndividual(speciesID: entry.finalID, nature: entry.nature, profile: profile, form: entry.form)
        }
        return nil
    }
}

extension CompanionStore {
    func trainable(id: String) -> TrainableIndividual? {
        TrainableIndividual.find(id: id, in: state)
    }

    /// Box id of the Pokémon on Home: the raised graduate, else the line Pokémon.
    var homeBoxID: String? { state.raisedEntryID ?? state.active?.profile?.instanceID }

    var mintPayment: MintPayment { payment(for: .mint, listPrice: Mint.price) }

    var mirrorHerbPayment: MintPayment { payment(for: .mirrorHerb, listPrice: MirrorHerb.price) }

    private func payment(for kind: ItemKind, listPrice: Int) -> MintPayment {
        let stock = itemCount(kind)
        if stock > 0 { return .stock(stock) }
        let price = price(of: kind) ?? listPrice
        return availableTokens >= price ? .buy(price: price) : .short(price: price)
    }

    /// A Mirror Herb does something only once per individual, and only for a species with attacking egg moves.
    func canUseMirrorHerb(on individual: TrainableIndividual) -> Bool {
        individual.profile.mirrorHerb != true && EggMoves.hasAttacking(speciesID: individual.speciesID)
    }

    /// The abilities of the individual's current form, or nil until the species details are loaded.
    func abilityOptions(of individual: TrainableIndividual) -> [PokemonAbilityOption]? {
        if let form = FormBattleData.of(speciesID: individual.speciesID, form: individual.form) { return form.abilities }
        return pokemonDetailsByID[individual.speciesID]?.abilities
    }

    /// The Capsule's target: the other regular ability. Nil for a hidden ability or a single regular one.
    func capsuleTarget(of individual: TrainableIndividual) -> PokemonAbilityOption? {
        guard !individual.profile.abilityIsHidden, let options = abilityOptions(of: individual) else { return nil }
        return options.first { !$0.isHidden && $0.slot != individual.profile.abilitySlot }
    }

    /// The Patch's target: the hidden ability from a regular one, or the first regular one from the hidden one.
    func patchTarget(of individual: TrainableIndividual) -> PokemonAbilityOption? {
        guard let options = abilityOptions(of: individual) else { return nil }
        let regular = options.filter { !$0.isHidden }.sorted { $0.slot < $1.slot }
        return individual.profile.abilityIsHidden ? regular.first : options.first(where: \.isHidden)
    }

    /// The loaded species details with the types, base stats and abilities of the individual's form.
    func pokemonDetails(speciesID: Int, form: PokemonForm?) -> PokemonDetails? {
        pokemonDetailsByID[speciesID]?.applying(FormBattleData.of(speciesID: speciesID, form: form))
    }

    /// The key item that switches this species' forms, when the player owns it.
    func ownedFormTool(speciesID: Int) -> ItemKind? {
        FormTool.tool(forSpecies: speciesID).flatMap { itemCount($0) > 0 ? $0 : nil }
    }

    /// Who a training item can be used on from the Bag: the raised Pokémon first, then the Box. A form key item
    /// lists only its own species, a Mirror Herb only those it would unlock egg moves for.
    func trainingTargets(for kind: ItemKind) -> [BoxIndividual] {
        let species = FormTool.species(of: kind)
        return boxIndividuals.filter { individual in
            guard !isTradeLocked(individual.id), let trainable = trainable(id: individual.id) else { return false }
            if kind == .mirrorHerb { return canUseMirrorHerb(on: trainable) }
            return species.map { $0.contains(individual.speciesID) } ?? true
        }
    }
}

extension PokemonProfile {
    mutating func setAbility(_ option: PokemonAbilityOption) {
        abilitySlot = option.slot
        abilityIsHidden = option.isHidden
        abilityName = option.name
    }
}

extension CompanionStore {
    // MARK: Training items (Mint, Ability Capsule and Patch, Bottle Caps, form tools)

    /// Applies `change` to one individual when it does something; `pay` runs just before the write and may
    /// refuse. Nothing is used up or paid for otherwise. Saves once.
    private func train(_ id: String, pay: () -> Bool, _ change: (inout TrainableIndividual) -> Void) -> TrainingResult {
        guard !isTradeLocked(id), let before = trainable(id: id) else { return .unavailable }
        var after = before
        change(&after)
        guard after != before else { return .unchanged }
        guard pay() else { return .short }
        if state.active?.profile?.instanceID == id {
            state.active?.nature = after.nature
            state.active?.profile = after.profile
            state.active?.form = after.form
        } else if state.storedLines[id] != nil {
            state.storedLines[id]?.mon.nature = after.nature
            state.storedLines[id]?.mon.profile = after.profile
            state.storedLines[id]?.mon.form = after.form
        } else if let index = state.dex.firstIndex(where: { $0.id == id && !$0.isReleased }) {
            state.dex[index].nature = after.nature
            state.dex[index].profile = after.profile
            state.dex[index].form = after.form
        }
        save()
        return .changed
    }

    private func useOne(_ kind: ItemKind) -> Bool {
        guard itemCount(kind) > 0 else { return false }
        state.inventory[kind.rawValue] = itemCount(kind) - 1
        return true
    }

    /// Sets the picked nature with a Mint from the bag, or buys one and uses it in the same step.
    @discardableResult
    func changeNature(of id: String, to nature: PokemonNature) -> TrainingResult {
        let result = train(id, pay: { useOrBuy(.mint, mintPayment) }) { $0.nature = nature }
        if result == .changed, id == homeBoxID {
            mintFeedbackNature = nature
            mintFeedbackSeq += 1
        }
        return result
    }

    /// Unlocks the individual's attacking egg moves with a Mirror Herb from the bag, or buys one and uses it in the
    /// same step.
    @discardableResult
    func useMirrorHerb(on id: String) -> TrainingResult {
        guard let individual = trainable(id: id), EggMoves.hasAttacking(speciesID: individual.speciesID) else {
            return .unavailable
        }
        return train(id, pay: { useOrBuy(.mirrorHerb, mirrorHerbPayment) }) { $0.profile.mirrorHerb = true }
    }

    private func useOrBuy(_ kind: ItemKind, _ payment: MintPayment) -> Bool {
        switch payment {
        case .stock: return useOne(kind)
        case .buy(let price): return spend(price)
        case .short: return false
        }
    }

    @discardableResult
    func useAbilityCapsule(on id: String) -> TrainingResult {
        guard itemCount(.abilityCapsule) > 0, let target = trainable(id: id).flatMap(capsuleTarget) else {
            return .unavailable
        }
        return train(id, pay: { useOne(.abilityCapsule) }) { $0.profile.setAbility(target) }
    }

    @discardableResult
    func useAbilityPatch(on id: String) -> TrainingResult {
        guard itemCount(.abilityPatch) > 0, let target = trainable(id: id).flatMap(patchTarget) else {
            return .unavailable
        }
        return train(id, pay: { useOne(.abilityPatch) }) { $0.profile.setAbility(target) }
    }

    @discardableResult
    func useBottleCap(on id: String, stat: String) -> TrainingResult {
        guard itemCount(.bottleCap) > 0, PokemonStatCalculator.order.contains(stat) else { return .unavailable }
        return train(id, pay: { useOne(.bottleCap) }) { $0.profile.ivs[stat] = BottleCap.maxIV }
    }

    @discardableResult
    func useGoldBottleCap(on id: String) -> TrainingResult {
        guard itemCount(.goldBottleCap) > 0 else { return .unavailable }
        return train(id, pay: { useOne(.goldBottleCap) }) { individual in
            for stat in PokemonStatCalculator.order { individual.profile.ivs[stat] = BottleCap.maxIV }
        }
    }

    /// Switches the individual to `form` with the key item its species needs; the item stays in the bag.
    @discardableResult
    func changeForm(of id: String, to form: PokemonForm) -> TrainingResult {
        guard let individual = trainable(id: id), ownedFormTool(speciesID: individual.speciesID) != nil,
              PokemonForm.forms(speciesID: individual.speciesID).contains(form) else { return .unavailable }
        guard PokemonForm.resolved(speciesID: individual.speciesID, form: individual.form) != form else { return .unchanged }
        return train(id, pay: { true }) { $0.form = form }
    }

    // MARK: 진화의 돌

    /// 돌 사용 결과 — wrongStone 이면 돌은 그대로 남는다.
    enum StoneUseResult: Equatable { case evolved, wrongStone, unavailable, notReady, everstone }

    /// 돌을 쓸 수 있는 상태 — 돌 재고 + 활성 포켓몬 + 라인 로딩 완료(위장 중인 메타몽 제외).
    func canUseStone(_ kind: ItemKind) -> Bool {
        guard kind.isEvolutionStone, itemCount(kind) > 0, let a = state.active, !isLineParked, currentLine != nil else { return false }
        return a.dittoDisguise == nil || a.dittoRevealed
    }

    /// 현재 형태가 이 돌로 진화하는 갈래를 가졌나.
    func stoneFits(_ kind: ItemKind) -> Bool {
        stoneTarget(kind) != nil
    }

    private func stoneTarget(_ kind: ItemKind) -> EvoNode? {
        guard let item = kind.evolutionItemName, let a = state.active, !isLineParked,
              let node = currentLine?.tree.node(withID: a.currentID) else { return nil }
        return node.children(for: a.profile?.gender).first { $0.evolves(withItem: item) }
    }

    /// 돌 1개로 그 돌의 갈래로 바로 진화 — 현재 단계 XP는 그대로 이어진다. 안 맞는 돌이면 소모 없이 wrongStone.
    @discardableResult
    func useEvolutionStone(_ kind: ItemKind) -> StoneUseResult {
        guard canUseStone(kind), let line = currentLine, let a = state.active,
              let node = line.tree.node(withID: a.currentID) else { return .unavailable }
        guard let next = stoneTarget(kind) else { return .wrongStone }
        if holdsEverstone(a.profile?.instanceID) { return .everstone }
        var rest: [EvolutionRequirement] = []
        if let path = EvolutionRules.rule(for: next.speciesID)?.path(usingBag: kind) {
            rest = path.filter { $0 != .bag(kind) }
            let context = evolutionContext(for: a)
            guard rest.allSatisfy({ $0.isMet(in: context) }) else { return .notReady }
        }
        spendEvolutionRequirements(of: rest, into: next.speciesID, instanceID: a.profile?.instanceID)
        state.inventory[kind.rawValue] = itemCount(kind) - 1
        replanEvolution(from: node, to: next, base: a)
        completeEvolution(of: a, to: next, through: rest + [.bag(kind)], in: line, usedAtStage: a.usedAtStage)
        applyUsage(0)   // 이어받은 XP가 다음 임계를 넘었으면 이어서 진화하고, 저장한다.
        return .evolved
    }
}
