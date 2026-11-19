import Foundation

/// One Pokémon the player owns, as the Box lists it. `id` is the instance ID that held items, trade locks and
/// battle slots are keyed by — the raised Pokémon's `profile.instanceID`, a graduated one's `DexEntry.id`.
struct BoxIndividual: Identifiable {
    /// `parked` is the line Pokémon set aside while a graduate is raised; `stored` is a line sent to the Box
    /// before it graduated.
    enum Role { case raising, parked, friend, graduated, stored }

    let id: String
    /// The line Pokémon's synthesized entry, or the graduated record.
    let entry: DexEntry
    let role: Role
    /// Walks beside the raised Pokémon: a `.friend` graduate, or a `.stored` line picked as a friend.
    var isFriend = false

    var speciesID: Int { entry.finalID }
    var level: Int { entry.profile?.level ?? 5 }
}

/// What an individual holds: a battle/evolution item or a Mega Stone.
enum HeldItemRef: Hashable {
    case item(ItemKind)
    case stone(MegaStone)

    var inventoryKey: String {
        switch self {
        case .item(let kind): kind.rawValue
        case .stone(let stone): stone.inventoryKey
        }
    }

    func name(_ l: L) -> String {
        switch self {
        case .item(let kind): l.itemName(kind)
        case .stone(let stone): l.megaStoneName(stone)
        }
    }
}

enum BoxSortOption: String, CaseIterable, Identifiable, Sendable, Codable {
    case recent, level, number, name

    var id: String { rawValue }
}

extension CompanionStore {
    /// Every individual that can hold an item: the raised Pokémon first, then the graduated ones that were not
    /// released. Same membership as `CompanionState.ownedInstanceIDs`.
    var boxIndividuals: [BoxIndividual] {
        var result: [BoxIndividual] = []
        if let entry = raisedDexEntry, let id = entry.profile?.instanceID {
            result.append(BoxIndividual(id: id, entry: entry, role: isLineParked ? .parked : .raising))
        }
        for entry in state.dex where entry.releasedAt == nil {
            let role: BoxIndividual.Role = entry.id == state.raisedEntryID ? .raising
                : state.isFriend(boxID: entry.id) ? .friend : .graduated
            result.append(BoxIndividual(id: entry.id, entry: entry, role: role, isFriend: role == .friend))
        }
        for (id, stored) in state.storedLines.sorted(by: { $0.key < $1.key }) {
            result.append(BoxIndividual(id: id, entry: storedBoxEntry(id: id, stored.mon), role: .stored,
                                        isFriend: state.isFriend(boxID: id)))
        }
        return result
    }

    /// The stored line as it stands now; names and the time it was stored come from its Pokédex record.
    func storedBoxEntry(id: String, _ mon: MonState) -> DexEntry {
        let record = state.dex.first { $0.id == id }
        return DexEntry(id: id, baseID: mon.baseID, finalID: mon.currentID,
                        chainOrder: Array(mon.pathIDs.prefix(mon.stageIndex + 1)), rarity: mon.rarity,
                        caughtAt: record?.caughtAt, isShiny: mon.displaysShiny, nature: mon.nature,
                        profile: mon.profile, names: record?.names, form: mon.form, prayers: mon.prayers)
    }

    func boxIndividual(id: String) -> BoxIndividual? {
        boxIndividuals.first { $0.id == id }
    }

    /// The Box id of a Pokédex entry; the synthesized raised entry maps to its profile's instance ID.
    func boxID(of entry: DexEntry) -> String? {
        if isActiveDexEntry(entry) { return entry.profile?.instanceID }
        return entry.releasedAt == nil || state.storedLines[entry.id] != nil ? entry.id : nil
    }

    func boxCount(speciesID: Int) -> Int {
        boxIndividuals.lazy.filter { $0.speciesID == speciesID }.count
    }

    func heldItemRef(of instanceID: String) -> HeldItemRef? {
        heldItem(of: instanceID).map(HeldItemRef.item) ?? heldMegaStone(of: instanceID).map(HeldItemRef.stone)
    }

    var currentHeldItemRef: HeldItemRef? {
        guard let id = raisedGraduate?.id ?? state.active?.profile?.instanceID else { return nil }
        return heldItemRef(of: id)
    }

    /// A Pokédex row is the representative when it names this individual's species and form.
    func isRepresentative(_ entry: DexEntry) -> Bool {
        guard state.representativeSpeciesID == entry.finalID else { return false }
        let form = PokemonForm.resolved(speciesID: entry.finalID, form: entry.form)
        return form == nil || state.representativeForm == form
    }

    /// Sets this individual's species and form as the representative, or clears it when it already is one.
    @discardableResult
    func toggleRepresentative(of entry: DexEntry) -> Bool {
        if isRepresentative(entry) { return setRepresentativeSpeciesID(nil) }
        return setRepresentativeSpeciesID(entry.finalID, form: PokemonForm.resolved(speciesID: entry.finalID, form: entry.form))
    }

    /// The sprite the Box draws for an individual: its Mega form while it holds the matching stone.
    func boxMegaSpriteID(_ individual: BoxIndividual) -> Int? {
        megaSpriteID(instanceID: individual.id, speciesID: individual.speciesID)
    }

    /// Items an individual can take from the bag: held and evolution items, then Mega Stones.
    var equippableBagItems: [HeldItemRef] {
        ownedItems.filter { $0.kind.isEquippable }.map { HeldItemRef.item($0.kind) }
            + ownedMegaStones().map { HeldItemRef.stone($0.stone) }
    }

    func bagCount(of ref: HeldItemRef) -> Int {
        switch ref {
        case .item(let kind): itemCount(kind)
        case .stone(let stone): megaStoneCount(stone)
        }
    }

    @discardableResult
    func equip(_ ref: HeldItemRef, to instanceID: String) -> Bool {
        switch ref {
        case .item(let kind): equip(kind, to: instanceID)
        case .stone(let stone): equip(stone, to: instanceID)
        }
    }

    /// The one place Box filtering lives. A selected type matches when the species has any of them; the other
    /// filters narrow together. `fightingIDs` is the battle lineup (`TradePool.fightingIDs`).
    func filteredBoxIndividuals(query: String = "", speciesID: Int? = nil, shinyOnly: Bool = false,
                                hasItemOnly: Bool = false, sort: BoxSortOption = .recent,
                                types: Set<PokemonType> = [], rarity: Rarity? = nil, region: PokedexRegion? = nil,
                                inLineupOnly: Bool = false, tradableOnly: Bool = false,
                                level: BoxLevelFilter = .any, fightingIDs: Set<String> = []) -> [BoxIndividual] {
        let matcher = DexSearchMatcher(query)
        let listed = tradableOnly ? Set(TradePool.listed(state: state, fightingIDs: fightingIDs).map(\.id)) : []
        let result = boxIndividuals.filter { individual in
            if let speciesID, individual.speciesID != speciesID { return false }
            if shinyOnly, !individual.entry.isShiny { return false }
            if hasItemOnly, state.heldItems[individual.id] == nil { return false }
            if let matcher, !matcher.matches(individual.entry) { return false }
            if let rarity, individual.entry.rarity != rarity { return false }
            if let region, !region.dexRange.contains(individual.speciesID) { return false }
            if !level.admits(individual.level) { return false }
            if inLineupOnly, !fightingIDs.contains(individual.id) { return false }
            if tradableOnly, !listed.contains(individual.id) || !isTradableNow(individual, fightingIDs: fightingIDs) {
                return false
            }
            if !types.isEmpty,
               !speciesTypes(individual.speciesID).contains(where: { PokemonType(apiName: $0).map(types.contains) ?? false }) {
                return false
            }
            return true
        }
        return sortBox(result, by: sort)
    }

    func filteredBoxIndividuals(query: String = "", speciesID: Int? = nil, filter: BoxFilter,
                                fightingIDs: Set<String> = []) -> [BoxIndividual] {
        filteredBoxIndividuals(query: query, speciesID: speciesID, shinyOnly: filter.shinyOnly,
                               hasItemOnly: filter.hasItemOnly, sort: filter.sort, types: filter.types,
                               rarity: filter.rarity, region: filter.region, inLineupOnly: filter.inLineupOnly,
                               tradableOnly: filter.tradableOnly, level: filter.level, fightingIDs: fightingIDs)
    }

    /// Could be offered in a trade right now: not the raised one, not fighting, not already in an open trade.
    func isTradableNow(_ individual: BoxIndividual, fightingIDs: Set<String>) -> Bool {
        individual.role != .raising && individual.role != .stored && !isTradeLocked(individual.id)
            && TradePool.refusal(for: individual.entry, fightingIDs: fightingIDs, activeID: nil) == nil
    }

    private func sortBox(_ list: [BoxIndividual], by sort: BoxSortOption) -> [BoxIndividual] {
        func newer(_ a: BoxIndividual, _ b: BoxIndividual) -> Bool {
            let (d0, d1) = (a.entry.caughtAt ?? .distantPast, b.entry.caughtAt ?? .distantPast)
            return d0 != d1 ? d0 > d1 : a.id < b.id
        }
        switch sort {
        case .recent:
            return list.sorted {
                if ($0.role == .raising) != ($1.role == .raising) { return $0.role == .raising }
                return newer($0, $1)
            }
        case .level:
            return list.sorted { $0.level != $1.level ? $0.level > $1.level : newer($0, $1) }
        case .number:
            return list.sorted { $0.speciesID != $1.speciesID ? $0.speciesID < $1.speciesID : newer($0, $1) }
        case .name:
            return list.sorted {
                let order = dexEntryName($0.entry).localizedCompare(dexEntryName($1.entry))
                return order != .orderedSame ? order == .orderedAscending : newer($0, $1)
            }
        }
    }
}
