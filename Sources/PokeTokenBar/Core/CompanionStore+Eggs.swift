import Foundation

extension CompanionStore {
    // MARK: 알 (현재 포켓몬은 박스로, 도감·확률 무영향)

    /// 현재 알이 보증하는 등급 하한(UI 표시용). 활성 포켓몬이 있으면 알이 없으므로 nil.
    var eggGuarantee: Rarity? { isEgg ? state.eggTier : nil }

    /// 알 구매 가능 — 박스로 보낼 활성 포켓몬이 있고 지갑이 그 티어 가격 이상일 때만.
    /// 알 상태에서는 살 수 없다 — 알끼리 교체하는 동작은 만들지 않는다.
    /// 항목 자체는 알 상태에서도 상점에 남는다(shopEntries) — 이 게이트는 구매만 막는다.
    func canBuyEgg(_ tier: Rarity?) -> Bool {
        // 파는 티어인지 먼저 확인한다 — 만족 불가능한 보증(전설: capture_rate 로 표현 불가)을 사면
        // 두 롤 경로 모두 후보가 0개라 알이 영영 안 깨지고, 부화가 없으니 보증도 안 풀리며,
        // 새 알 구매는 `hasActive` 에 막혀 되돌릴 수단이 없다. 가격만 계산되면 값이 빠져나가므로
        // 판매 목록을 여기서 강제한다(호출부 하나가 실수하면 토큰이 통째로 사라진다).
        guard FreshEgg.shopTiers.contains(tier) else { return false }
        return hasActive && availableTokens >= price(of: .egg(tier))
    }

    /// 알 구매 — 현재 포켓몬을 박스로 보내고 처음부터 인큐베이션하는 새 알로. 지갑에서 가격 차감.
    /// `collectedFinals`(최종체 완성·분기 가중)는 손대지 않는다 — 끝까지 키운 게 아니다.
    ///
    /// 여기서 종을 롤하지 않는다 — 롤에는 네트워크가 필요해서 오프라인이면 토큰만 사라진다. 보증만
    /// 상태(`eggTier`)에 적고, 실제 롤은 프리패치/부화 경로가 그 보증을 읽어 수행한다.
    @discardableResult
    func buyEgg(_ tier: Rarity?) -> Bool {
        guard canBuyEgg(tier) else { return false }
        state.spentTokens += price(of: .egg(tier))
        storeActiveForNewEgg(tier: tier, pendingHatchID: nil)
        return true
    }

    /// 활성 포켓몬을 박스로 보내고 처음부터 인큐베이션하는 새 알로 — 상점 알과 스카우트가 같이 쓴다.
    /// `pendingHatchID` 가 있으면(스카우트) 그 종으로 미리 정해 두고 메타몽 위장도 끈다.
    func storeActiveForNewEgg(tier: Rarity?, pendingHatchID: Int?, shiny: Bool = false, attachesBagCopy: Bool = true) {
        if let storedID = storeActiveInBox() {
            addFriendIfSlotFree(storedID)
            if attachesBagCopy, !isExpShareTakenOff(storedID) { attachExpShare(to: storedID) }
        }
        state.reconcileRepresentativeSelection()
        activeGeneration += 1
        currentLine = nil
        state.eggUsage = 0            // 새 알은 처음부터 인큐베이션(재부화에 부화 임계만큼 필요)
        state.resetEggPrayers()
        isHatchRetryDelayed = false
        state.eggTier = tier          // 등급 보증(nil = 보증 없음)
        state.pendingHatchID = pendingHatchID   // nil 이면 새 보증으로 처음부터 롤(활성 포켓몬이 있는 동안엔 원래 비어 있다)
        state.pendingForm = pendingHatchID.flatMap { shiny ? PokemonForm.lineForms(baseID: $0).first : rollLineForm(baseID: $0) }
        state.scoutedEgg = pendingHatchID != nil
        state.shinyEgg = shiny
        prefetchedLineID = nil
        justGraduated = nil; justEvolvedTo = nil; eventUntil = nil
        AppLog.write("egg purchased: active stored in the Box, tier=\(tier?.rawValue ?? "none") scouted=\(pendingHatchID.map(String.init) ?? "no")")
        Task { await self.ensureEggPrefetch() }   // 다음 부화 예열
        save()
    }

    // MARK: 스카우트 (티켓 → 후보 10종 → 하나 골라 그 종의 알)

    func scoutTicketCount(_ pool: ScoutPool) -> Int { max(0, state.inventory[pool.inventoryKey] ?? 0) }

    /// 가방에 든 티켓 — 지역 순서(전국 마지막).
    var ownedScoutTickets: [(pool: ScoutPool, count: Int)] {
        ScoutPool.all.compactMap { pool in
            let count = scoutTicketCount(pool)
            return count > 0 ? (pool, count) : nil
        }
    }

    var scoutPrice: Int { ScoutTicket.price }
    var canBuyScoutTicket: Bool { availableTokens >= scoutPrice }

    @discardableResult
    func buyScoutTicket(_ pool: ScoutPool) -> Bool {
        guard canBuyScoutTicket else { return false }
        completePurchase(key: pool.inventoryKey, count: 1, cost: scoutPrice)
        return true
    }

    /// 이 티켓으로 이미 뽑아 둔 후보. 없으면 nil.
    func scoutDraw(for pool: ScoutPool) -> [Int]? {
        guard scoutTicketCount(pool) > 0, let ids = state.scoutDraws[pool.key], !ids.isEmpty else { return nil }
        return ids
    }

    /// 후보를 돌려준다 — 이미 뽑아 둔 게 있으면 그대로, 없으면 알이 쓰는 가중치로 10종을 뽑아 저장한다.
    /// 티켓은 여기서 쓰지 않는다(고를 때 쓴다). 종 인덱스를 못 받으면 nil — 티켓은 그대로다.
    func drawScout(_ pool: ScoutPool) async -> [Int]? {
        guard scoutTicketCount(pool) > 0 else { return nil }
        if let existing = scoutDraw(for: pool) { return existing }
        guard let full = try? await provider.baseSpeciesIndex() else { return nil }
        // await 사이에 다른 호출이 먼저 뽑았거나 티켓이 줄었을 수 있다.
        guard scoutTicketCount(pool) > 0 else { return nil }
        if let existing = scoutDraw(for: pool) { return existing }
        let candidates = full.filter { pool.dexRange.contains($0.id) && PokemonAssets.isSupported(speciesID: $0.id) }
        let drawn = SpeciesRoll.drawDistinct(from: candidates, count: ScoutTicket.drawSize,
                                             isCollected: { state.hasCollectedFinal(forBaseID: $0) }, rng: &rng)
        guard !drawn.isEmpty else { return nil }
        state.scoutDraws[pool.key] = drawn
        save()
        return drawn
    }

    /// 고르기는 박스로 보낼 포켓몬이 있을 때만 — 알 상태에서 알을 바꾸는 동작은 상점 알과 같은 이유로 만들지 않는다.
    var canPickScout: Bool { hasActive }

    /// 고른 종의 알로 바꾼다 — 티켓 1장과 그 풀의 후보를 지운다. 현재 포켓몬은 박스로 간다.
    @discardableResult
    func pickScout(_ pool: ScoutPool, speciesID: Int) -> Bool {
        guard canPickScout, scoutTicketCount(pool) > 0, scoutDraw(for: pool)?.contains(speciesID) == true else { return false }
        state.inventory[pool.inventoryKey] = scoutTicketCount(pool) - 1
        state.scoutDraws[pool.key] = nil
        storeActiveForNewEgg(tier: nil, pendingHatchID: speciesID)
        return true
    }

    // MARK: Hidden boss prize eggs

    func prizeEggCount(speciesID: Int) -> Int {
        max(0, state.inventory[HiddenBossPrize.eggKey(speciesID)] ?? 0)
    }

    /// Prize eggs in the bag, in prize-table order.
    var ownedPrizeEggs: [(speciesID: Int, count: Int)] {
        HiddenBossPrize.all.compactMap { prize in
            let count = prizeEggCount(speciesID: prize.eggSpeciesID)
            return count > 0 ? (prize.eggSpeciesID, count) : nil
        }
    }

    /// Same gate as a scout pick: the active Pokémon goes to the Box to make room for the egg.
    var canHatchPrizeEgg: Bool { hasActive }

    @discardableResult
    func hatchPrizeEgg(speciesID: Int) -> Bool {
        guard canHatchPrizeEgg, prizeEggCount(speciesID: speciesID) > 0 else { return false }
        state.inventory[HiddenBossPrize.eggKey(speciesID)] = prizeEggCount(speciesID: speciesID) - 1
        storeActiveForNewEgg(tier: nil, pendingHatchID: speciesID, shiny: true)
        return true
    }

    /// 후보 한 칸의 표시 정보 — 종 인덱스(이름·타입·전설 여부)가 있어야 만든다.
    struct ScoutPick: Identifiable {
        let species: DexSpecies
        let types: [String]
        var id: Int { species.id }
    }

    func scoutPicks(_ ids: [Int]) -> [ScoutPick] {
        guard let speciesIndex else { return [] }
        return ids.compactMap { id in
            guard let entry = speciesIndex.entry(id), let rarity = speciesIndex.rarity(of: id) else { return nil }
            let species = DexSpecies(id: id, name: state.language.resolveName(entry.names) ?? "#\(id)",
                                     rarity: rarity, isShiny: false, isRaising: false,
                                     names: entry.names, isOwned: state.ownsSpecies(id))
            return ScoutPick(species: species, types: entry.types)
        }
    }
}
