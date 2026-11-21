import Foundation
import UserNotifications

extension CompanionStore {
    // MARK: 클릭 성장

    /// One click or pat on the pet. Grows the egg or Pokémon like tokens do and returns the XP it added.
    @discardableResult
    func growByClick() -> Int {
        let xp = ClickGrowth.tokensPerClick
        state.clickGrowth += xp
        if state.raisedEntry != nil {
            recordPet()
            creditRaisedGraduate(xp)
            save()
        } else if state.active == nil {
            state.eggUsage += xp
            save()
            if state.eggUsage >= eggHatchThreshold { Task { await hatchIfNeeded() } }
        } else {
            recordPet()
            applyUsage(xp)
        }
        return xp
    }

    /// Pray over the egg. A placebo: it only counts, and never touches an RNG or a roll — the species is
    /// usually already in `pendingHatchID` (prefetched at purchase) long before anyone prays.
    func pray() {
        guard state.active == nil, state.raisedEntry == nil else { return }
        var record = state.eggPrayers ?? PrayerRecord(count: 0)
        record.count += 1
        state.eggPrayers = record
        save()
    }

    // 보증 없는 기본 알 래퍼 — 기존 호출부/테스트 호환.
    var canBuyFreshEgg: Bool { canBuyEgg(nil) }
    @discardableResult
    func buyFreshEgg() -> Bool { buyEgg(nil) }

    /// Parse an epoch string into a Date, supporting Unix timestamp (seconds or ms) or ISO8601 strings.
    static func parseEpochDate(_ string: String) -> Date? {
        if let ts = Double(string) {
            if ts > 1_000_000_000_000 {
                return Date(timeIntervalSince1970: ts / 1000.0)
            } else if ts > 100_000_000 {
                return Date(timeIntervalSince1970: ts)
            }
        }
        return ISO8601Parser.date(from: string)
    }

    /// Determines if a new epoch represents an actual window advancement (reset) rather than
    /// volatile network jitter (e.g. Codex ±1s) or fractional-second differences (Claude microseconds).
    /// For session windows (≈5h), requires advancing forward by at least 30 minutes.
    /// For weekly windows (7d), requires advancing forward by at least 24 hours.
    /// Non-date strings (used in synthetic unit tests) fall back to string inequality.
    static func isNewEpoch(previous: String, current: String, kind: WindowClass) -> Bool {
        guard previous != current else { return false }
        guard let dPrev = parseEpochDate(previous), let dCurr = parseEpochDate(current) else {
            return true
        }
        let delta = dCurr.timeIntervalSince(dPrev)
        let minAdvance: TimeInterval = kind == .weekly ? 86400 : 1800
        return delta >= minAdvance
    }

    /// 지급 판정(순수·엣지 트리거) — 한도 창이 100% 를 새로 넘어선 순간에만 지급.
    /// - 100% 미만 → 맵에서 제거(재무장).
    /// - 같은 key 라도 epoch(`resets_at`)가 바뀌면 새 창으로 보고 재무장 — 슬립·종료로 &lt;100% 샘플을
    ///   못 본 채 다시 100%만 관측해도 지급 누락이 없다(#326). key 자체엔 epoch 를 넣지 않는다
    ///   (알림 dedup 과 같은 이유로 매 fetch 새 키 폭탄 방지).
    /// - epoch 없는 창(Codex)은 100% 미만 관측으로만 재무장한다.
    /// - 이미 지급한 창(tier≥1)은 재지급 안 함. session=1개·weekly=weeklyGrant.
    /// - 부수효과(인벤토리·알림)와 분리해 xctest 가능. (evaluateLimitAlerts 자매)
    static func evaluateCandyGrants(
        windows: [CandyWindow],
        grantTier: inout [String: Int],
        windowEpoch: inout [String: String]
    ) -> [CandyGrant] {
        var grants: [CandyGrant] = []
        for w in windows {
            if let epoch = w.epoch {
                if let previousEpoch = windowEpoch[w.key] {
                    if isNewEpoch(previous: previousEpoch, current: epoch, kind: w.kind) {
                        grantTier[w.key] = nil
                        windowEpoch[w.key] = epoch
                    }
                } else {
                    windowEpoch[w.key] = epoch
                }
            }
            guard w.utilization >= 100 else {
                grantTier[w.key] = nil
                if let epoch = w.epoch {
                    windowEpoch[w.key] = epoch
                }
                continue
            }
            let previous = grantTier[w.key] ?? 0
            guard previous < 1 else { continue }
            grantTier[w.key] = 1
            if let epoch = w.epoch {
                windowEpoch[w.key] = epoch
            }
            let count = w.kind == .weekly ? RareCandy.weeklyGrant : 1
            grants.append(CandyGrant(windowKey: w.key, windowName: w.name, count: count))
        }
        return grants
    }

    /// 한도 창 상태로부터 사탕 지급(엣지·영속). AppDelegate 가 매 refresh 완료 시(한도 로드 후) 호출.
    /// - 첫 실행: 현재 100% 창을 지급 없이 tier 시드만 → 이후 "새로 넘어서는" 순간부터 지급(소급 차단).
    /// - limitsReady=false(한도 미로딩)면 시드/지급 모두 대기(다음 refresh 에 재시도).
    func grantCandies(from windows: [CandyWindow], limitsReady: Bool) {
        guard limitsReady else { return }
        if !state.candyFeatureSeeded {
            // 한계(수용): 첫 refresh 에 한 프로바이더 한도만 로드되면 그 프로바이더 창만 시드된다.
            // 이후 다른 프로바이더가 이미 100%인 채 로드되면 소급 지급될 수 있으나, 1회·소수 캔디라
            // 1인 로컬에서 무시(YAGNI). refresh() 는 전 프로바이더 fetch 를 await 후 onRefresh 하므로
            // 정상 경로(둘 다 성공)에선 원자적 시드다.
            for w in windows where w.utilization >= 100 {
                state.candyGrantTier[w.key] = 1
                if let epoch = w.epoch { state.candyWindowEpoch[w.key] = epoch }
            }
            state.candyFeatureSeeded = true
            save()
            return
        }
        let beforeTier = state.candyGrantTier
        let beforeEpoch = state.candyWindowEpoch
        var grantTier = state.candyGrantTier
        var windowEpoch = state.candyWindowEpoch
        let grants = Self.evaluateCandyGrants(
            windows: windows,
            grantTier: &grantTier,
            windowEpoch: &windowEpoch)
        state.candyGrantTier = grantTier
        state.candyWindowEpoch = windowEpoch
        for g in grants {
            state.inventory[ItemKind.rareCandy.rawValue, default: 0] += g.count
            // 지급 자체는 알림 여부와 무관(상태 변경). 알림은 "왜 받는지"(그 창 한도를 다 채운 수고) 명시.
            notifyCompanionEvent(l.notifCandyTitle(item: l.itemName(.rareCandy), count: g.count),
                                 l.notifCandyBody(window: g.windowName), showsOnPet: false)
        }
        // 지급이 없어도 재무장(util dip / epoch 교체)은 영속해야 한다 —
        // 안 하면 재시작 시 stale tier=1 로 다음 100% 도달이 "이미 지급"으로 오판돼 지급 누락(회귀).
        if !grants.isEmpty
            || state.candyGrantTier != beforeTier
            || state.candyWindowEpoch != beforeEpoch {
            save()
        }
    }


    func notifyCompanionEvent(_ title: String, _ body: String, showsOnPet: Bool = true) {
        if showsOnPet {
            eventSeq += 1
            latestEvent = CompanionEvent(seq: eventSeq, text: body, at: clock())
        }
        guard AppEnv.isBundledApp else { return }
        guard UserDefaults.standard.object(forKey: "companionNotifications") as? Bool ?? true else { return }
        notifSeq += 1
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "companion-event-\(notifSeq)", content: content, trigger: nil))
    }
}
