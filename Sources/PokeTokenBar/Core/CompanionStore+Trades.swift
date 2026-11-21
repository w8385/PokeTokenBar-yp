import Foundation

extension CompanionStore {
    // MARK: 교환

    /// The newest trade arrival or Linking Cord evolution, shown once by the popover banner.
    struct TradeArrival: Equatable, Identifiable {
        let id: Int
        let entryID: String
        /// Nil for a Linking Cord evolution, which has no trade partner.
        let fromName: String?
        let receivedID: Int
        /// The sender's wording until the evolution line is known.
        var receivedName: String
        var evolvedID: Int?
        var evolvedName: String?
        let isShiny: Bool
    }

    func dismissTradeArrival() { tradeArrival = nil }

    enum TradeEvolutionResult: Equatable { case evolved, noEvolution, notReady, unavailable, everstone }
    /// `wrongTarget` and `notReady` (it evolves by trade, but the item or friend it needs is missing) leave the
    /// cord in the bag.
    /// `listed`: the individual is in an open trade, and a cord evolution would use up the item the trade carries.
    enum CordUseResult: Equatable { case evolved, wrongTarget, notReady, unavailable, listed, everstone }

    private static let appliedTradeLimit = 200
    /// An offer lives 24 hours on the bot; a lock the bot stops reporting is dropped at the next sync, and one it
    /// can no longer report (bot unreachable) lapses with the offer.
    private static let tradeLockLifetime: TimeInterval = 24 * 3600


    func isTradeLocked(_ instanceID: String) -> Bool {
        tradeLocks[instanceID].map { $0 > clock() } ?? false
    }

    func lockForTrade(_ instanceID: String) {
        tradeLocks[instanceID] = clock().addingTimeInterval(Self.tradeLockLifetime)
    }

    func setTradeLocked(_ ids: Set<String>) {
        let expiry = clock().addingTimeInterval(Self.tradeLockLifetime)
        tradeLocks = Dictionary(uniqueKeysWithValues: ids.map { ($0, expiry) })
    }

    func tradePool(fightingIDs: Set<String>, moveChoices: [String: MoveChoice] = [:]) -> [TradePoolEntry] {
        TradePool.build(state: state, fightingIDs: fightingIDs, moveChoices: moveChoices, name: dexEntryName)
    }

    /// Nil only for an individual in the pool the app sends, so the post and offer buttons match what the bot holds.
    func tradeRefusal(for entry: DexEntry, fightingIDs: Set<String>) -> TradeRefusal? {
        ownerRefusal(for: entry, fightingIDs: fightingIDs)
            ?? TradePool.listingRefusal(for: entry, state: state, fightingIDs: fightingIDs)
    }

    /// The pool in the order the bot keeps it, newest first.
    func tradableEntries(fightingIDs: Set<String>) -> [DexEntry] {
        TradePool.listed(state: state, fightingIDs: fightingIDs)
            .filter { ownerRefusal(for: $0, fightingIDs: fightingIDs) == nil }
    }

    private func ownerRefusal(for entry: DexEntry, fightingIDs: Set<String>) -> TradeRefusal? {
        if state.storedLines[entry.id] != nil { return .unavailable }
        return TradePool.refusal(for: entry, fightingIDs: fightingIDs, activeID: activeDexEntry?.id,
                          raisedID: state.raisedEntryID, lineParked: isLineParked)
    }

    /// Applies completed trades once each and returns the ids safe to acknowledge (applied now or earlier).
    /// A delivery this build cannot show is left out, so the bot offers it again after an update.
    @discardableResult
    func applyTrades(_ deliveries: [TradeDelivery]) -> [String] {
        var settled: [String] = []
        var changed = false
        for delivery in deliveries {
            if state.appliedTradeIDs.contains(delivery.tradeID) {
                settled.append(delivery.tradeID)
                continue
            }
            let now = clock()
            let sender = Self.cleanedTrainerName(delivery.fromName)
            let given = state.dex.first { $0.id == delivery.giveID && $0.releasedAt == nil }
            guard let arrived = Self.receivedEntry(delivery.receive.entry, from: sender, partner: given?.finalID,
                                                   now: now) else { continue }
            if let index = state.dex.firstIndex(where: { $0.id == delivery.giveID && $0.releasedAt == nil }) {
                state.dex[index].releasedAt = now
                state.dex[index].tradedTo = sender
                settleSentItem(of: delivery)
            }
            state.dex.append(arrived)
            state.appliedTradeIDs.append(delivery.tradeID)
            if state.appliedTradeIDs.count > Self.appliedTradeLimit {
                state.appliedTradeIDs.removeFirst(state.appliedTradeIDs.count - Self.appliedTradeLimit)
            }
            settled.append(delivery.tradeID)
            changed = true
            tradeArrivalSeq += 1
            let name = delivery.receive.name
            tradeArrival = TradeArrival(id: tradeArrivalSeq, entryID: arrived.id, fromName: sender,
                                        receivedID: arrived.finalID, receivedName: name, isShiny: arrived.isShiny)
            notifyCompanionEvent(l.notifTradeTitle, l.notifTradeBody(name, from: sender))
        }
        guard changed else { return settled }
        state.reconcileRepresentativeSelection()
        save()
        Task { await resolveTradeEvolutions() }
        return settled
    }

    static let remoteOpResultLimit = 500

    /// Applies each op above `remoteOpsLastID` once, in id order, and saves once. An op whose kind this build does
    /// not know is cancelled as unsupported; a failing op is cancelled and the rest still apply.
    func applyRemoteOps(_ ops: [RemoteOp], appliers: [String: RemoteOpApplier]) {
        let fresh = ops.filter { $0.id > state.remoteOpsLastID }.sorted { $0.id < $1.id }
        guard !fresh.isEmpty else { return }
        for op in fresh {
            let reason = appliers[op.kind].map { $0(self, op.payload) } ?? RemoteOpReason.unsupported
            state.remoteOpResults.append(RemoteOpResult(id: op.id, reason: reason))
            state.remoteOpsLastID = op.id
        }
        if state.remoteOpResults.count > Self.remoteOpResultLimit {
            state.remoteOpResults.removeFirst(state.remoteOpResults.count - Self.remoteOpResultLimit)
        }
        save()
    }

    func prepareRemoteOps(_ ops: [RemoteOp]) async {
        for speciesID in RemoteTrain.detailsNeeded(for: ops, store: self).sorted() {
            await loadPokemonDetails(speciesID: speciesID)
        }
    }

    func acknowledgeRemoteOps(_ ids: [Int]) {
        let acknowledged = Set(ids)
        guard state.remoteOpResults.contains(where: { acknowledged.contains($0.id) }) else { return }
        state.remoteOpResults.removeAll { acknowledged.contains($0.id) }
        save()
    }

    /// The first epoch is only recorded. Another one is a new bot database whose op ids start over, so the ids and
    /// results of the old one are dropped.
    func adoptRemoteOpsEpoch(_ epoch: String) {
        guard state.remoteOpsEpoch != epoch else { return }
        if state.remoteOpsEpoch != nil {
            state.remoteOpsLastID = 0
            state.remoteOpResults = []
        }
        state.remoteOpsEpoch = epoch
        save()
    }

    /// Gives each listed Pokémon its new item (nil takes it off) for a lineup `RemoteLineup` has checked: every
    /// changing holder's item goes back to the bag first, then each takes its new one from the bag.
    func moveHeldItems(_ changes: [(id: String, key: String?)]) {
        let changing = changes.filter { state.heldItems[$0.id] != $0.key }
        guard !changing.isEmpty else { return }
        let megaBefore = Dictionary(changing.map { ($0.id, megaSpriteID(ofInstance: $0.id)) }, uniquingKeysWith: { first, _ in first })
        for change in changing {
            if let previous = state.heldItems[change.id] { state.inventory[previous, default: 0] += 1 }
            state.heldItems[change.id] = nil
        }
        for change in changing {
            guard let key = change.key else { continue }
            state.inventory[key, default: 0] -= 1
            state.heldItems[change.id] = key
        }
        for change in changing { announceMegaChange(of: change.id, from: megaBefore[change.id] ?? nil) }
        reevaluateEvolution()
    }

    /// The trade item the bot says left with the Pokémon is taken out of the game: off the Pokémon if it still
    /// holds it, else out of the bag where an earlier unequip put it. Anything else it holds goes back to the bag
    /// with the orphan sweep in `save()`. An older bot does not say, so only a held trade item is removed.
    private func settleSentItem(of delivery: TradeDelivery) {
        let id = delivery.giveID
        guard delivery.reportsGiveHeldItem else {
            if heldItem(of: id)?.isTradeEvolutionItem == true { state.heldItems[id] = nil }
            return
        }
        guard let traveled = delivery.giveHeldItem.flatMap(ItemKind.init(rawValue:))?.tradeItemKey else { return }
        if state.heldItems[id] == traveled {
            state.heldItems[id] = nil
        } else {
            state.inventory[traveled] = max(0, (state.inventory[traveled] ?? 0) - 1)
        }
    }

    /// A received individual is a new one here: fresh id, no names, evolution pending until the line is known.
    /// `partner` is the species this side gave for it; the wire's own value is never trusted.
    nonisolated static func receivedEntry(_ wire: DexEntry, from sender: String, partner: Int? = nil,
                                          now: Date) -> DexEntry? {
        guard var profile = wire.profile,
              PokemonAssets.isSupported(speciesID: wire.baseID), PokemonAssets.isSupported(speciesID: wire.finalID)
        else { return nil }
        var entry = wire
        let id = UUID().uuidString
        profile.instanceID = id
        profile.sanitize()
        entry.id = id
        entry.profile = profile
        entry.names = nil
        entry.namesVersion = nil
        entry.releasedAt = nil
        entry.tradedTo = nil
        entry.caughtAt = now
        entry.originalTrainer = sender
        entry.tradeEvolutionPending = true
        entry.tradeHeldItem = wire.tradeHeldItem.flatMap { ItemKind(rawValue: $0)?.tradeItemKey }
        entry.tradePartnerID = partner
        if entry.chainOrder.last != entry.finalID {
            entry.chainOrder = entry.baseID == entry.finalID ? [entry.baseID] : [entry.baseID, entry.finalID]
        }
        return entry
    }

    nonisolated static func cleanedTrainerName(_ raw: String) -> String {
        let name = raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let trimmed = String(String.UnicodeScalarView(name)).trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(40))
    }

    /// Evolves every received individual that has a trade evolution. Offline, the flag stays and the next
    /// launch or sync tries again.
    func resolveTradeEvolutions() async {
        guard !isResolvingTradeEvolutions else { return }
        isResolvingTradeEvolutions = true
        defer { isResolvingTradeEvolutions = false }
        let pending = state.dex.filter { $0.tradeEvolutionPending == true && $0.releasedAt == nil }.map(\.id)
        for id in pending {
            _ = await evolveByTrade(entryID: id, withCord: false)
        }
    }

    /// Spends a Linking Cord to evolve a graduated individual as if it had been traded.
    @discardableResult
    func useLinkingCord(on entryID: String) async -> CordUseResult {
        if isTradeLocked(entryID) { return .listed }
        guard itemCount(.linkingCord) > 0,
              state.dex.contains(where: { $0.id == entryID && $0.releasedAt == nil && $0.profile != nil })
        else { return .unavailable }
        switch await evolveByTrade(entryID: entryID, withCord: true) {
        case .evolved: return .evolved
        case .noEvolution: return .wrongTarget
        case .notReady: return .notReady
        case .unavailable: return .unavailable
        case .everstone: return .everstone
        }
    }

    /// With the cord, the item it holds and the species the player has as friends count; on arrival, the item
    /// it was sent with and the species this side gave for it.
    private func evolveByTrade(entryID: String, withCord: Bool) async -> TradeEvolutionResult {
        func owned(_ entry: DexEntry) -> Bool { entry.id == entryID && entry.releasedAt == nil }
        if holdsEverstone(entryID) { return .everstone }
        guard let baseID = state.dex.first(where: owned)?.baseID else { return .noEvolution }
        guard let line = try? await dexNameLine(baseID: baseID) else { return .unavailable }
        // The store may have changed while the line loaded; read the entry again.
        guard let index = state.dex.firstIndex(where: owned) else { return .noEvolution }
        var entry = state.dex[index]
        let node = line.tree.node(withID: entry.finalID)
        let held = withCord ? heldItem(of: entryID) : entry.tradeHeldItem.flatMap(ItemKind.init(rawValue:))
        let partners: Set<Int> = withCord
            ? Set(state.friendEntryIDs.compactMap { friendEntry(forKey: $0)?.finalID })
            : Set(entry.tradePartnerID.map { [$0] } ?? [])
        let next = node?.tradeEvolution(heldItem: held, partners: partners)
        if withCord, next == nil, node?.evolvesByTrade == true { return .notReady }
        let fromID = entry.finalID
        if let next {
            if !entry.chainOrder.contains(next.speciesID) { entry.chainOrder.append(next.speciesID) }
            entry.finalID = next.speciesID
        }
        var usedItem = false
        if let next, case .holding? = EvolutionRules.rule(for: next.speciesID)?.trade { usedItem = true }
        if let unusedArrival = entry.tradeHeldItem.flatMap(ItemKind.init(rawValue:)), !usedItem {
            state.inventory[unusedArrival.rawValue, default: 0] += 1
        }
        if withCord, usedItem { state.heldItems[entryID] = nil }
        entry.tradeEvolutionPending = nil
        entry.tradeHeldItem = nil
        entry.tradePartnerID = nil
        Self.mergeNames(of: line, into: &entry)
        state.dex[index] = entry
        guard let next else {
            save()
            return .noEvolution
        }
        if withCord { state.inventory[ItemKind.linkingCord.rawValue] = max(0, itemCount(.linkingCord) - 1) }
        state.reconcileRepresentativeSelection()
        announceTradeEvolution(of: entry, from: fromID, to: next.speciesID, line: line)
        save()
        await loadPokemonDetails(speciesID: next.speciesID)
        return .evolved
    }

    private func announceTradeEvolution(of entry: DexEntry, from fromID: Int, to toID: Int, line: EvoLine) {
        func name(_ id: Int) -> String {
            formDisplayName(line.localizedName(id, state.language), speciesID: id, form: entry.form)
        }
        if var arrival = tradeArrival, arrival.entryID == entry.id {
            arrival.receivedName = name(fromID)
            arrival.evolvedID = toID
            arrival.evolvedName = name(toID)
            tradeArrival = arrival
        } else {
            tradeArrivalSeq += 1
            tradeArrival = TradeArrival(id: tradeArrivalSeq, entryID: entry.id, fromName: nil, receivedID: fromID,
                                        receivedName: name(fromID), evolvedID: toID, evolvedName: name(toID),
                                        isShiny: entry.isShiny)
        }
        notifyCompanionEvent(l.notifTradeEvolveTitle, l.notifTradeEvolveBody(name(fromID), name(toID)))
    }
}
