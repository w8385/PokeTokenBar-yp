import Foundation

extension CompanionStore {
    /// The Catch Log row behind a candidate. The Pokémon being raised has a synthesized one.
    func dexEntry(for candidate: BattleCandidate) -> DexEntry? {
        candidate.dexEntry ?? dexEntries.first { isActiveDexEntry($0) }
    }

    /// The candidate for a Catch Log individual; nil for a released or unsupported one.
    func battleCandidate(for entry: DexEntry) -> BattleCandidate? {
        let id = isActiveDexEntry(entry) ? entry.profile?.instanceID : entry.id
        return BattleEntry.candidates(in: state).first { $0.id == id }
    }

    /// Owned candidates matching the Pokédex search and filters, the raised one first, then by level.
    func filteredBattleCandidates(query: String = "", rarity: Rarity? = nil,
                                  shinyOnly: Bool = false) -> [BattleCandidate] {
        let matcher = DexSearchMatcher(query)
        return BattleEntry.candidates(in: state).compactMap { candidate -> (BattleCandidate, DexEntry)? in
            guard let entry = dexEntry(for: candidate) else { return nil }
            if let rarity, entry.rarity != rarity { return nil }
            if shinyOnly, !entry.isShiny { return nil }
            if let matcher, !matcher.matches(entry) { return nil }
            return (candidate, entry)
        }
        .sorted {
            if ($0.0.dexEntry == nil) != ($1.0.dexEntry == nil) { return $0.0.dexEntry == nil }
            if $0.0.member.level != $1.0.member.level { return $0.0.member.level > $1.0.member.level }
            return $0.1.finalID < $1.1.finalID
        }
        .map(\.0)
    }

    /// A Pokédex grid cell for an individual, so the picker draws the same cell as the Pokédex.
    func battleSpecies(for candidate: BattleCandidate) -> DexSpecies? {
        guard let entry = dexEntry(for: candidate) else { return nil }
        return DexSpecies(id: entry.finalID, name: dexEntryName(entry), rarity: entry.rarity,
                          isShiny: entry.isShiny, isRaising: candidate.dexEntry == nil,
                          form: PokemonForm.resolved(speciesID: entry.finalID, form: entry.form),
                          names: entry.names?[entry.finalID], hasNormal: !entry.isShiny,
                          isFemale: entry.profile?.gender == .female)
    }
}
