import Foundation

extension CompanionStore {
    // MARK: 부화

    func hatchIfNeeded() async {
        guard state.active == nil, state.raisedEntry == nil, !isHatching, state.eggUsage >= eggHatchThreshold else { return }
        // 프리패치가 "종 롤 중"(pending 미확정)일 때만 대기 — 이중 rng 소비 방지.
        // pending 확정 후의 예열(라인/스프라이트)과는 동시 진행해도 안전하다.
        guard state.pendingHatchID != nil || !prefetchInFlight else { return }
        // isHatching 을 롤~부화 전체에 defer 로 잠근다. 과거엔 chooseBase 후 isHatching 을 잠깐
        // 내렸다가(hatch 자체 가드 통과용) hatch 를 호출해, 그 await 창에서 다른 update 틱이
        // 두 번째 종을 롤하는 경합이 있었다. hatchCore 는 isHatching 을 재검사하지 않으므로
        // 여기서 소유한 락 하나로 롤·부화가 원자적으로 보호된다.
        let generation = activeGeneration
        isHatching = true
        defer { isHatching = false }
        // 프리패칭된 종이 있으면 그대로 사용(라인·스프라이트 예열됨 → 딜레이 ~0), 없으면 지금 롤.
        let base: Int?
        if let pending = state.pendingHatchID {
            base = pending
        } else {
            base = await chooseBase()
        }
        guard isCurrentReadyEgg(generation: generation) else {
            AppLog.write("hatch: discarded before result handling — subject replaced during species roll")
            kickLineLoadIfNeeded()
            return
        }
        guard let base else {
            isHatchRetryDelayed = true
            return
        }
        let pendingForm = state.pendingHatchID == base ? state.pendingForm : nil
        await hatchCore(baseID: base, generation: generation, form: pendingForm)
    }

    /// 부화가 폐기된 뒤 남은 개체(대개 방금 불러온 개체)의 진화 라인을 다시 로드한다.
    /// `loadCurrentLine` 은 `!isHatching` 을 요구하므로 부화 중에 걸린 로드는 조용히 실패한다 —
    /// 아무도 재시도하지 않으면 다음 update 틱(기본 120초)까지 이름이 "Token Egg" 로 남는다.
    /// Task 본문은 현재 동기 실행(= defer 로 isHatching 해제)이 끝난 뒤 돌므로 락이 이미 풀려 있다.
    func kickLineLoadIfNeeded() {
        guard state.active != nil, currentLine == nil else { return }
        Task { await loadCurrentLine() }
    }

    // MARK: 알 프리패칭


    private func isCurrentEgg(generation: Int) -> Bool {
        activeGeneration == generation && state.active == nil && state.raisedEntry == nil
    }

    private func isCurrentReadyEgg(generation: Int) -> Bool {
        isCurrentEgg(generation: generation) && state.eggUsage >= eggHatchThreshold
    }

    private func markHatchRetryDelayedIfReady(generation: Int) {
        guard isCurrentReadyEgg(generation: generation) else { return }
        isHatchRetryDelayed = true
    }

    private func finishEggPrefetch(generation: Int, shouldHatch: Bool) {
        prefetchInFlight = false
        guard shouldHatch, isCurrentReadyEgg(generation: generation) else { return }
        Task { await self.hatchIfNeeded() }
    }

    /// 알 상태에서 부화를 미리 준비 — ① 종 pre-roll(pendingHatchID, 영속) ② 진화 라인
    /// fetch(provider 캐시 적재) ③ 스프라이트 예열(정적+애니메이션+shiny 애니메이션).
    /// 전부 성공하면 부화 순간 네트워크 0. 실패 지점부터 다음 update 틱에 이어서 재시도.
    func ensureEggPrefetch() async {
        guard state.active == nil, state.raisedEntry == nil, !isHatching, !prefetchInFlight else { return }
        let generation = activeGeneration
        var shouldHatch = false
        prefetchInFlight = true
        defer { finishEggPrefetch(generation: generation, shouldHatch: shouldHatch) }

        if state.pendingHatchID == nil {
            let selected = await chooseBase()
            // await 사이에 부화가 끝났거나(active != nil) 상태가 통째로 교체됐으면(세이브 불러오기)
            // 이 롤을 버린다 — 안 그러면 불러온 알의 pre-roll 을 남의 롤로 덮어쓴다.
            guard isCurrentEgg(generation: generation) else { return }
            guard let id = selected else {
                markHatchRetryDelayedIfReady(generation: generation)
                return
            }
            state.pendingHatchID = id
            state.pendingForm = rollLineForm(baseID: id)
            save()
        }
        guard let id = state.pendingHatchID else { return }
        if prefetchedLineID == id {
            isHatchRetryDelayed = false
            shouldHatch = true
            return
        }
        let form = state.pendingForm
        let line: EvoLine
        do {
            line = try await provider.line(baseSpeciesID: id)
        } catch {
            markHatchRetryDelayedIfReady(generation: generation)
            return
        }
        guard isCurrentEgg(generation: generation), state.pendingHatchID == id else { return }
        // 스프라이트 예열 — 부화 직후 보일 것들: base 정적+애니메이션, shiny 롤(1/64) 대비 shiny 애니메이션.
        // .app 번들에서만(단위 테스트가 실네트워크에 닿지 않도록 — 알림과 동일한 게이트).
        if AppEnv.isBundledApp {
            _ = await SpriteStore.shared.data(speciesID: line.baseID, animated: false, shiny: false, form: form)
            _ = await SpriteStore.shared.data(speciesID: line.baseID, animated: true, shiny: false, form: form)
            _ = await SpriteStore.shared.data(speciesID: line.baseID, animated: true, shiny: true, form: form)
            if PokemonForm.hasForms(speciesID: line.baseID) {
                _ = await SpriteStore.shared.data(speciesID: line.baseID, animated: false, shiny: true, form: form)
            }
            await loadFormNames(baseID: line.baseID, form: form)
        }
        guard isCurrentEgg(generation: generation), state.pendingHatchID == id else { return }
        prefetchedLineID = id
        isHatchRetryDelayed = false
        shouldHatch = true
    }

    /// Draws only for lines with forms, so other species keep their random sequence.
    func rollLineForm(baseID: Int) -> PokemonForm? {
        let forms = PokemonForm.hatchForms(baseID: baseID)
        guard !forms.isEmpty else { return nil }
        return PokemonForm.roll(rng.next(), among: forms, collected: state.collectedLineForms(baseID: baseID))
    }

    /// Warms the localized names the hatch, evolution and graduation messages of this line show.
    private func loadFormNames(baseID: Int, form: PokemonForm?) async {
        await loadFormNames(PokemonForm.formSpecies(baseID: baseID).compactMap {
            PokemonForm.nameResource(speciesID: $0, form: form)
        })
    }

    /// The raised Pokémon's form names, for its title and its evolution and graduation messages.
    func loadActiveFormNames() async {
        if let graduate = raisedGraduate {
            await loadFormNames(baseID: graduate.baseID, form: graduate.form)
        } else if let active = state.active {
            await loadFormNames(baseID: active.baseID, form: active.form)
        }
    }

    func loadFormNames(_ resources: [PokemonNameResource]) async {
        for resource in Set(resources) {
            _ = await PokemonNameDisplayStore.shared.load(resource, provider: PokemonNameClient.shared)
        }
    }

    func formDisplayName(_ name: String, speciesID: Int, form: PokemonForm?) -> String {
        PokemonForm.displayName(name, speciesID: speciesID, form: form, language: state.language)
    }

    func hatch(baseID: Int) async {
        guard !isHatching, state.raisedEntry == nil else { return }
        let generation = activeGeneration
        isHatching = true
        defer { isHatching = false }
        await hatchCore(baseID: baseID, generation: generation)
    }

    // MARK: 메타몽 위장/리빌

    /// 메타몽 위장 롤 판정(순수) — common·≥2형태만, 미리 뽑은 roll 값으로 1/128. (부수효과 없이 xctest)
    nonisolated static func dittoDisguiseHit(rarity: Rarity, totalForms: Int, roll: UInt64) -> Bool {
        rarity == .common && totalForms >= 2 && roll % PokemonOdds.dittoDisguiseDenominator == 0
    }

    /// 이로치 부화 분모 — 부적 보유 48, 없으면 64. 판정과 알림 문구가 같은 값을 쓰도록 여기가 단일 소스다.
    nonisolated static func shinyDenominator(charmOwned: Bool) -> UInt64 {
        charmOwned ? ShinyCharm.shinyDenominator : PokemonOdds.shinyDenominator
    }

    /// 지금 부화하면 적용될 이로치 분모.
    var shinyDenominator: UInt64 { Self.shinyDenominator(charmOwned: ownsShinyCharm) }

    /// 이로치 부화 판정(순수) — 미리 뽑은 roll 값 % 분모==0. (부수효과 없이 xctest)
    nonisolated static func rollsShiny(roll: UInt64, charmOwned: Bool) -> Bool {
        roll % shinyDenominator(charmOwned: charmOwned) == 0
    }

    /// 실제 부화 로직 — isHatching 락은 호출자(hatch / hatchIfNeeded)가 소유·해제한다.
    private func hatchCore(baseID: Int, generation: Int, form pendingForm: PokemonForm? = nil) async {
        let line: EvoLine
        do {
            line = try await provider.line(baseSpeciesID: baseID).prunedTradeOnly()
        } catch {
            markHatchRetryDelayedIfReady(generation: generation)
            AppLog.write("hatch: line fetch failed for base \(baseID) — egg kept, retry next tick")
            return
        }
        // 라인 fetch 창(네트워크) 동안 활성 개체가 교체됐으면 이 부화 결과를 폐기한다. 세이브 불러오기가
        // 그 창에 들어오면, 여기서 멈추지 않는 한 갓 부화한 개체가 방금 불러온 개체를 덮어쓴다.
        // (loadCurrentLine·revealDitto 와 같은 세대 가드 — isHatching 락은 같은 앱 내 중복 부화만 막는다.)
        guard activeGeneration == generation else {
            AppLog.write("hatch: discarded — active subject replaced during line fetch")
            kickLineLoadIfNeeded()
            return
        }
        // 산 보증을 지키는 마지막 관문 — 진짜 등급을 아는 건 여기뿐이다(후보 인덱스엔 capture_rate 만
        // 있고 is_legendary 가 없다). 필터가 어긋났으면(인덱스 stale 등) 낮은 등급을 그냥 내주지 말고
        // 알을 유지한 채 pre-roll 만 버려 다음 틱에 다시 뽑는다 — 사용자는 산 보증을 계속 들고 있는다.
        if let tier = state.eggTier, line.rarity.sortRank < tier.sortRank {
            AppLog.write("hatch: rolled \(line.rarity) below guaranteed \(tier) — discarded, re-roll next tick")
            state.pendingHatchID = nil
            state.pendingForm = nil
            prefetchedLineID = nil
            markHatchRetryDelayedIfReady(generation: generation)
            save()
            return
        }
        state.pendingHatchID = nil
        state.pendingForm = nil
        // A later egg can roll the same species with another form and must warm its own sprite.
        prefetchedLineID = nil
        currentLine = line
        isHatchRetryDelayed = false
        // 부화 임계 초과분은 부화체 성장에 이월(낭비 없음).
        let overflow = max(0, state.eggUsage - eggHatchThreshold)
        state.eggUsage = 0
        state.eggTier = nil   // 보증은 이 부화로 소비된다(다음 알은 다시 무보증)
        let scouted = state.scoutedEgg
        state.scoutedEgg = false
        let prizeShiny = state.shinyEgg
        state.shinyEgg = false
        let prayers = state.eggPrayers   // 부화체에 옮기고 알 쪽은 비운다
        state.resetEggPrayers()
        // 개체 롤 — shiny(1/64, 부적 1/48)·성격(25종)은 부화 순간 확정, 진화해도 유지.
        // 알림 문구는 이 판정과 같은 분모를 보여준다.
        let shinyOdds = shinyDenominator
        let isShiny = Self.rollsShiny(roll: rng.next(), charmOwned: ownsShinyCharm) || prizeShiny
        let nature = PokemonNature.allCases[Int(rng.next() % UInt64(PokemonNature.allCases.count))]
        // 메타몽 위장 롤 — common·≥2형태에 한해 1/128. .app 게이트(&& 단락 → 비앱에선 rng 미소비로
        // 기존 테스트 RNG 시퀀스 무영향). 위장/리빌 로직은 상태 기반으로 별도 테스트한다.
        var dittoDisguise: Int?
        if dittoDisguiseRollingEnabled, !scouted,   // 스카우트로 고른 종이 메타몽으로 바뀌면 산 걸 못 받는다
           Self.dittoDisguiseHit(rarity: line.rarity, totalForms: line.totalForms, roll: rng.next()) {
            dittoDisguise = line.baseID
        }
        // Gender is rolled before the plan: it decides which evolutions the individual can take.
        var profile = PokemonProfile.generate(seed: rng.next())
        if let rate = line.genderRate { profile.assignGender(genderRate: rate) }
        let evolutionPlan = makeEvolutionPlan(
            from: line.tree, baseID: line.baseID, gender: profile.gender,
            traits: EvolutionTraits(seed: profile.seed, ivs: profile.ivs, nature: nature))
        if let details = pokemonDetailsByID[line.baseID] { profile.enrich(with: details) }
        let hasGrowthBoost = state.hasCollectedFinal(forBaseID: line.baseID)
        let form = pendingForm ?? rollLineForm(baseID: line.baseID)
        // 위장 중엔 이로치를 숨긴다 — 부화 알림·연출도 일반체로(정체는 리빌 때 공개).
        let showShiny = isShiny && dittoDisguise == nil
        activeGeneration += 1
        state.active = MonState(baseID: line.baseID, pathIDs: [line.baseID], plannedPathIDs: evolutionPlan,
                                stageIndex: 0, usedAtStage: 0, rarity: line.rarity, totalForms: evolutionPlan.count,
                                isShiny: isShiny, nature: nature, profile: profile, hasGrowthBoost: hasGrowthBoost,
                                dittoDisguise: dittoDisguise, form: form, prayers: prayers, tradeGated: true)
        state.active!.evolution = EvolutionProgress(spentBaseline: state.spentTokens, battleCursor: clock())
        AppLog.write("hatch: base=\(line.baseID) rarity=\(line.rarity) shiny=\(isShiny) forms=\(evolutionPlan.count) boost=\(hasGrowthBoost) ditto=\(dittoDisguise != nil)")
        let name = formDisplayName(line.localizedName(line.baseID, state.language),
                                   speciesID: line.baseID, form: form)
        let hatchBody: String
        if let prayers, prayers.count > 0 {
            hatchBody = l.notifPrayerHatchBody(name, prayers: prayers.count, shiny: showShiny,
                                               rarity: line.rarity)
        } else {
            hatchBody = showShiny ? l.notifShinyHatchBody(name, odds: shinyOdds) : l.notifHatchBody(name)
        }
        notifyCompanionEvent(showShiny ? l.notifShinyHatchTitle : l.notifHatchTitle, hatchBody)
        justEvolvedTo = nil        // 새 부화는 "성장" 문구(진화 아님) — 직전 진화명이 남아 표시되지 않게
        displayState = .levelUp
        eventUntil = clock().addingTimeInterval(4)
        if overflow > 0 { applyUsage(overflow) }   // 이월분 즉시 반영(필요 시 진화/리빌까지)
        // 연출은 이월 진화 뒤에 발화 — 이월 evolve 가 shiny 부화 버스트를 덮지 않도록
        // 마지막 이벤트를 hatch 로 유지한다. 이월로 즉시 졸업한 극단 케이스면 생략(이미 도감행).
        if state.active != nil { fireCelebration(.hatch(shiny: showShiny)) }
        save()
        if detailProvider != nil { Task { await self.loadPokemonDetails(speciesID: line.baseID) } }
    }

    /// 위장 → 리빌: 진화 못 하는 메타몽이 "첫 진화 임계"에서 진화 대신 정체를 드러내는 순간.
    /// Ditto 라인 로드 후 상태 변환(rare·단일형태·초과분 이월, isShiny/nature 유지) + 연출·알림.
    func revealDitto() async {
        guard let a = state.active, a.dittoDisguise != nil, !a.dittoRevealed, !isRevealingDitto else { return }
        let generation = activeGeneration
        let firstEvoThr = stageThreshold(for: a)
        guard a.usedAtStage >= firstEvoThr else { return }   // 임계 미달 방어
        isRevealingDitto = true
        defer { isRevealingDitto = false }
        guard let dittoLine = try? await provider.line(baseSpeciesID: PokemonOdds.dittoSpeciesID) else {
            AppLog.write("ditto reveal: line fetch failed — retry next tick"); return
        }
        guard activeGeneration == generation,
              var m = state.active, m.dittoDisguise != nil, !m.dittoRevealed else { return }
        let latestFirstEvoThr = stageThreshold(for: m)
        guard m.usedAtStage >= latestFirstEvoThr else { return }
        let disguiseName = currentLine?.localizedName(m.baseID, state.language) ?? "#\(m.baseID)"
        let carryOver = max(0, m.usedAtStage - latestFirstEvoThr)   // 위장체 첫 진화 초과분 → 메타몽 성장 이월
        // 메타몽으로 전환 — rarity/forms 는 로드한 라인에서, isShiny/nature/dittoDisguise 는 유지.
        let previousRarity = m.rarity
        m.baseID = dittoLine.baseID
        let evolutionPlan = makeEvolutionPlan(from: dittoLine.tree, baseID: dittoLine.baseID, gender: nil)
        m.pathIDs = [dittoLine.baseID]
        m.plannedPathIDs = evolutionPlan
        m.stageIndex = 0
        m.rarity = dittoLine.rarity
        m.totalForms = evolutionPlan.count
        m.usedAtStage = carryOver
        m.dittoRevealed = true
        m.form = nil
        // The hatch boost came from the disguise's line; from now on only a repeat Ditto earns it.
        m.hasGrowthBoost = state.hasCollectedFinal(forBaseID: dittoLine.baseID)
        m.profile?.rebaseForSpeciesIdentity(from: previousRarity, to: dittoLine.rarity)
        if let details = pokemonDetailsByID[dittoLine.baseID] {
            m.profile?.enrich(with: details)
        }
        let shiny = m.isShiny
        state.active = m
        state.reconcileRepresentativeSelection()   // 위장 종만 근거였던 선택은 리빌과 함께 제거
        currentLine = dittoLine
        AppLog.write("ditto reveal: disguise=\(m.dittoDisguise ?? -1) → ditto rarity=\(dittoLine.rarity) shiny=\(shiny)")
        fireCelebration(.dittoReveal(shiny: shiny))
        displayState = .levelUp
        eventUntil = clock().addingTimeInterval(5)
        notifyCompanionEvent(shiny ? l.notifShinyDittoRevealTitle : l.notifDittoRevealTitle,
                             shiny ? l.notifShinyDittoRevealBody(disguiseName) : l.notifDittoRevealBody(disguiseName))
        save()
        applyUsage(0)   // 이월분으로 메타몽 졸업 재평가(rare 3B라 보통 즉시 졸업 아님)
        isRevealingDitto = false   // Details are enrichment, not part of the reveal transaction.
        if detailProvider != nil {
            await loadPokemonDetails(speciesID: PokemonOdds.dittoSpeciesID)
        }
    }

    func loadCurrentLine() async {
        guard let a = state.active, currentLine == nil, !isHatching else { return }
        let generation = activeGeneration
        isHatching = true
        defer { isHatching = false }
        if let fullLine = try? await provider.line(baseSpeciesID: a.baseID) {
            let line = a.tradeGated == true
                ? fullLine.prunedTradeOnly(keeping: Set(a.pathIDs + a.plannedPathIDs)) : fullLine
            // await 중 사용량·민트 등 활성 상태는 계속 바뀔 수 있다. 요청 당시 스냅샷을 다시 쓰지 말고
            // 같은 개체가 아직 활성인 경우에만 최신 상태를 정규화한다.
            guard activeGeneration == generation,
                  var latest = state.active, latest.baseID == a.baseID, currentLine == nil else { return }
            // Old saves rolled gender only once details arrived; settle it before the plan is checked.
            if let rate = line.genderRate { latest.profile?.assignGender(genderRate: rate) }
            state.active = normalizedEvolutionState(latest, from: line.tree)
            state.reconcileRepresentativeSelection()   // 손상 경로 정규화로 사라진 단계가 대표로 남지 않게
            currentLine = line
            save()   // 마이그레이션 선택을 사용량 재평가 전에 영속화해 재시작마다 다시 롤리지 않는다.
            applyUsage(0)   // 라인 미로딩 동안 적립된 사용량이 임계를 넘었으면 지금 진화 판정
            // Path normalization can change currentID without entering the regular evolution branch.
            isHatching = false   // Do not hold the line-load lock across detail HTTP requests.
            // After a relaunch only the popover loads form names; evolution and graduation
            // notifications need them before it is opened.
            if AppEnv.isBundledApp { await loadActiveFormNames() }
            if let speciesID = state.active?.currentID, detailProvider != nil {
                await loadPokemonDetails(speciesID: speciesID)
            }
        }
    }

    /// 부화 종 선정 — 하드코딩 풀 없이 PokéAPI 지원 범위 base 전체에서 가중 선택.
    ///   ① base 인덱스(id + capture_rate)를 GraphQL 1쿼리로 취득(30일 디스크 캐시 → 보통 0콜)
    ///   ② 가중치 = 공식 capture_rate 그대로(캐터피 255 vs 뮤츠 3 = 85:1, 전설군 ≈ 0.77%)
    ///      단, 이미 수집한 base 는 가중치 ½(미수집 부스트 — 재부화/shiny 사냥은 열어둠)
    ///   ③ 누적 가중치에서 정확히 1롤 — 루프/재롤 없음, 시간 상한 확정적
    /// 인덱스 취득 실패(오프라인 + 캐시 없음) 시 nil → 알 유지, 다음 갱신 틱 재시도.
    private func chooseBase() async -> Int? {
        let tier = state.eggTier
        if let full = try? await provider.baseSpeciesIndex(), !full.isEmpty {
            // 등급 보증 알은 후보를 먼저 좁힌다 — capture_rate 상한이 곧 등급 하한이므로
            // (Rarity.captureRateCeiling) 전설도 자연히 포함된다("희귀 이상"에 전설이 들어가는 게 정상).
            // 좁힌 결과가 비면 보증을 못 지키므로 전체 풀로 폴백하지 말고 알을 유지한다(다음 틱 재시도).
            let index = tier.map { t in full.filter { t.includes(captureRate: $0.captureRate) } } ?? full
            guard !index.isEmpty else {
                AppLog.write("hatch: no candidate for guaranteed \(tier?.rawValue ?? "none") — egg kept, retry next tick")
                return nil
            }
            return SpeciesRoll.pick(from: index, isCollected: { state.hasCollectedFinal(forBaseID: $0) }, rng: &rng)?.id
        }
        // GraphQL base 인덱스 엔드포인트 장애 → REST 폴백. 부화가 한 엔드포인트에 묶이지 않게.
        AppLog.write("hatch: base index unavailable — REST fallback")
        return await chooseBaseViaREST()
    }

    /// REST 폴백 — animated 에셋 지원 범위에서 무작위 id 를 뽑아 base 인지 확인(rejection sampling).
    /// GraphQL 인덱스가 죽어도 부화가 되게 한다. 가중치(capture_rate)는 생략 — 희귀도는 부화 후
    /// line() 이 실제 capture_rate 로 계산하므로 결과 개체의 등급은 정확하다. 인덱스 복구 시 가중 선택 재개.
    private func chooseBaseViaREST() async -> Int? {
        let tier = state.eggTier
        for attempt in 1...16 {
            let ids = PokemonAssets.supportedSpeciesIDs
            let id = Int(rng.next() % UInt64(ids.count)) + ids.lowerBound
            do {
                if let bs = try await provider.baseSpecies(id: id) {
                    // 등급 보증은 가중 경로와 **같은 기준**으로 여기서도 걸러야 한다 — 이 폴백만 빠지면
                    // GraphQL 인덱스 장애 때 보증이 조용히 깨진다. 못 찾으면 알 유지(구매 소멸 금지).
                    if let tier, !tier.includes(captureRate: bs.captureRate) { continue }
                    AppLog.write("hatch: REST fallback picked base \(id) (cap \(bs.captureRate), \(attempt) tries)")
                    return id
                }
                // nil = base 아님(진화 중간체) → 다음 시도
            } catch {
                AppLog.write("hatch: REST fallback network error — retry next tick: \(error)")
                return nil   // REST 도 불가 → 알 유지, 다음 update 틱 재시도
            }
        }
        AppLog.write("hatch: REST fallback exhausted 16 tries")
        return nil
    }
}
