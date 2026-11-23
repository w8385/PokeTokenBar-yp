import Foundation

extension CompanionStore {
    // MARK: Exp. Share


    func holdsExpShare(_ instanceID: String) -> Bool { state.expShareHolders.contains(instanceID) }

    func showsExpShareSlot(for individual: BoxIndividual) -> Bool {
        holdsExpShare(individual.id) || (Self.canHoldExpShare(individual.role) && itemOwnedTotal(.expShare) > 0)
    }

    /// Graduated, friend and stored individuals can hold one; the Pokémon being raised or resting cannot.
    func canAttachExpShare(to instanceID: String) -> Bool {
        guard itemCount(.expShare) > 0, !holdsExpShare(instanceID),
              let individual = boxIndividual(id: instanceID) else { return false }
        return Self.canHoldExpShare(individual.role)
    }

    private static func canHoldExpShare(_ role: BoxIndividual.Role) -> Bool {
        role == .graduated || role == .friend || role == .stored
    }

    @discardableResult
    func attachExpShare(to instanceID: String) -> Bool {
        guard placeBagExpShare(on: instanceID) else { return false }
        state.expShareTakenOff.remove(instanceID)
        save()
        Task { await checkExpShareEvolution() }
        return true
    }

    /// Moves one bag copy onto `instanceID` without saving or starting a check. The caller saves.
    func placeBagExpShare(on instanceID: String) -> Bool {
        guard canAttachExpShare(to: instanceID) else { return false }
        let left = itemCount(.expShare) - 1
        state.inventory[ItemKind.expShare.rawValue] = left > 0 ? left : nil
        state.expShareHolders.append(instanceID)
        return true
    }

    func isExpShareTakenOff(_ instanceID: String?) -> Bool {
        instanceID.map(state.expShareTakenOff.contains) ?? false
    }

    /// A shop or scout egg puts one copy from the bag on the Pokémon it sends to the Box, unless the player took one
    /// off it.
    var eggSwapAttachesExpShare: Bool {
        itemCount(.expShare) > 0 && !isExpShareTakenOff(state.active?.profile?.instanceID)
    }

    /// A shop or scout egg makes the Pokémon it sends to the Box a friend while a slot is free.
    var eggSwapAddsFriend: Bool { state.friendEntryIDs.count < CompanionState.maxFriends }

    /// The Pokémon leaving the raised slot walks with you while a friend slot is free.
    func addFriendIfSlotFree(_ boxID: String) {
        guard eggSwapAddsFriend, let key = state.friendKey(forBoxID: boxID), !state.friendEntryIDs.contains(key) else { return }
        state.friendEntryIDs.append(key)
    }

    /// The player's detach: automatic moves leave this Pokémon alone until the player attaches a copy to it again.
    @discardableResult
    func detachExpShare(from instanceID: String) -> Bool {
        guard returnExpShareToBag(from: instanceID) else { return false }
        state.expShareTakenOff.insert(instanceID)
        save()
        return true
    }

    /// The caller saves.
    func returnExpShareToBag(from instanceID: String) -> Bool {
        guard let index = state.expShareHolders.firstIndex(of: instanceID) else { return false }
        state.expShareHolders.remove(at: index)
        state.inventory[ItemKind.expShare.rawValue, default: 0] += 1
        return true
    }

    /// Every holder as the Box lists it, oldest holder first.
    func expShareHolderIndividuals(in all: [BoxIndividual]? = nil) -> [BoxIndividual] {
        guard !state.expShareHolders.isEmpty else { return [] }
        let all = all ?? boxIndividuals
        return state.expShareHolders.compactMap { id in all.first { $0.id == id } }
    }

    /// Holders whose copy can move onto `target` in one step. Empty when it can't hold one or already does.
    func expShareMoveSources(to target: BoxIndividual, holders: [BoxIndividual]) -> [BoxIndividual] {
        guard Self.canHoldExpShare(target.role), !holdsExpShare(target.id) else { return [] }
        return holders
    }

    func expShareMoveSources(to instanceID: String) -> [BoxIndividual] {
        let all = boxIndividuals
        guard let target = all.first(where: { $0.id == instanceID }) else { return [] }
        return expShareMoveSources(to: target, holders: expShareHolderIndividuals(in: all))
    }

    /// Moves the copy `source` holds onto `target`. What either has banked stays with it.
    @discardableResult
    func moveExpShare(from source: String, to target: String) -> Bool {
        guard expShareMoveSources(to: target).contains(where: { $0.id == source }),
              let index = state.expShareHolders.firstIndex(of: source) else { return false }
        state.expShareHolders.remove(at: index)
        state.expShareHolders.append(target)
        state.expShareTakenOff.remove(target)
        save()
        Task { await checkExpShareEvolution() }
        return true
    }

    /// A graduate holder levels and builds `graduateXP` like the raised graduate; a stored line banks the share in
    /// its stage and takes the steps that open by themselves (`evolveStoredLineIfReady`).
    func creditExpShareHolders(_ share: Int, skipping raisingIDs: Set<String>) {
        guard share > 0 else { return }
        for id in state.expShareHolders where !raisingIDs.contains(id) {
            if let stored = state.storedLines[id] {
                var mon = stored.mon
                mon.usedAtStage = min(SaveTransfer.maxTokenValue, mon.usedAtStage + share)
                state.storedLines[id]?.mon = reconciledProfileGrowth(mon)
                if let line = expShareLines[mon.baseID] { _ = evolveStoredLineIfReady(id: id, in: line) }
            } else if let index = state.dex.firstIndex(where: { $0.id == id && !$0.isReleased }) {
                creditExpShareGraduate(at: index, share)
            }
        }
    }

    private func creditExpShareGraduate(at index: Int, _ share: Int) {
        growGraduate(at: index, by: share)
        let entry = state.dex[index]
        guard let line = expShareLines[entry.baseID] else { return }
        if var progress = state.graduateEvolution[entry.id] {
            progress.graduateXP += share
            state.graduateEvolution[entry.id] = progress
        } else if !graduateOptions(entry, in: line).isEmpty {
            var progress = EvolutionProgress(spentBaseline: state.spentTokens)
            progress.graduateXP = share
            state.graduateEvolution[entry.id] = progress
        }
        _ = evolveGraduateIfReady(id: entry.id, in: line, celebrate: false)
    }

    private var expShareGraduates: [DexEntry] {
        let raisingIDs = Set([state.raisedEntry?.id, state.active?.profile?.instanceID].compactMap { $0 })
        return state.expShareHolders.filter { !raisingIDs.contains($0) && state.storedLines[$0] == nil }
            .compactMap { id in state.dex.first { $0.id == id && !$0.isReleased } }
    }

    private var expShareStoredLines: [(id: String, baseID: Int)] {
        state.expShareHolders.compactMap { id in state.storedLines[id].map { (id, $0.mon.baseID) } }
    }

    /// Stored lines full at their last planned form that hold no copy: a copy passed on before Box graduation
    /// existed left them waiting.
    private var fullStoredLinesWithoutCopy: [(id: String, baseID: Int)] {
        state.storedLines.filter { id, stored in
            !holdsExpShare(id) && stored.mon.stageIndex + 1 >= stored.mon.plannedPathIDs.count
                && stored.mon.usedAtStage >= stageThreshold(for: stored.mon)
        }.map { (id: $0.key, baseID: $0.value.mon.baseID) }.sorted { $0.id < $1.id }
    }

    private var graduatingStoredLines: [(id: String, baseID: Int)] { expShareStoredLines + fullStoredLinesWithoutCopy }

    var hasExpShareWork: Bool {
        !state.expShareHolders.isEmpty || !fullStoredLinesWithoutCopy.isEmpty || (autoMoveOn && itemCount(.expShare) > 0)
    }

    /// Loads each holder's line once, then takes any step that is open now (a clock gate opens on its own).
    func checkExpShareEvolution() async {
        let everstoneLastForms = state.storedLines.filter { id, stored in
            holdsEverstone(id) && stored.mon.stageIndex + 1 >= stored.mon.plannedPathIDs.count
        }.map(\.value.mon.baseID)
        let baseIDs = Set(expShareGraduates.map(\.baseID)).union(graduatingStoredLines.map(\.baseID))
            .union(everstoneLastForms)
        for baseID in baseIDs where expShareLines[baseID] == nil {
            guard loadingExpShareLines.insert(baseID).inserted else { continue }
            defer { loadingExpShareLines.remove(baseID) }
            if let line = try? await dexNameLine(baseID: baseID) { expShareLines[baseID] = line }
        }
        var evolved = false
        for entry in expShareGraduates {
            guard let line = expShareLines[entry.baseID] else { continue }
            if evolveGraduateIfReady(id: entry.id, in: line, celebrate: false) { evolved = true }
        }
        var graduated: [String] = []
        for holder in graduatingStoredLines {
            guard let line = expShareLines[holder.baseID] else { continue }
            if holdsExpShare(holder.id), evolveStoredLineIfReady(id: holder.id, in: line) { evolved = true }
            if isStoredLineGraduating(id: holder.id, in: line),
               let name = graduateStoredLine(id: holder.id, in: line) { graduated.append(l.boxGraduatedLine(name)) }
        }
        let moved = moveIdleExpShares() + giveBagExpSharesToCandidates()
        if evolved || !graduated.isEmpty || !moved.isEmpty { save() }
        guard !graduated.isEmpty || !moved.isEmpty else { return }
        notifyCompanionEvent(graduated.isEmpty ? l.expShareMovedTitle : l.notifGraduateTitle,
                             (graduated + moved).joined(separator: "\n"))
    }

    /// The step a stored line takes in the Box now: the one the raised line would choose, through a path that asks
    /// nothing of the player. Nil while it waits.
    private func storedLineStep(_ stored: StoredLine, in line: EvoLine) -> (node: EvoNode, next: EvoNode, replans: Bool)? {
        let mon = stored.mon
        let threshold = stageThreshold(for: mon)
        guard line.baseID == mon.baseID, mon.usedAtStage >= threshold, mon.dittoDisguise == nil || mon.dittoRevealed,
              !holdsEverstone(mon.profile?.instanceID), let node = line.tree.node(withID: mon.currentID) else { return nil }
        let options = growthOptions(of: node, gender: mon.profile?.gender)
        guard !options.isEmpty else { return nil }
        let step = lineStep(of: mon, at: node, among: options)
        guard EvolutionRules.pathOpenByItself(into: step.next.speciesID, in: storedLineContext(stored)) != nil else {
            return nil
        }
        return (node, step.next, step.replans)
    }

    /// A stored holder at its graduation point, as the raised line would graduate: no growth option left and its stage
    /// XP full. An Everstone doesn't stop it there.
    private func isStoredLineGraduating(id: String, in line: EvoLine) -> Bool {
        guard let mon = state.storedLines[id]?.mon, line.baseID == mon.baseID, !isTradeLocked(id),
              mon.dittoDisguise == nil || mon.dittoRevealed, mon.usedAtStage >= stageThreshold(for: mon),
              let node = line.tree.node(withID: mon.currentID) else { return false }
        return growthOptions(of: node, gender: mon.profile?.gender).isEmpty
    }

    /// Moves a stored line to the graduates under the same id: it keeps its friend slot, held items and Exp. Share.
    /// Returns its name for the notice. The caller saves.
    private func graduateStoredLine(id: String, in line: EvoLine) -> String? {
        guard let stored = state.storedLines.removeValue(forKey: id) else { return nil }
        state.dex.removeAll { $0.id == id && $0.isReleased }
        var record = graduateRecord(of: stored.mon, in: line)
        record.id = id
        state.dex.append(record)
        let storedKey = CompanionState.friendKey(storedLine: id)
        state.friendEntryIDs = state.friendEntryIDs.map { $0 == storedKey ? id : $0 }
        return formDisplayName(line.localizedName(record.finalID, state.language), speciesID: record.finalID,
                               form: record.form)
    }

    /// Takes every step a stored holder can take in the Box. The caller graduates it once it can't go further.
    /// The caller saves.
    private func evolveStoredLineIfReady(id: String, in line: EvoLine) -> Bool {
        var evolved = false
        for _ in 0..<5 {
            guard let stored = state.storedLines[id], let step = storedLineStep(stored, in: line) else { break }
            var mon = stored.mon
            if step.replans {
                mon.plannedPathIDs = replannedPath(from: step.node, to: step.next, base: mon)
                mon.totalForms = mon.plannedPathIDs.count
            }
            spendHeldEvolutionItem(of: id, into: step.next.speciesID)
            completeStoredEvolution(id: id, mon, to: step.next, in: line, spentAtStore: stored.spentAtStore)
            evolved = true
        }
        return evolved
    }

    /// Like `completeEvolution` without the Home celebration; the released Pokédex record follows the new species.
    private func completeStoredEvolution(id: String, _ a: MonState, to next: EvoNode, in line: EvoLine, spentAtStore: Int) {
        var mon = a
        mon.pathIDs = Array(a.pathIDs.prefix(a.stageIndex + 1)) + [next.speciesID]
        mon.stageIndex += 1
        mon.usedAtStage = a.usedAtStage - stageThreshold(for: a)
        mon.evolution = a.evolution.nextForm(spentBaseline: spentAtStore)
        if let details = pokemonDetailsByID[next.speciesID] {
            mon.profile?.enrich(with: details)
        } else if detailProvider != nil {
            Task { await self.loadPokemonDetails(speciesID: next.speciesID) }
        }
        state.storedLines[id]?.mon = mon
        if let index = state.dex.firstIndex(where: { $0.id == id && $0.isReleased }) {
            state.dex[index].chainOrder = Array(mon.pathIDs.prefix(mon.stageIndex + 1))
            state.dex[index].finalID = next.speciesID
            Self.mergeNames(of: line, into: &state.dex[index])
        }
        if let companion = EvolutionRules.companions[next.speciesID] {
            registerCompanion(companion, evolvedFrom: a, in: line)
        }
        let oldName = formDisplayName(line.localizedName(a.currentID, state.language), speciesID: a.currentID, form: a.form)
        let newName = formDisplayName(line.localizedName(next.speciesID, state.language), speciesID: next.speciesID,
                                      form: a.form)
        notifyCompanionEvent(l.notifEvolveTitle, l.notifEvolveBody(from: oldName, to: newName))
    }

    /// Spending while it waits in the Box does not count toward its gate (`resumeStoredLine`).
    func storedLineContext(_ stored: StoredLine) -> EvolutionContext {
        var context = evolutionContext(for: stored.mon)
        context.spentTokens = stored.spentAtStore
        return context
    }

    /// The step a stored line waits on in the Box and what it still lacks, for its Box page. Without a loaded line
    /// (it holds no Exp. Share) the step is its planned one.
    func storedLineGate(id: String) -> (rule: EvolutionRule, context: EvolutionContext)? {
        guard let stored = state.storedLines[id] else { return nil }
        guard holdsExpShare(id), let line = expShareLines[stored.mon.baseID],
              let node = line.tree.node(withID: stored.mon.currentID) else {
            guard let rule = plannedStoredStep(stored.mon), !rule.paths.isEmpty else { return nil }
            return (rule, storedLineContext(stored))
        }
        let mon = stored.mon
        let options = growthOptions(of: node, gender: mon.profile?.gender)
        let traits = evolutionTraits(of: mon)
        let nextIndex = mon.stageIndex + 1
        let planned = mon.plannedPathIDs.indices.contains(nextIndex)
            ? options.first { $0.speciesID == mon.plannedPathIDs[nextIndex] } : nil
        guard let target = planned ?? EvolutionRules.plannable(options, traits: traits).first else { return nil }
        let timed = EvoNode.resolvingTimeOfDay(target, among: options, at: DayPeriod.at(clock()))
        let next = EvolutionRules.resolvingSelector(timed, among: options, traits: traits)
        guard let rule = EvolutionRules.rule(for: next.speciesID), !rule.paths.isEmpty else { return nil }
        return (rule, storedLineContext(stored))
    }

    static func mergeNames(of line: EvoLine, into entry: inout DexEntry) {
        var names = entry.names ?? [:]
        for id in entry.chainOrder {
            if let incoming = line.names[id], !incoming.isEmpty {
                names[id] = (names[id] ?? [:]).merging(incoming) { _, new in new }
            }
        }
        entry.names = names.isEmpty ? nil : names
        entry.namesVersion = entry.chainOrder.allSatisfy { line.names[$0]?.isEmpty == false }
            ? DexEntry.currentNamesVersion : nil
    }

    /// The same individual (id, profile, shininess, held item) becomes the next species; the old one stays in
    /// its chain, so the Pokédex still counts it.
    func evolveGraduate(at index: Int, to speciesID: Int, through path: [EvolutionRequirement], in line: EvoLine,
                        progress: EvolutionProgress, celebrate: Bool) {
        var entry = state.dex[index]
        let fromID = entry.finalID
        let fromForm = entry.form
        if !entry.chainOrder.contains(speciesID) { entry.chainOrder.append(speciesID) }
        entry.finalID = speciesID
        if let form = EvolutionRules.rule(for: speciesID)?.form(through: path, progress: progress) { entry.form = form }
        Self.mergeNames(of: line, into: &entry)
        if let details = pokemonDetailsByID[speciesID] {
            entry.profile?.enrich(with: details)
        } else if detailProvider != nil {
            Task { await self.loadPokemonDetails(speciesID: speciesID) }
        }
        state.dex[index] = entry
        state.collectedFinals.insert("\(entry.baseID):\(speciesID)")
        state.graduateEvolution[entry.id] = progress.nextForm(spentBaseline: state.spentTokens)
        state.reconcileRepresentativeSelection()
        let oldName = formDisplayName(line.localizedName(fromID, state.language), speciesID: fromID, form: fromForm)
        let newName = formDisplayName(line.localizedName(speciesID, state.language), speciesID: speciesID, form: entry.form)
        if celebrate {
            justEvolvedTo = newName
            fireCelebration(.evolve)
            eventUntil = clock().addingTimeInterval(4)
        }
        notifyCompanionEvent(l.notifEvolveTitle, l.notifEvolveBody(from: oldName, to: newName))
    }

    /// The progress record the raised Pokémon's next step reads: the line's, or the evolving graduate's.
    var raisedEvolutionProgress: EvolutionProgress? {
        if hasActive { return state.active!.evolution }
        if let id = raisedGraduate?.id, let saved = state.graduateEvolution[id] { return saved }
        guard evolvingGraduate != nil else { return nil }
        return EvolutionProgress(spentBaseline: state.spentTokens)
    }

    func setRaisedEvolutionProgress(_ progress: EvolutionProgress) {
        if hasActive {
            state.active!.evolution = progress
        } else if let id = raisedGraduate?.id, state.graduateEvolution[id] != nil || evolvingGraduate != nil {
            state.graduateEvolution[id] = progress
        }
    }

    /// A gate may be waiting for what just happened (a pet, a friend, a gesture): run the stage check again.
    func reevaluateEvolution() {
        if raisedGraduate != nil {
            evolveRaisedGraduateIfReady()
            save()
            return
        }
        guard let a = state.active, !isLineParked, currentLine != nil, a.usedAtStage >= stageThreshold(for: a) else {
            save()
            return
        }
        applyUsage(0)
    }

    func recordPet() {
        guard var progress = raisedEvolutionProgress else { return }
        progress.pets += 1
        setRaisedEvolutionProgress(progress)
        reevaluateEvolution()
    }

    func recordFlip() {
        guard var progress = raisedEvolutionProgress, !progress.flipped else { return }
        progress.flipped = true
        setRaisedEvolutionProgress(progress)
        reevaluateEvolution()
    }

    func recordSpin() {
        guard var progress = raisedEvolutionProgress, !progress.spun else { return }
        progress.spun = true
        setRaisedEvolutionProgress(progress)
        reevaluateEvolution()
    }

    func recordTokenRain() {
        guard var progress = raisedEvolutionProgress, !progress.rained else { return }
        progress.rained = true
        setRaisedEvolutionProgress(progress)
        reevaluateEvolution()
    }

    func chooseTower(_ tower: String) {
        guard var progress = raisedEvolutionProgress, progress.tower == nil else { return }
        progress.tower = tower
        setRaisedEvolutionProgress(progress)
        reevaluateEvolution()
    }

    func recordBattle(key: String, result: EvolutionRequirement.Tally) {
        guard var progress = raisedEvolutionProgress else { return }
        progress.record(battle: key, result: result)
        setRaisedEvolutionProgress(progress)
        reevaluateEvolution()
    }

    /// Reads the bot's recent-battle list. Only battles after the cursor count; the first read just sets it.
    func syncBattles(_ battles: [BattleInfo.RecentBattle]) {
        guard var progress = raisedEvolutionProgress else { return }
        guard let cursor = progress.battleCursor else {
            progress.battleCursor = clock()
            setRaisedEvolutionProgress(progress)
            save()
            return
        }
        var newest = cursor
        for battle in battles.sorted(by: { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }) {
            guard let date = battle.date, date > cursor else { continue }
            newest = max(newest, date)
            let key = "\(battle.at ?? "")|\(battle.opponentName ?? "")|\(battle.result)"
            let result: EvolutionRequirement.Tally = battle.isWin ? .won : (battle.result == "loss" ? .lost : .played)
            progress.record(battle: key, result: result)
        }
        progress.battleCursor = newest
        setRaisedEvolutionProgress(progress)
        reevaluateEvolution()
    }

    enum EvolutionGesture: Equatable { case flip, spin }

    /// Gestures the waiting step still asks for; the Home sprite offers them in its context menu.
    var evolutionGestures: [EvolutionGesture] {
        guard let pending = pendingEvolutionGate(), let progress = raisedEvolutionProgress else { return [] }
        let requirements = pending.rule.paths.flatMap { $0 }
        var gestures: [EvolutionGesture] = []
        if requirements.contains(.flipped), !progress.flipped { gestures.append(.flip) }
        if requirements.contains(.spun), !progress.spun { gestures.append(.spin) }
        return gestures
    }

    /// Children growth reaches by itself. Item-only forms (an apple, an armor) are reached by using the item.
    func growthOptions(of node: EvoNode, gender: PokemonGender?) -> [EvoNode] {
        EvolutionRules.growthChildren(node.children(for: gender))
    }

    func evolutionTraits(of mon: MonState) -> EvolutionTraits? {
        mon.profile.map { EvolutionTraits(seed: $0.seed, ivs: $0.ivs, nature: mon.nature) }
    }

    func pickPlannedChild(_ node: EvoNode, baseID: Int, gender: PokemonGender?,
                                  traits: EvolutionTraits?) -> EvoNode {
        let options = EvolutionRules.plannable(growthOptions(of: node, gender: gender), traits: traits)
        let fresh = options.filter { ch in
            ch.finalIDs(for: gender).contains { !state.collectedFinals.contains("\(baseID):\($0)") }
        }
        let pool = fresh.isEmpty ? options : fresh
        return pool[Int(rng.next() % UInt64(pool.count))]
    }

    func makeEvolutionPlan(from root: EvoNode, baseID: Int, gender: PokemonGender?,
                                   traits: EvolutionTraits? = nil) -> [Int] {
        var plan = [root.speciesID]
        var node = root
        while !growthOptions(of: node, gender: gender).isEmpty {
            let next = pickPlannedChild(node, baseID: baseID, gender: gender, traits: traits)
            plan.append(next.speciesID)
            node = next
        }
        return plan
    }

    static func repairedPlan(realizedPath: [Int], stageIndex: Int, fallbackRoute: [Int]) -> [Int] {
        guard !realizedPath.isEmpty else { return fallbackRoute }
        let currentIndex = min(stageIndex, realizedPath.count - 1)
        let prefix = Array(realizedPath.prefix(currentIndex + 1))
        guard fallbackRoute.first == prefix.last else { return prefix }
        return prefix + fallbackRoute.dropFirst()
    }

    /// 루트부터 실제로 이어지는 가장 긴 ID 경로와 마지막 유효 노드. 첫 ID가 루트와 다르면 루트로 복구한다.
    private func longestValidPath(_ ids: [Int], from root: EvoNode,
                                  gender: PokemonGender?) -> (path: [Int], lastNode: EvoNode) {
        var path = [root.speciesID]
        var node = root
        guard ids.first == root.speciesID else { return (path, node) }
        for id in ids.dropFirst() {
            guard let child = node.children(for: gender).first(where: { $0.speciesID == id }) else { break }
            path.append(id)
            node = child
        }
        return (path, node)
    }

    /// 저장된 실제 경로와 계획을 현재 에셋 트리에 맞춘다. 완전한 계획만 재사용해 재시작 시 RNG를 소비하지 않는다.
    func normalizedEvolutionState(_ saved: MonState, from root: EvoNode) -> MonState {
        var normalized = saved
        let gender = saved.profile?.gender
        // Evolutions already taken stay, whatever the gender rules say now.
        let realized = longestValidPath(saved.pathIDs, from: root, gender: nil)
        let candidate = longestValidPath(saved.plannedPathIDs, from: root, gender: gender)
        let aheadIsItemOnly = candidate.path.dropFirst(realized.path.count).contains {
            EvolutionRules.rule(for: $0)?.isItemOnly == true
        }
        let canReusePlan = candidate.path == saved.plannedPathIDs
            && candidate.path.starts(with: realized.path)
            && growthOptions(of: candidate.lastNode, gender: gender).isEmpty
            && !aheadIsItemOnly
        let plan: [Int]
        if canReusePlan {
            plan = candidate.path
        } else {
            let suffix = makeEvolutionPlan(from: realized.lastNode, baseID: saved.baseID, gender: gender,
                                           traits: evolutionTraits(of: saved))
            plan = realized.path + suffix.dropFirst()
        }
        normalized.pathIDs = realized.path
        normalized.plannedPathIDs = plan
        normalized.stageIndex = realized.path.count - 1
        normalized.totalForms = plan.count
        return normalized
    }

    /// Returns the new dex entry's id.
    @discardableResult
    func graduate() -> String? {
        guard let a = state.active else { return nil }
        let record = graduateRecord(of: a, in: currentLine)
        let finalID = record.finalID
        let entryID = record.id
        state.dex.append(record)
        let name = formDisplayName(currentLine?.localizedName(finalID, state.language) ?? "",
                                   speciesID: finalID, form: a.form)
        justGraduated = name
        notifyCompanionEvent(l.notifGraduateTitle, l.notifGraduateBody(name))
        eventUntil = clock().addingTimeInterval(6)
        state.active = nil
        cheerSeq += 1
        state.reconcileRepresentativeSelection()   // 졸업 체인이 dex 로 옮겨져 선택은 정상적으로 유지된다
        activeGeneration += 1
        currentLine = nil
        state.eggUsage = 0   // 새 알은 처음부터 인큐베이션
        state.resetEggPrayers()
        isHatchRetryDelayed = false
        // eggTier 는 손대지 않는다 — 여기 도달했다는 건 활성 포켓몬이 있었다는 뜻이라 보증은 이미 nil 이다
        // (부화가 소비, 디스크/불러오기는 sanitized 가 정규화). 소비 지점은 hatchCore 한 곳으로 유지한다.
        // "알을 받는 순간" 즉시 프리패칭 시작 — 다음 부화의 종·라인·스프라이트 예열.
        Task { await self.ensureEggPrefetch() }
        return entryID
    }

    /// The graduate `a` becomes, wherever it graduates. Records its final in `collectedFinals`; the caller adds it.
    private func graduateRecord(of mon: MonState, in line: EvoLine?) -> DexEntry {
        var a = mon
        a.profile?.advanceGrowth(to: PokemonBalance.graduationTotal(a.rarity), rarity: a.rarity)
        if let details = pokemonDetailsByID[a.currentID] { a.profile?.enrich(with: details) }
        state.collectedFinals.insert("\(a.baseID):\(a.currentID)")
        return DexEntry(id: a.profile?.instanceID ?? UUID().uuidString,
                        baseID: a.baseID, finalID: a.currentID,
                        chainOrder: a.pathIDs, rarity: a.rarity, caughtAt: clock(),
                        isShiny: a.isShiny, nature: a.nature,
                        profile: a.profile,
                        names: line.map { line in
                            Dictionary(uniqueKeysWithValues: a.pathIDs.compactMap { id in line.names[id].map { (id, $0) } })
                        }, form: a.form, prayers: a.prayers)
    }
}
