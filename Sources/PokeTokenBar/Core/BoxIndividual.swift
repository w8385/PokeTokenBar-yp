import Foundation

/// One Pokémon the player owns, as the Box lists it. `id` is the instance ID that held items, trade locks and
/// battle slots are keyed by — the raised Pokémon's `profile.instanceID`, a graduated one's `DexEntry.id`.
struct BoxIndividual: Identifiable {
    /// `parked` is the line Pokémon set aside while a graduate is raised.
    enum Role { case raising, parked, friend, graduated }

    let id: String
    /// The line Pokémon's synthesized entry, or the graduated record.
    let entry: DexEntry
    let role: Role

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

enum BoxSortOption: String, CaseIterable, Identifiable, Sendable {
    case recent, level, number, name

    var id: String { rawValue }
}

extension CompanionStore {
    /// Every individual that can hold an item: the raised Pokémon first, then the graduated ones that were not
    /// released. Same membership as `CompanionState.ownedInstanceIDs`.
    var boxIndividuals: [BoxIndividual] {
        let friends = Set(state.friendEntryIDs)
        var result: [BoxIndividual] = []
        if let entry = raisedDexEntry, let id = entry.profile?.instanceID {
            result.append(BoxIndividual(id: id, entry: entry, role: isLineParked ? .parked : .raising))
        }
        for entry in state.dex where entry.releasedAt == nil {
            let role: BoxIndividual.Role = entry.id == state.raisedEntryID ? .raising
                : friends.contains(entry.id) ? .friend : .graduated
            result.append(BoxIndividual(id: entry.id, entry: entry, role: role))
        }
        return result
    }

    func boxIndividual(id: String) -> BoxIndividual? {
        boxIndividuals.first { $0.id == id }
    }

    /// The Box id of a Pokédex entry; the synthesized raised entry maps to its profile's instance ID.
    func boxID(of entry: DexEntry) -> String? {
        isActiveDexEntry(entry) ? entry.profile?.instanceID : (entry.releasedAt == nil ? entry.id : nil)
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

    func filteredBoxIndividuals(query: String = "", speciesID: Int? = nil, shinyOnly: Bool = false,
                                hasItemOnly: Bool = false, sort: BoxSortOption = .recent) -> [BoxIndividual] {
        let matcher = DexSearchMatcher(query)
        let result = boxIndividuals.filter { individual in
            if let speciesID, individual.speciesID != speciesID { return false }
            if shinyOnly, !individual.entry.isShiny { return false }
            if hasItemOnly, state.heldItems[individual.id] == nil { return false }
            if let matcher, !matcher.matches(individual.entry) { return false }
            return true
        }
        return sortBox(result, by: sort)
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
