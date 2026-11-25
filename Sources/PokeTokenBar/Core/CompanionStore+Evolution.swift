import Foundation

extension CompanionStore {
    // MARK: 특이 진화 조건

    func registerCompanion(_ species: Int, evolvedFrom a: MonState, in line: EvoLine) {
        let id = UUID().uuidString
        var profile = PokemonProfile.generate(
            seed: PokemonProfileMigration.seed("companion:\(id):\(species)"),
            growthTokens: PokemonBalance.graduationTotal(a.rarity), instanceID: id)
        profile.applyGrowth(0, rarity: a.rarity)
        if let details = pokemonDetailsByID[species] { profile.enrich(with: details) }
        let chain = Array(a.pathIDs.prefix(a.stageIndex + 1)) + [species]
        state.collectedFinals.insert("\(a.baseID):\(species)")
        state.dex.append(DexEntry(id: id, baseID: a.baseID, finalID: species, chainOrder: chain, rarity: a.rarity,
                                  caughtAt: clock(), nature: a.nature, profile: profile,
                                  names: Dictionary(uniqueKeysWithValues: chain.compactMap { sid in
                                      line.names[sid].map { (sid, $0) }
                                  })))
    }

    /// Everything the evolution rules read about `mon` right now.
    func evolutionContext(for mon: MonState, thresholdOverride: Int? = nil) -> EvolutionContext {
        evolutionContext(progress: mon.evolution, speciesID: mon.currentID, profile: mon.profile,
                         stageXP: mon.usedAtStage, stageThreshold: thresholdOverride ?? stageThreshold(for: mon))
    }

    func evolutionContext(progress: EvolutionProgress, speciesID: Int, profile: PokemonProfile?,
                                  stageXP: Int, stageThreshold: Int) -> EvolutionContext {
        var context = EvolutionContext()
        context.progress = progress
        context.period = DayPeriod.at(clock())
        context.level = profile?.level ?? 5
        if let details = pokemonDetailsByID[speciesID] {
            context.knownMoves = Set(details.levelUpMoves(through: context.level).map(\.name))
            context.learnableMoves = Set(details.moves.filter { move in
                move.learnMethods.contains { $0.method == "level-up" }
            }.map(\.name))
        }
        context.knownMoves.formUnion(profile?.moves.map(\.name) ?? [])
        if let id = profile?.instanceID { context.heldItem = heldItem(of: id) }
        for (kind, count) in ownedItems { context.bag[kind] = count }
        for key in state.friendEntryIDs {
            guard let entry = friendEntry(forKey: key), entry.id != profile?.instanceID else { continue }
            context.friendCount += 1
            context.friendLines.formUnion(entry.chainOrder)
            context.friendLines.insert(entry.finalID)
            context.friendTypes.formUnion(types(speciesID: entry.finalID, form: entry.form, gender: entry.profile?.gender))
        }
        context.spentTokens = state.spentTokens
        context.stageXP = stageXP
        context.stageThreshold = stageThreshold
        return context
    }

    func types(speciesID: Int, form: PokemonForm?, gender: PokemonGender?) -> [String] {
        FormBattleData.of(speciesID: speciesID, form: form, gender: gender)?.types ?? speciesTypes(speciesID)
    }

    private func speciesTypes(_ id: Int) -> [String] {
        speciesIndex?.entry(id)?.types ?? pokemonDetailsByID[id]?.types ?? []
    }

    /// The bag items a satisfied path used up, and the held item the new form names.
    func spendEvolutionRequirements(of path: [EvolutionRequirement], into speciesID: Int, instanceID: String?) {
        for case .bag(let kind) in path {
            state.inventory[kind.rawValue] = max(0, itemCount(kind) - 1)
        }
        spendHeldEvolutionItem(of: instanceID, into: speciesID)
    }

    func spendHeldEvolutionItem(of instanceID: String?, into speciesID: Int) {
        guard let instanceID, let held = heldItem(of: instanceID),
              EvolutionRules.rule(for: speciesID)?.heldItemsUsed.contains(held) == true else { return }
        state.heldItems[instanceID] = nil
    }

    /// The form the raised Pokémon is waiting to take and what it still lacks; nil when nothing special waits.
    func pendingEvolutionGate() -> (rule: EvolutionRule, context: EvolutionContext)? {
        if raisedGraduate != nil { return raisedGraduateGate() }
        guard let a = state.active, let node = currentLine?.tree.node(withID: a.currentID) else { return nil }
        let gender = a.profile?.gender
        let options = growthOptions(of: node, gender: gender)
        let traits = evolutionTraits(of: a)
        let nextIndex = a.stageIndex + 1
        let planned = a.plannedPathIDs.indices.contains(nextIndex)
            ? options.first { $0.speciesID == a.plannedPathIDs[nextIndex] } : nil
        guard let target = planned ?? EvolutionRules.plannable(options, traits: traits).first else { return nil }
        let timed = EvoNode.resolvingTimeOfDay(target, among: options, at: DayPeriod.at(clock()))
        let next = EvolutionRules.resolvingSelector(timed, among: options, traits: traits)
        guard let rule = EvolutionRules.rule(for: next.speciesID), !rule.paths.isEmpty else { return nil }
        return (rule, evolutionContext(for: a))
    }

    // MARK: Moving on from a stuck Pokémon (`CompanionStore+MoveOn`)

    func setAttended(_ attended: Bool) {
        guard attended != isAttended else { return }
        isAttended = attended
        guard state.stuckWatch != nil else { return }
        state.stuckWatch?.since = clock()
        save()
    }

    /// Called from the evolution tick. Starts, resets or clears the watch, and moves on once it has run out unseen.
    func checkStuckMoveOn() {
        guard !isHatching, !isRevealingDitto, !isStuckUnknown else { return }
        let stuck = stuckRaised
        if let stuck, let mark = state.keepWaiting[stuck.id], mark != stuck.speciesID {
            state.keepWaiting[stuck.id] = nil
        }
        guard autoMoveOn, let stuck, !isKeptWaiting(stuck.id, species: stuck.speciesID) else {
            if state.stuckWatch != nil {
                state.stuckWatch = nil
                save()
            }
            return
        }
        guard let watch = state.stuckWatch, watch.id == stuck.id else {
            state.stuckWatch = StuckWatch(id: stuck.id, since: clock())
            save()
            return
        }
        guard !isAttended, clock().timeIntervalSince(watch.since) >= Self.stuckMoveOnDelay else { return }
        moveOn(stuck)
    }

    func keepWaitingOnStuck() {
        guard let stuck = stuckRaised else { return }
        state.keepWaiting[stuck.id] = stuck.speciesID
        state.stuckWatch = nil
        save()
    }

    private func moveOn(_ stuck: StuckRaised) {
        state.stuckWatch = nil
        let next: MoveOnNext
        var raised: (id: String, name: String)?
        if stuck.isGraduate {
            let parkedName = parkedLineName ?? l.parkedEggName
            state.resumeParkedLine(now: clock())
            addFriendIfSlotFree(stuck.id)
            let pick = raiseCandidate(excluding: stuck.id)
            let name = pick.map { candidateName($0.id) }
            if let pick, let name, raise(entryID: pick.id) {
                next = .raise(name)
                raised = (pick.id, name)
            } else {
                settleRaisedChange()
                next = .resume(parkedName)
            }
        } else if let pick = raiseCandidate(excluding: stuck.id) {
            let name = candidateName(pick.id)
            if state.storedLines[pick.id] != nil {
                raise(entryID: pick.id)
                if state.storedLines[stuck.id] != nil { addFriendIfSlotFree(stuck.id) }
            } else {
                storeActiveForNewEgg(tier: nil, pendingHatchID: nil, attachesBagCopy: false)
                raise(entryID: pick.id)
            }
            next = .raise(name)
            raised = (pick.id, name)
        } else {
            storeActiveForNewEgg(tier: nil, pendingHatchID: nil, attachesBagCopy: false)
            next = .egg
        }
        let given = passExpShare(offRaised: raised) + giveBagExpSharesToCandidates()
        save()
        AppLog.write("move on: \(stuck.speciesID) stuck, next \(next)")
        notifyCompanionEvent(l.moveOnTitle,
                             ([l.moveOnBody(stuck.name, requirementsText(stuck.needs), next, toGraduates: stuck.isGraduate)]
                              + given).joined(separator: "\n"))
    }

    // MARK: Skipping a blocked evolution

    /// The active Pokémon is ready but held back by something other than the clock, so it may graduate as it is.
    var canSkipEvolution: Bool {
        guard let a = state.active, hasActive, currentLine != nil, a.dittoDisguise == nil || a.dittoRevealed,
              !holdsEverstone(a.profile?.instanceID), a.usedAtStage >= stageThreshold(for: a),
              let pending = pendingEvolutionGate(), case .conditions = pending.rule.block(in: pending.context)
        else { return false }
        return true
    }

    /// Graduates the active Pokémon in its current form. Its progress toward the blocked step goes with it, so
    /// raising it again later can still evolve it.
    @discardableResult
    func skipEvolutionAndGraduate() -> Bool {
        guard canSkipEvolution, let a = state.active else { return false }
        var progress = a.evolution
        progress.stuckNotified = nil
        progress.graduateXP = max(0, a.usedAtStage - stageThreshold(for: a))
        guard let entryID = graduate() else { return false }
        state.graduateEvolution[entryID] = progress
        save()
        return true
    }

    // MARK: Evolving a raised graduate


    /// The forms the graduate's current form can grow into, resolved for the clock and its traits now.
    func graduateOptions(_ entry: DexEntry, in line: EvoLine) -> [EvoNode] {
        guard let node = line.tree.node(withID: entry.finalID) else { return [] }
        let options = growthOptions(of: node, gender: entry.profile?.gender)
        let traits = entry.profile.map { EvolutionTraits(seed: $0.seed, ivs: $0.ivs, nature: entry.nature) }
        return EvolutionRules.plannable(options, traits: traits).map { option in
            let timed = EvoNode.resolvingTimeOfDay(option, among: options, at: DayPeriod.at(clock()))
            return EvolutionRules.resolvingSelector(timed, among: options, traits: traits)
        }
    }

    /// A graduate has finished growing, so it counts as having reached its stage threshold; `graduateXP` is what
    /// it has past that. Only the `longStage` requirement reads the two.
    func graduateContext(_ entry: DexEntry) -> EvolutionContext {
        let progress = state.graduateEvolution[entry.id] ?? EvolutionProgress(spentBaseline: state.spentTokens)
        let forms = max(1, entry.chainOrder.count)
        let threshold = PokemonBalance.phaseThreshold(rarity: entry.rarity, totalForms: forms + 1, stageIndex: forms - 1)
        return evolutionContext(progress: progress, speciesID: entry.finalID, profile: entry.profile,
                                stageXP: threshold + progress.graduateXP, stageThreshold: threshold)
    }

    /// The raised graduate, when its line is loaded and its form can still evolve.
    var evolvingGraduate: (entry: DexEntry, line: EvoLine)? {
        guard let entry = raisedGraduate, let line = raisedGraduateLine, line.baseID == entry.baseID,
              !graduateOptions(entry, in: line).isEmpty else { return nil }
        return (entry, line)
    }

    func raisedGraduateGate() -> (rule: EvolutionRule, context: EvolutionContext)? {
        guard let graduate = evolvingGraduate else { return nil }
        for option in graduateOptions(graduate.entry, in: graduate.line) {
            if let rule = EvolutionRules.rule(for: option.speciesID), !rule.paths.isEmpty {
                return (rule, graduateContext(graduate.entry))
            }
        }
        return nil
    }

    /// Loads the raised graduate's line once, then evolves it if a step is open. Called on raise and from the tick.
    func checkRaisedGraduateEvolution() async {
        guard let entry = raisedGraduate, !isLoadingGraduateLine else { return }
        if raisedGraduateLine?.baseID != entry.baseID {
            isLoadingGraduateLine = true
            defer { isLoadingGraduateLine = false }
            guard let line = try? await dexNameLine(baseID: entry.baseID) else { return }
            raisedGraduateLine = line
        }
        if evolveRaisedGraduateIfReady() { save() }
    }

    /// Takes every step whose conditions hold now. The caller saves. Returns whether it evolved.
    @discardableResult
    func evolveRaisedGraduateIfReady() -> Bool {
        guard let id = raisedGraduate?.id, let line = raisedGraduateLine else { return false }
        return evolveGraduateIfReady(id: id, in: line, celebrate: true)
    }

    /// A Box holder evolving only notifies; the celebration on the home screen belongs to the raised Pokémon.
    func evolveGraduateIfReady(id: String, in line: EvoLine, celebrate: Bool) -> Bool {
        var evolved = false
        for _ in 0..<5 {
            guard let index = state.dex.firstIndex(where: { $0.id == id && !$0.isReleased }),
                  line.baseID == state.dex[index].baseID else { break }
            let entry = state.dex[index]
            let options = graduateOptions(entry, in: line)
            if options.isEmpty {
                state.graduateEvolution[entry.id] = nil
                break
            }
            if holdsEverstone(entry.id) { break }
            let context = graduateContext(entry)
            let step = options.lazy.compactMap { option in
                EvolutionRules.openPath(into: option.speciesID, in: context).map { (speciesID: option.speciesID, path: $0) }
            }.first
            guard let step else { break }
            spendEvolutionRequirements(of: step.path, into: step.speciesID, instanceID: entry.id)
            evolveGraduate(at: index, to: step.speciesID, through: step.path, in: line, progress: context.progress,
                           celebrate: celebrate)
            evolved = true
        }
        return evolved
    }
}
