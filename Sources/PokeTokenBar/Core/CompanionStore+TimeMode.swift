import Foundation

extension CompanionStore {
    // MARK: Time mode

    var growthMode: GrowthMode { state.growthMode }

    func setGrowthMode(_ mode: GrowthMode) {
        guard mode != state.growthMode else { return }
        state.growthMode = mode
        if mode == .token {
            state.tokenModeSince = clock()
            rebaseUsageOnNextUpdate = true
        }
        timeMeter.reanchor()
        timeActiveNow = false
        save()
    }

    /// The monitor reports sleep, screen sleep or lock: the next tick only re-anchors.
    func noteActivityBreak() {
        timeMeter.reanchor()
        timeActiveNow = false
        flushTimeSave()
    }

    /// Writes time-mode credit that is still only in memory.
    func flushTimeSave() {
        guard timeSavePending else { return }
        save()
    }

    /// One tick of time mode. `uptime` is monotonic and excludes sleep; `idle` is seconds since the last input.
    /// Credits active seconds as virtual tokens to growth and the wallet alike, and writes the save at most every
    /// `timeSaveInterval`. Returns the growth tokens credited.
    @discardableResult
    func creditActiveTime(uptime: TimeInterval, idle: TimeInterval, present: Bool) -> Int {
        if tokenModeSinceUnsaved {
            tokenModeSinceUnsaved = false
            save()
        }
        guard state.growthMode == .time else {
            timeMeter.reanchor()
            return 0
        }
        let seconds = timeMeter.step(uptime: uptime, idle: idle, present: present)
        timeActiveNow = present && idle <= PokemonBalance.timeIdleLimit
        let tokens = PokemonBalance.timeTokens(forActiveSeconds: seconds)
        guard tokens > 0 else {
            refreshTimeDisplayState()
            return 0
        }
        state.timeCredit += tokens
        state.installBaselineSet = true
        let milestone = growthMilestone
        deferTimeSaves = true
        creditUsage(tokens)
        deferTimeSaves = false
        let saveDue = lastTimeSaveUptime.map { uptime - $0 >= PokemonBalance.timeSaveInterval } ?? true
        if saveDue || growthMilestone != milestone {
            lastTimeSaveUptime = uptime
            save()
        } else {
            timeSavePending = true
        }
        if state.active == nil, state.raisedEntry == nil, !isHatching {
            if state.eggUsage >= eggHatchThreshold {
                Task { await hatchIfNeeded() }
            } else if saveDue {
                Task { await ensureEggPrefetch() }
            }
        }
        refreshTimeDisplayState()
        return tokens
    }

    /// Changes here are written at once, not at the next throttled time-mode save.
    private var growthMilestone: [String] {
        [state.active.map { "\($0.currentID)/\($0.stageIndex)" } ?? "egg", "\(state.dex.count)",
         state.raisedEntryID ?? "", "\(state.raisedEntry?.finalID ?? 0)"]
            + state.storedLines.map { "\($0.key):\($0.value.mon.currentID)" }.sorted()
            + state.dex.filter { state.expShareHolders.contains($0.id) }.map { "\($0.id):\($0.finalID)" }.sorted()
    }

    @discardableResult
    func expireEventWindow() -> Bool {
        guard let until = eventUntil, clock() > until else { return false }
        justGraduated = nil; justEvolvedTo = nil; eventUntil = nil
        return true
    }

    private func refreshTimeDisplayState() {
        guard state.active != nil else { return }
        let next: CompanionStateKind = timeActiveNow ? .working : .sleep
        if expireEventWindow(), displayState == .levelUp { displayState = next }
        switch displayState {
        case .egg, .idle, .sulk: displayState = next
        case .working, .sleep: if displayState != next { displayState = next }
        default: break
        }
    }

    /// Token mode with no real usage for `idleTokenHintAfter`: offer time mode once.
    var showsIdleTokenHint: Bool {
        guard state.growthMode == .token, !state.idleHintDismissed else { return false }
        let since = [state.lastUsageAt, state.tokenModeSince].compactMap { $0 }.max() ?? clock()
        return clock().timeIntervalSince(since) >= PokemonBalance.idleTokenHintAfter
    }

    func dismissIdleTokenHint() {
        state.idleHintDismissed = true
        save()
    }

    /// A gate that waits on the clock (day/night) opens without any new usage. Called from every usage update and
    /// from the app's 30-second tick; at most one check per 20 seconds.
    func checkEvolutionGate() {
        checkStuckMoveOn()
        if hasExpShareWork, clock() >= nextExpShareCheck {
            nextExpShareCheck = clock().addingTimeInterval(20)
            Task { await checkExpShareEvolution() }
        }
        if raisedGraduate != nil {
            guard clock() >= nextEvolutionGateCheck else { return }
            nextEvolutionGateCheck = clock().addingTimeInterval(20)
            Task { await checkRaisedGraduateEvolution() }
            return
        }
        guard let a = state.active, !isLineParked, currentLine != nil, a.dittoDisguise == nil || a.dittoRevealed,
              a.usedAtStage >= stageThreshold(for: a), clock() >= nextEvolutionGateCheck else { return }
        nextEvolutionGateCheck = clock().addingTimeInterval(20)
        applyUsage(0)
    }

    /// The period now and the seconds left in it, on the app's clock.
    func dayPeriodNow() -> (period: DayPeriod, secondsLeft: TimeInterval, degrees: Double) {
        let now = clock()
        return (DayPeriod.at(now), DayPeriod.secondsUntilSwitch(from: now), DayPeriod.cycleDegrees(from: now))
    }

    /// Usage goes to exactly one place: the raised graduate, else the line in `active`, else the egg.
    /// A parked line or egg gets nothing.
    func creditUsage(_ delta: Int) {
        let raisedID = state.raisedEntry?.id
        let raisingIDs = Set([raisedID, state.active?.profile?.instanceID].compactMap { $0 })
        if raisedID != nil {
            creditRaisedGraduate(delta)
        } else if state.active != nil {
            applyUsage(delta)
        } else {
            state.eggUsage += delta
        }
        creditExpShareHolders(delta / ExpShare.shareDivisor, skipping: raisingIDs)
    }

    /// A graduate grows by level only, on the same curve as the line.
    func growGraduate(at index: Int, by delta: Int) {
        guard var profile = state.dex[index].profile else { return }
        profile.applyGrowth(delta, rarity: state.dex[index].rarity)
        if let details = pokemonDetailsByID[state.dex[index].finalID] { profile.enrich(with: details) }
        state.dex[index].profile = profile
    }

    func creditRaisedGraduate(_ delta: Int) {
        guard delta > 0, let index = state.dex.firstIndex(where: { $0.id == state.raisedEntryID }),
              state.dex[index].profile != nil else { return }
        growGraduate(at: index, by: delta)
        if var progress = raisedEvolutionProgress {
            progress.graduateXP += delta
            setRaisedEvolutionProgress(progress)
            evolveRaisedGraduateIfReady()
        }
    }

    /// 토큰 증분을 현재 포켓몬에 적용 — 임계 도달 시 진화/졸업.
    /// 라인 미로딩(재시작 직후·오프라인)이어도 사용량은 항상 적립한다 — 여기서 드롭하면
    /// 프로바이더별 ledger 는 이미 전진해 델타가 영구 유실된다. 진화 판정만 라인 로드 후로 미룬다.
    /// Returns the XP past the last stage when the line graduates; the line itself keeps none of it.
    @discardableResult
    func applyUsage(_ delta: Int) -> Int {
        guard state.active != nil, !isLineParked else { return 0 }
        state.active!.usedAtStage += delta
        reconcileActiveProfileGrowth()
        guard let line = currentLine else { save(); return 0 }
        var graduationOverflow = 0
        var guardCount = 0
        while state.active != nil, guardCount < 50 {
            guardCount += 1
            let a = state.active!
            let thr = stageThreshold(for: a)
            guard a.usedAtStage >= thr else { break }
            guard let node = line.tree.node(withID: a.currentID) else { break }
            // 위장체는 부화 때는 다형태지만, 에셋 정규화/마이그레이션 뒤 leaf가 될 수 있다.
            // 따라서 terminal 졸업보다 먼저 리빌해야 위장 종이 도감으로 잘못 졸업하지 않는다.
            if a.dittoDisguise != nil, !a.dittoRevealed {
                if !isRevealingDitto { Task { await revealDitto() } }
                break
            }
            let gender = a.profile?.gender
            let options = growthOptions(of: node, gender: gender)
            if options.isEmpty {
                graduationOverflow = a.usedAtStage - thr
                graduate(); break
            } else if holdsEverstone(a.profile?.instanceID) {
                break
            } else {
                let step = lineStep(of: a, at: node, among: options)
                let next = step.next
                let context = evolutionContext(for: a, thresholdOverride: thr)
                let openPath = EvolutionRules.openPath(into: next.speciesID, in: context)
                // A closed gate keeps the stage open: the XP keeps adding up and carries over once it opens.
                guard let openPath else {
                    notifyEvolutionStuckIfNeeded(of: a, into: next, in: line, context: context)
                    break
                }
                if step.replans {
                    replanEvolution(from: node, to: next, base: a)
                    AppLog.write("evolve: replanned path for base \(a.baseID)")
                }
                spendEvolutionRequirements(of: openPath, into: next.speciesID, instanceID: a.profile?.instanceID)
                completeEvolution(of: a, to: next, through: openPath, in: line,
                                  usedAtStage: a.usedAtStage - thr)   // 초과분 이월
            }
        }
        reconcileActiveProfileGrowth()
        save()
        return graduationOverflow
    }

    /// Tells the player once per blocking reason that the form is ready but a condition is unmet. Time is one
    /// reason however many times the period flips, so a day/night wait is not announced every ten minutes.
    private func notifyEvolutionStuckIfNeeded(of a: MonState, into next: EvoNode, in line: EvoLine, context: EvolutionContext) {
        guard let rule = EvolutionRules.rule(for: next.speciesID) else { return }
        let block = rule.block(in: context)
        let blocking: [EvolutionRequirement]
        switch block {
        case .open: return
        case .clock: blocking = []
        case .conditions(let conditions): blocking = conditions
        }
        let key = ([String(next.speciesID)] + blocking.map { String(describing: $0) }).joined(separator: "|")
        guard a.evolution.stuckNotified != key else { return }
        state.active!.evolution.stuckNotified = key
        let name = formDisplayName(line.localizedName(a.currentID, state.language),
                                   speciesID: a.currentID, form: a.form)
        if case .clock(let period) = block {
            let what = l.notifEvolveStuckWaitsFor(period, minutes: Self.minutes(DayPeriod.secondsUntilSwitch(from: clock())))
            notifyCompanionEvent(l.notifEvolveStuckTitle, l.notifEvolveStuckBody(name, what))
            return
        }
        let what = blocking.map {
            l.evolutionRequirementText($0, speciesName: { speciesIndex?.entry($0)?.names[language.rawValue] ?? "#\($0)" })
        }.joined(separator: " + ")
        notifyCompanionEvent(l.notifEvolveStuckTitle, l.notifEvolveStuckSkippableBody(name, what))
    }

    static func minutes(_ seconds: TimeInterval) -> Int { max(1, Int((seconds / 60).rounded(.up))) }

    /// The form a line moves into next: its planned child (else a fresh pick), resolved for the clock and its traits.
    /// `replans` when that is not the plan. The raised line and a stored holder both choose here.
    func lineStep(of a: MonState, at node: EvoNode, among options: [EvoNode]) -> (next: EvoNode, replans: Bool) {
        let nextIndex = a.stageIndex + 1
        let traits = evolutionTraits(of: a)
        let planned = a.plannedPathIDs.indices.contains(nextIndex)
            ? options.first(where: { $0.speciesID == a.plannedPathIDs[nextIndex] }) : nil
        let picked = planned ?? pickPlannedChild(node, baseID: a.baseID, gender: a.profile?.gender, traits: traits)
        let timed = EvoNode.resolvingTimeOfDay(picked, among: options, at: DayPeriod.at(clock()))
        let next = EvolutionRules.resolvingSelector(timed, among: options, traits: traits)
        return (next, planned == nil || next.speciesID != picked.speciesID)
    }

    func replanEvolution(from node: EvoNode, to next: EvoNode, base a: MonState) {
        let plan = replannedPath(from: node, to: next, base: a)
        state.active!.plannedPathIDs = plan
        state.active!.totalForms = plan.count
    }

    /// 실제로 간 갈래가 계획과 다르면 계획을 그 갈래 아래로 다시 세운다.
    func replannedPath(from node: EvoNode, to next: EvoNode, base a: MonState) -> [Int] {
        let fallbackRoute = [node.speciesID]
            + makeEvolutionPlan(from: next, baseID: a.baseID, gender: a.profile?.gender, traits: evolutionTraits(of: a))
        return Self.repairedPlan(realizedPath: a.pathIDs, stageIndex: a.stageIndex, fallbackRoute: fallbackRoute)
    }

    /// 다음 형태로 넘어가는 공통 처리 — 경로·단계·프로필·연출·알림. 저장은 호출부가 한다.
    func completeEvolution(of a: MonState, to next: EvoNode, through path: [EvolutionRequirement], in line: EvoLine,
                           usedAtStage: Int) {
        let form = EvolutionRules.rule(for: next.speciesID)?.form(through: path, progress: a.evolution) ?? a.form
        state.active!.pathIDs = Array(a.pathIDs.prefix(a.stageIndex + 1)) + [next.speciesID]
        state.active!.stageIndex += 1
        state.active!.usedAtStage = usedAtStage
        state.active!.form = form
        state.active!.evolution = a.evolution.nextForm(spentBaseline: state.spentTokens)
        if let details = pokemonDetailsByID[next.speciesID] {
            state.active!.profile?.enrich(with: details)
        } else if detailProvider != nil {
            Task { await self.loadPokemonDetails(speciesID: next.speciesID) }
        }
        let oldName = formDisplayName(line.localizedName(a.currentID, state.language),
                                      speciesID: a.currentID, form: a.form)
        let newName = formDisplayName(line.localizedName(next.speciesID, state.language),
                                      speciesID: next.speciesID, form: form)
        if let companion = EvolutionRules.companions[next.speciesID] {
            registerCompanion(companion, evolvedFrom: a, in: line)
        }
        justEvolvedTo = newName
        fireCelebration(.evolve)
        // 짧은 levelUp 창 — 진화 순간 "…(으)로 진화했어요" 문구 노출(hatch/graduate 와 동일 패턴).
        // 이게 없으면 computeState 가 .levelUp 을 안 내 statusEvolved 가 도달 불가(dead code)였다.
        eventUntil = clock().addingTimeInterval(4)
        notifyCompanionEvent(l.notifEvolveTitle, l.notifEvolveBody(from: oldName, to: newName))
    }
}
