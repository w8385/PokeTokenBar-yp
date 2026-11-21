import Foundation

extension CompanionStore {
    // MARK: 갱신 (AppDelegate 가 UsageStore 값으로 호출)

    /// `timeSinceLastUsage`: nil when unknown (see `UsageStore.timeSinceLastUsage`); unknown never sulks.
    /// It comes from the slower enrichment scan, so a rise in today's total seen here counts as usage at once.
    /// `dayTotalsByProvider`: `UsageStore.dayTotalsByProvider`. nil holds a token-mode date change until
    /// today's scan has finished; `[:]` credits no tail.
    func update(todayTokensByProvider: [String: Int], todayDate: String, monthTotal: Int,
                burnTier: BurnTier, limitWarning: Bool, hasUsageData: Bool,
                timeSinceLastUsage: TimeInterval? = nil,
                dayTotalsByProvider: [String: [String: Int]]? = [:]) {
        let todayTokens = todayTokensByProvider.values.reduce(0, +)
        // `hasUsageData`는 표시용 snapshot 존재 여부이고, 이 map은 오늘 날짜가 확인된
        // provider 데이터만 담는다. stale snapshot이나 today == nil carrier만 있는 refresh는
        // ledger의 기준점을 움직일 수 있는 관측으로 취급하지 않는다.
        let hasCurrentProviderData = hasUsageData && !todayTokensByProvider.isEmpty
        let idle = effectiveIdle(timeSinceLastUsage: timeSinceLastUsage, todayDate: todayDate,
                                 todayTokens: todayTokens, hasCurrentProviderData: hasCurrentProviderData)
        if state.growthMode == .time, !state.installBaselineSet, !hasCurrentProviderData {
            // Time mode must work with no coding agent at all. A nil ledger seeds from the first usage seen later.
            state.installBaselineSet = true
        }
        if !state.installBaselineSet {
            // 설치 기준선 — 실제 데이터가 도착한 시점의 today 를 baseline 으로(이전 사용량 미카운트).
            // 데이터 도착 전(기동 직후 빈 새로고침)에는 잡지 않는다.
            guard hasCurrentProviderData else {
                // 세이브 불러오기가 baseline 판정을 이 경로에 넘겼을 수 있다(SaveTransfer.rebasedForThisDevice).
                // 그 경우 개체는 이미 들어와 있으므로 알로 표시하면 안 되고, 진화 라인 로드도 계속 재시도해야
                // 한다 — 새 Mac 은 AI CLI 를 처음 쓸 때까지 hasUsageData 가 false 라 여기서 막히면 그날 내내
                // 알로 보인다(재시작해도 동일).
                displayState = isEgg ? .egg : .idle
                kickLineLoadIfNeeded()
                return
            }
            state.installBaselineSet = true
            state.claimedTodayTokensByProvider = todayTokensByProvider
            state.lastDate = todayDate
            save()
        } else {
            // `today == nil` carrier만 남거나 파싱이 실패한 refresh는 현재 map이 비어 있을 수
            // 있다. 그런 관측으로 날짜·ledger를 움직이면 다음 정상 snapshot을 당일 전체 신규
            // 사용량으로 오인할 수 있으므로, 유효한 사용량이 있는 refresh만 ledger를 갱신한다.
            if hasCurrentProviderData {
                let dateChanged = todayDate != state.lastDate
                if state.claimedTodayTokensByProvider == nil {
                    // 구버전 세이브에는 aggregate high-water mark만 있어 프로바이더별로 분해할 수 없다.
                    // 첫 유효 관측을 새 장부의 기준점으로만 저장해 과거 사용량을 소급 지급하지 않는다.
                    state.claimedTodayTokensByProvider = todayTokensByProvider
                    state.lastDate = todayDate
                    AppLog.write("companion provider ledger seeded date=\(todayDate) providers=\(todayTokensByProvider.keys.sorted().joined(separator: ","))")
                } else if dateChanged, state.growthMode == .token, dayTotalsByProvider == nil {
                    AppLog.writeIfChanged("companion-date-hold", "companion date change held from=\(state.lastDate) to=\(todayDate) until day totals arrive")
                } else if dateChanged {
                    let tail = state.growthMode == .token
                        ? unseenDayTail(claimed: state.claimedTodayTokensByProvider!, before: todayDate,
                                        dayTotalsByProvider: dayTotalsByProvider ?? [:]) : 0
                    if tail > 0 {
                        AppLog.write("companion day tail credited from=\(state.lastDate) to=\(todayDate) tokens=\(tail)")
                    }
                    // 일자별 snapshot은 서로 비교할 수 없다. 새 날짜의 누적값은 이전 날짜의 ledger와
                    // 비교하지 않고 전체를 새 날짜 사용량으로 적립한다. 이전 날짜의 ledger는 그 날의
                    // 최종 합계와 비교해 못 본 꼬리(unseenDayTail)를 구하는 데만 쓴다.
                    // 단, 위의 nil migration 경로는 구버전 aggregate를 분해할 수 없으므로 seed만 한다.
                    //
                    // 이전 날짜에 이미 알려진 provider가 첫 새로고침에서 빠질 수 있다(오늘 데이터
                    // 없음, stale 응답, 일시 실패). 그 provider를 아예 ledger에서 제거하면 같은
                    // 날짜에 복구될 때 현재 누적값을 "이미 적립한 값"으로 seed해 사용량이 누락된다.
                    // 이전 날짜의 숫자는 비교에 사용할 수 없으므로, 알려진 provider의 새 날짜 기준을
                    // 0으로 열어 둔다. 이후 복구된 현재 날짜 값은 그 날짜의 실제 사용량으로 적립되고,
                    // 같은 날짜의 부분 응답에서는 이 기준을 그대로 보존한다.
                    state.lastDate = todayDate
                    var newLedger = Dictionary(uniqueKeysWithValues:
                        state.claimedTodayTokensByProvider!.keys.map { ($0, 0) })
                    for (providerID, current) in todayTokensByProvider {
                        newLedger[providerID] = current
                    }
                    state.claimedTodayTokensByProvider = newLedger
                    creditRealUsage(tail + todayTokensByProvider.values.reduce(0, +))
                } else {
                    var ledger = state.claimedTodayTokensByProvider ?? [:]
                    var delta = 0
                    for (providerID, current) in todayTokensByProvider {
                        guard let previous = ledger[providerID] else {
                            // 새로 관측된 프로바이더의 과거 로그를 소급하지 않는다. 이후 refresh부터
                            // 해당 프로바이더의 증가분을 추적할 수 있도록 현재 값을 seed한다.
                            ledger[providerID] = current
                            continue
                        }
                        if current < previous {
                            // 전체 합계가 아니라 해당 프로바이더의 line만 rebase한다. 다른 프로바이더가
                            // 이번 refresh에서 보고하지 않았거나 carrier snapshot만 남은 경우에는 map에
                            // line 자체가 없으므로 기존 기준값을 건드리지 않는다.
                            ledger[providerID] = current
                            AppLog.write("companion usage regression provider=\(providerID) date=\(todayDate) previous=\(previous) current=\(current) drop=\(previous - current) — rebased provider ledger")
                            continue
                        }
                        delta += current - previous
                        ledger[providerID] = current
                    }
                    state.claimedTodayTokensByProvider = ledger
                    creditRealUsage(delta)
                }
            }
        }
        // 이벤트(진화/졸업/부화) 창 만료 — .levelUp 창이 끝날 때 문구 플래그를 함께 정리한다.
        // justEvolvedTo 는 창 만료(expireEventWindow)에서만 지운다: 과거엔 매 update() 초입에 무조건 nil 로 밀어,
        // 진화 후 4초 창 도중 update 틱이 끼면 "…(으)로 진화했어요"→"성장했어요"로 되돌아갔다(회귀 #4).
        expireEventWindow()
        if state.active == nil, state.raisedEntry == nil, state.installBaselineSet, !isHatching {
            if state.eggUsage >= eggHatchThreshold {
                // ready egg 는 부화를 우선한다. 같은 틱에 프리패치와 별도 Task 로 경쟁시키면
                // 프리패치 락을 본 부화가 반환하고 실패 상태도 놓칠 수 있다.
                Task { await hatchIfNeeded() }
            } else {
                // 임계 전에는 종 pre-roll + 라인/스프라이트 예열(부화 순간 딜레이 제거).
                Task { await ensureEggPrefetch() }
            }
        }
        // active 인데 라인 미로딩(앱 재시작) → 로드
        if state.active != nil, currentLine == nil, !isHatching {
            Task { await loadCurrentLine() }
        }
        // 위장 메타몽이 첫 진화 임계 도달 → 리빌(재시작 등 applyUsage 킥을 못 탄 경우 백업 트리거)
        if let a = state.active, !isLineParked, a.dittoDisguise != nil, !a.dittoRevealed, currentLine != nil,
           !isHatching, !isRevealingDitto,
           a.usedAtStage >= stageThreshold(for: a) {
            Task { await revealDitto() }
        }
        if burnTier == .blazing { recordTokenRain() }
        checkEvolutionGate()
        displayState = computeState(burnTier: burnTier, limitWarning: limitWarning,
                                    hasUsageData: hasUsageData, today: todayTokens,
                                    timeSinceLastUsage: idle)
        sulkIdle = displayState == .sulk ? idle ?? 0 : 0
        rebaseUsageOnNextUpdate = false
        save()
        autoSnapshotIfNeeded()
    }

    /// Usage no refresh saw between `state.lastDate`'s last claim and the end of yesterday, for providers
    /// already in the ledger. A provider new to the ledger gets no back credit, as on the same day.
    private func unseenDayTail(claimed: [String: Int], before todayDate: String,
                               dayTotalsByProvider: [String: [String: Int]]) -> Int {
        let lastDate = state.lastDate
        var tail = 0
        for (providerID, alreadyClaimed) in claimed {
            for (day, total) in dayTotalsByProvider[providerID] ?? [:] where day >= lastDate && day < todayDate {
                tail += day == lastDate ? max(0, total - alreadyClaimed) : total
            }
        }
        return tail
    }

    /// Real usage: only token mode turns it into growth and wallet.
    private func creditRealUsage(_ delta: Int) {
        guard delta > 0 else { return }
        state.lastUsageAt = clock()
        guard state.growthMode == .token, !rebaseUsageOnNextUpdate else { return }
        state.usedSinceInstall += delta
        creditUsage(delta)
    }


    /// `timeSinceLastUsage`, capped by how long ago this store itself saw today's total rise.
    /// A new day or a first sighting only sets the baseline — it is not usage, so a midnight rollover
    /// neither un-sulks nor sulks by itself. nil stays nil: unknown is never idle.
    private func effectiveIdle(timeSinceLastUsage: TimeInterval?, todayDate: String, todayTokens: Int,
                               hasCurrentProviderData: Bool) -> TimeInterval? {
        if hasCurrentProviderData {
            if let seen = lastSeenToday, seen.date == todayDate, todayTokens > seen.total {
                lastObservedUsage = clock()
            }
            lastSeenToday = (todayDate, todayTokens)
        }
        guard let reported = timeSinceLastUsage else { return nil }
        guard let observed = lastObservedUsage else { return reported }
        return min(reported, max(0, clock().timeIntervalSince(observed)))
    }

    private func computeState(burnTier: BurnTier, limitWarning: Bool, hasUsageData: Bool, today: Int,
                              timeSinceLastUsage: TimeInterval? = nil) -> CompanionStateKind {
        if isEgg { return .egg }
        if justGraduated != nil || (eventUntil != nil && clock() < eventUntil!) { return .levelUp }
        if limitWarning { return .tired }
        if state.growthMode == .time { return timeActiveNow ? .working : .sleep }
        if hasUsageData, let idle = timeSinceLastUsage, idle >= PokemonBalance.sulkAfterIdle {
            return .sulk
        }
        if !hasUsageData || today == 0 { return .sleep }
        switch burnTier {
        case .idle: return .idle
        case .normal: return .working
        case .fast, .blazing: return .focus
        }
    }
}
