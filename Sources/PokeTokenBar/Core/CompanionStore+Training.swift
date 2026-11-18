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
}

extension CompanionStore {
    func trainable(id: String) -> TrainableIndividual? {
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
