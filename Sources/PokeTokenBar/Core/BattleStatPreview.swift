import Foundation

/// One line of a battle row's stats: what the bot fights with in that form.
struct BattleStatLine: Equatable, Sendable {
    enum Form: Hashable, Sendable { case normal, mega, stellar }
    enum Mark: String, Sendable { case raised = "↑", lowered = "↓" }

    let form: Form
    let stats: [PokemonComputedStat]
    let raised: String?
    let lowered: String?

    func mark(of stat: String) -> Mark? {
        stat == raised ? .raised : stat == lowered ? .lowered : nil
    }
}

/// The battle tab's stat lines, computed like the bot does: level capped at `BattleEntry.battleLevel`,
/// the uploaded IVs and nature, and the base stats of the form the Pokémon fights in.
enum BattleStatPreview {
    @MainActor
    static func lines(for fighter: BattleCandidate, speciesID: Int, in store: CompanionStore) -> [BattleStatLine] {
        lines(member: fighter.member, details: details(for: fighter, speciesID: speciesID, in: store),
              heldItem: store.heldItem(of: fighter.id), mega: store.megaStone(of: fighter.id, speciesID: speciesID),
              tera: store.teraForm(of: fighter.id, speciesID: speciesID))
    }

    /// The species id of the row; the raised line's candidate carries its form's variety id instead.
    @MainActor
    static func speciesID(of fighter: BattleCandidate, in store: CompanionStore) -> Int {
        store.dexEntry(for: fighter)?.finalID ?? fighter.member.pokemonID
    }

    /// The types the row's badges show: the battle form's, else the uploaded form's, else the species'.
    @MainActor
    static func types(for fighter: BattleCandidate, speciesID: Int, in store: CompanionStore) -> [String]? {
        if let types = store.megaStone(of: fighter.id, speciesID: speciesID)?.types
            ?? store.teraForm(of: fighter.id, speciesID: speciesID)?.types {
            return types
        }
        return (details(for: fighter, speciesID: speciesID, in: store) ?? store.pokemonDetailsByID[speciesID])?.types
    }

    /// The details of the form the member is uploaded as; nil for a variety the app has no battle data for.
    @MainActor
    static func details(for fighter: BattleCandidate, speciesID: Int, in store: CompanionStore) -> PokemonDetails? {
        let form = store.dexEntry(for: fighter)?.form
        guard fighter.member.pokemonID == speciesID || FormBattleData.of(speciesID: speciesID, form: form) != nil
        else { return nil }
        return store.pokemonDetails(speciesID: speciesID, form: form)
    }

    /// `details` must be the default form the member fights in; a row whose starting form the app has no base
    /// stats for (Terapagos' Terastal form, an Origin or Crowned item) gets no normal line.
    static func lines(member: PartyMember, details: PokemonDetails?, heldItem: ItemKind?,
                      mega: MegaStone?, tera: TeraForm.Sprite?) -> [BattleStatLine] {
        guard let ivs = member.ivs else { return [] }
        let level = min(member.level, BattleEntry.battleLevel)
        let nature = member.nature.flatMap(PokemonNature.init(rawValue:))
        let raised = PokemonStatCalculator.order.first { (nature?.modifier(for: $0) ?? 1) > 1 }
        let lowered = PokemonStatCalculator.order.first { (nature?.modifier(for: $0) ?? 1) < 1 }
        func line(_ form: BattleStatLine.Form, _ baseStats: [String: Int], speciesID: Int) -> BattleStatLine {
            BattleStatLine(form: form, stats: PokemonStatCalculator.stats(
                baseStats: baseStats, speciesID: speciesID, level: level, ivs: ivs, nature: nature),
                           raised: raised, lowered: lowered)
        }
        func ordered(_ stats: [Int]) -> [String: Int] {
            Dictionary(uniqueKeysWithValues: zip(PokemonStatCalculator.order, stats))
        }

        var lines: [BattleStatLine] = []
        if let details, startsInOwnForm(speciesID: details.speciesID, heldItem: heldItem) {
            lines.append(line(.normal, details.baseStats, speciesID: details.speciesID))
        }
        if let mega {
            lines.append(line(.mega, ordered(mega.stats), speciesID: mega.megaID))
        } else if let stats = tera?.stats {
            lines.append(line(.stellar, ordered(stats), speciesID: tera?.id ?? 0))
        }
        return lines
    }

    static func startsInOwnForm(speciesID: Int, heldItem: ItemKind?) -> Bool {
        if speciesID == TeraForm.terapagos { return false }
        guard let heldItem, (ItemKind.originItems + ItemKind.crownedItems).contains(heldItem) else { return true }
        return heldItem.holderSpeciesID != speciesID
    }
}
