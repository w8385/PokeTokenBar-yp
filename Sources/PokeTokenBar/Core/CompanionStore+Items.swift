import Foundation

extension CompanionStore {
    // MARK: 인벤토리 / 이상한 사탕

    var rareCandyCount: Int { itemCount(.rareCandy) }
    func itemCount(_ kind: ItemKind) -> Int { state.inventory[kind.rawValue] ?? 0 }
    /// 이로치 부적 보유 여부 — 보유형이라 개수>0 = 소유(부화 shiny 분모를 낮춘다).
    var ownsShinyCharm: Bool { itemCount(.shinyCharm) > 0 }

    /// 소유 아이템(개수>0) — 가방 목록. 정렬은 ItemKind.listOrder 순서.
    var ownedItems: [(kind: ItemKind, count: Int)] {
        ItemKind.listOrder.compactMap { k in
            let c = itemCount(k)
            return c > 0 ? (k, c) : nil
        }
    }

    func ownedItems(in category: ItemCategory?) -> [(kind: ItemKind, count: Int)] {
        guard let category else { return ownedItems }
        return ownedItems.filter { $0.kind.category == category }
    }

    /// The bag's flat list for a chip. In the held tab and the all view, battle items move to `ownedBattleSections`.
    func bagListItems(in category: ItemCategory?) -> [(kind: ItemKind, count: Int)] {
        let items = ownedItems(in: category)
        guard category == nil || category == .heldItem else { return items }
        return items.filter { $0.kind.battleGroup == nil }
    }

    var ownedBattleSections: [BattleItemSection] { BattleItemGroup.sections(of: ownedItems.map(\.kind)) }

    // MARK: 지닌 도구 (개체에 달았다 뗀다 — 다는 동안 가방에서 빠지고 떼면 돌아온다)

    func heldItem(of instanceID: String) -> ItemKind? {
        state.heldItems[instanceID].flatMap(ItemKind.init(rawValue:))
    }

    func holdsEverstone(_ instanceID: String?) -> Bool {
        instanceID.map { heldItem(of: $0) == .everstone } ?? false
    }

    /// `kind` 를 `instanceID` 에 단다. 이미 다른 도구를 들고 있으면 그건 가방으로 돌아온다.
    /// 가방에 없거나 지닌 도구가 아니거나 가진 개체가 아니면 false.
    @discardableResult
    func equip(_ kind: ItemKind, to instanceID: String) -> Bool {
        kind.isEquippable && equip(inventoryKey: kind.rawValue, to: instanceID)
    }

    @discardableResult
    func equip(_ stone: MegaStone, to instanceID: String) -> Bool {
        equip(inventoryKey: stone.inventoryKey, to: instanceID)
    }

    private func equip(inventoryKey key: String, to instanceID: String) -> Bool {
        guard !isTradeLocked(instanceID), state.inventory[key, default: 0] > 0,
              state.ownedInstanceIDs.contains(instanceID) else { return false }
        if state.heldItems[instanceID] == key { return true }
        let megaBefore = megaSpriteID(ofInstance: instanceID)
        if let previous = state.heldItems[instanceID] { state.inventory[previous, default: 0] += 1 }
        state.inventory[key, default: 0] -= 1
        state.heldItems[instanceID] = key
        announceMegaChange(of: instanceID, from: megaBefore)
        reevaluateEvolution()
        return true
    }

    func megaSpriteID(ofInstance instanceID: String) -> Int? {
        let species = state.dex.first { $0.id == instanceID && $0.releasedAt == nil }?.finalID
            ?? (state.active?.profile?.instanceID == instanceID ? state.active?.currentID : nil)
        return megaSpriteID(instanceID: instanceID, speciesID: species)
    }

    func announceMegaChange(of instanceID: String, from before: Int?) {
        let after = megaSpriteID(ofInstance: instanceID)
        guard before != after, let sprite = after ?? before else { return }
        megaEvolveCounter += 1
        megaEvolveEvent = MegaEvolveEvent(id: megaEvolveCounter, kind: after == nil ? .unequip : .equip,
                                          instanceID: instanceID, megaSpriteID: sprite, at: Date())
    }

    // MARK: 메가스톤 (포켓몬마다 한 개 — 키 `mega-stone:<slug>`)

    func megaStoneCount(_ stone: MegaStone) -> Int { state.inventory[stone.inventoryKey] ?? 0 }

    /// 가방의 메가스톤 — 도감 번호 순.
    func ownedMegaStones(in category: ItemCategory? = nil) -> [(stone: MegaStone, count: Int)] {
        guard category == nil || category == .megaStone else { return [] }
        return MegaStone.all.compactMap { stone in
            let count = megaStoneCount(stone)
            return count > 0 ? (stone, count) : nil
        }
    }

    func heldMegaStone(of instanceID: String) -> MegaStone? {
        state.heldItems[instanceID].flatMap(MegaStone.stone(inventoryKey:))
    }

    /// 이 개체가 `speciesID` 로서 들고 있는 메가스톤 — 종이 맞을 때만 메가진화한다.
    func megaStone(of instanceID: String, speciesID: Int) -> MegaStone? {
        heldMegaStone(of: instanceID).flatMap { $0.speciesID == speciesID ? $0 : nil }
    }

    /// The bag plus every Pokémon holding it. The shop sells a stone only while this is zero.
    func megaStoneOwnedTotal(_ stone: MegaStone) -> Int {
        megaStoneCount(stone) + state.heldItems.values.filter { $0 == stone.inventoryKey }.count
    }

    func canBuy(_ stone: MegaStone) -> Bool {
        megaStoneOwnedTotal(stone) == 0 && availableTokens >= price(of: .megaStone(stone))
    }

    @discardableResult
    func buy(_ stone: MegaStone) -> Bool {
        guard megaStoneOwnedTotal(stone) == 0 else { return false }
        return completePurchase(key: stone.inventoryKey, count: 1, cost: price(of: .megaStone(stone)))
    }

    // MARK: 기술머신 (기술마다 한 개 — 키 `tm:<moveID>`, 소모되지 않는다)

    func ownsTM(_ moveID: Int) -> Bool { (state.inventory[MachineMove.inventoryKey(moveID)] ?? 0) > 0 }

    func tmPrice(power: Int, isWeather: Bool) -> Int {
        PokemonBalance.machinePrice(power: power, isWeather: isWeather)
    }

    func canBuyTM(power: Int, isWeather: Bool) -> Bool { availableTokens >= tmPrice(power: power, isWeather: isWeather) }

    @discardableResult
    func buyTM(moveID: Int, power: Int, isWeather: Bool) -> Bool {
        guard !ownsTM(moveID) else { return false }
        return completePurchase(key: MachineMove.inventoryKey(moveID), count: 1,
                                cost: tmPrice(power: power, isWeather: isWeather))
    }

    /// Gives the TM for free (battle rewards). False when it is already owned.
    @discardableResult
    func grantTM(moveID: Int) -> Bool {
        guard !ownsTM(moveID) else { return false }
        state.inventory[MachineMove.inventoryKey(moveID)] = 1
        save()
        return true
    }

    /// 상점 메가스톤 목록 — 가진 포켓몬의 돌이 먼저, 나머지는 도감 번호 순.
    var megaStoneShopEntries: [ShopEntry] {
        let owned = state.ownedSpeciesIDs
        let (mine, others) = (MegaStone.all.filter { owned.contains($0.speciesID) }, MegaStone.all.filter { !owned.contains($0.speciesID) })
        let crystal = ShopEntry.item(.stellarCrystal)
        let stones = (mine + others).map(ShopEntry.megaStone)
        let crystalIndex = owned.contains(TeraForm.terapagos) ? mine.count : stones.count
        return Array(stones[..<crystalIndex]) + [crystal] + Array(stones[crystalIndex...])
    }

    /// 홈·플로팅 펫·메뉴바가 그릴 메가 스프라이트 id. 표시만 바꾼다 — 종·레벨·저장 데이터는 그대로다.
    func megaSpriteID(instanceID: String?, speciesID: Int?) -> Int? {
        guard let instanceID, let speciesID else { return nil }
        return megaStone(of: instanceID, speciesID: speciesID)?.spriteID
            ?? teraForm(of: instanceID, speciesID: speciesID)?.id
    }

    /// The form a mask or the Stellar Crystal gives this individual — only on its own species.
    func teraForm(of instanceID: String, speciesID: Int) -> TeraForm.Sprite? {
        guard let kind = heldItem(of: instanceID), kind.holderSpeciesID == speciesID else { return nil }
        return kind.formSprite
    }

    /// The bag plus every Pokémon holding it.
    func itemOwnedTotal(_ kind: ItemKind) -> Int {
        if kind == .expShare { return itemCount(kind) + state.expShareHolders.count }
        return itemCount(kind) + state.heldItems.values.filter { $0 == kind.rawValue }.count
    }

    /// An item the shop sells once: a bought passive item, or a single-copy item that is in the bag or on a holder.
    func isSoldOut(_ kind: ItemKind) -> Bool {
        (kind.isBoughtOnce && itemCount(kind) > 0) || (kind.isSingleCopy && itemOwnedTotal(kind) > 0)
            || (kind == .expShare && itemOwnedTotal(kind) >= ExpShare.maxOwned)
    }

    /// 그 종의 개체 중 맞는 메가스톤을 든 개체가 있으면 그 메가 스프라이트 id.
    func megaSpriteID(forSpecies speciesID: Int) -> Int? {
        var holders = state.dex.filter { $0.releasedAt == nil && $0.finalID == speciesID }.map(\.id)
        if state.active?.currentID == speciesID, let id = state.active?.profile?.instanceID { holders.append(id) }
        return holders.lazy.compactMap { self.megaSpriteID(instanceID: $0, speciesID: speciesID) }.first
    }

    /// 지금 키우는 개체가 메가진화 중으로 보일 때의 스프라이트 id.
    var currentMegaSpriteID: Int? {
        megaSpriteID(instanceID: raisedGraduate?.id ?? state.active?.profile?.instanceID, speciesID: currentSpeciesID)
    }

    @discardableResult
    func unequip(from instanceID: String) -> Bool {
        guard !isTradeLocked(instanceID), let key = state.heldItems[instanceID] else { return false }
        let megaBefore = megaSpriteID(ofInstance: instanceID)
        state.inventory[key, default: 0] += 1
        state.heldItems[instanceID] = nil
        announceMegaChange(of: instanceID, from: megaBefore)
        if key == ItemKind.everstone.rawValue { reevaluateEvolution() } else { save() }
        return true
    }

    /// 가방에 아이템이 있는 분류 — 빈 분류는 탭에서 숨긴다.
    var bagCategories: [ItemCategory] {
        var present = Set(ownedItems.map { $0.kind.category })
        if !ownedScoutTickets.isEmpty { present.insert(.scout) }
        if !ownedPrizeEggs.isEmpty { present.insert(.egg) }
        if !ownedMegaStones().isEmpty { present.insert(.megaStone) }
        if !ownedBattleSections.isEmpty { present.insert(.heldItem) }
        return ItemCategory.allCases.filter(present.contains)
    }

    /// 이상한 사탕 사용 가능 — 활성 포켓몬 + 라인 로딩 완료 + 재고>0.
    /// 라인 미로딩(재시작 직후·오프라인)이면 비활성 — 사탕이 진화 없이 적립만 되는 것 방지.
    var canUseRareCandy: Bool { maxRareCandyUseCount > 0 }

    /// Use the same rounded thresholds as actual growth.
    /// Preview the apparent evolution path so hidden identities cannot change the picker.
    private var rareCandyStageCosts: [Int] {
        guard var mon = state.active, !isLineParked, currentLine != nil else { return [] }
        if mon.dittoDisguise != nil && !mon.dittoRevealed && mon.usedAtStage >= stageThreshold(for: mon) {
            // The accepted batch is already saved. Wait for the reveal before accepting another.
            return []
        }
        return (mon.stageIndex..<mon.totalForms).map { stage in
            mon.stageIndex = stage
            return stageThreshold(for: mon)
        }
    }

    var maxRareCandyUseCount: Int {
        let remaining = max(0, rareCandyStageCosts.reduce(0, +) - (state.active?.usedAtStage ?? 0))
        let needed = remaining / RareCandy.xp + (remaining % RareCandy.xp == 0 ? 0 : 1)
        return min(rareCandyCount, needed)
    }

    struct RareCandyUsePlan {
        let count: Int
        var xp: Int { count * RareCandy.xp }
        let evolves: Bool
        let graduates: Bool
        let carryoverXP: Int
        let discardedXP: Int
    }

    func planRareCandyUse(count requested: Int) -> RareCandyUsePlan? {
        let count = min(max(0, requested), maxRareCandyUseCount)
        guard count > 0, let mon = state.active else { return nil }
        let costs = rareCandyStageCosts
        var remaining = mon.usedAtStage + count * RareCandy.xp
        var evolves = false
        for (index, cost) in costs.enumerated() {
            guard remaining >= cost else { break }
            remaining -= cost
            if index == costs.count - 1 {
                return RareCandyUsePlan(count: count, evolves: evolves, graduates: true,
                                       carryoverXP: 0, discardedXP: remaining)
            }
            evolves = true
        }
        return RareCandyUsePlan(count: count, evolves: evolves, graduates: false,
                               carryoverXP: evolves ? remaining : 0, discardedXP: 0)
    }

    /// 사탕 사용 결과 — UI 피드백 분기용.
    enum CandyUseResult: Equatable { case evolved, graduated, progressed, unavailable }

    /// How many Exp. Share holders would split a batch's XP past graduation.
    var candyLeftoverRecipientCount: Int { expShareRecipients().count }

    /// The Bag's line about a batch's XP past graduation; `wasted` when no holder takes it.
    func candyLeftoverLine(for plan: RareCandyUsePlan) -> (text: String, wasted: Bool)? {
        guard plan.discardedXP > 0 else { return nil }
        let xp = TokenFormatter.compact(plan.discardedXP)
        let holders = candyLeftoverRecipientCount
        return holders > 0 ? (l.candyLeftoverToExpShare(xp, holders: holders), false) : (l.candyDiscardedXP(xp), true)
    }

    /// The home line under the graduation banner when the graduation shared its leftover.
    var graduationLeftoverLine: String? {
        guard justGraduated != nil, let shared = graduationLeftoverShared else { return nil }
        return l.leftoverShared(TokenFormatter.compact(shared.xp), holders: shared.holders)
    }

    /// Spend only the candies needed by the current growth plan, preserving unused inventory.
    /// 사탕 XP 는 usedAtStage(진화 진행)에만 반영 — usedSinceInstall/오늘 토큰(실사용 통계)엔 안 잡힌다.
    @discardableResult
    func useRareCandy(count: Int = 1) -> CandyUseResult {
        guard let preview = planRareCandyUse(count: count) else { return .unavailable }
        var consumed = preview.count
        if let mon = state.active, mon.dittoDisguise != nil && !mon.dittoRevealed {
            // Keep the picker indistinguishable from the apparent Pokémon, but preserve whole
            // candies beyond the surprise reveal. Only the last consumed candy's XP carries over.
            let remaining = max(0, stageThreshold(for: mon) - mon.usedAtStage)
            let needed = remaining / RareCandy.xp + (remaining % RareCandy.xp == 0 ? 0 : 1)
            consumed = min(consumed, needed)
        }
        let xp = consumed * RareCandy.xp
        state.inventory[ItemKind.rareCandy.rawValue] = rareCandyCount - consumed
        let beforeStage = state.active?.stageIndex ?? 0
        state.active?.evolution.candies += consumed
        // 진화 안 될 때(부분 진행)도 즉시 "+XP" 피드백 — CompanionHeader 가 연출과 별개로 표시.
        candyFeedbackAmount = xp
        candyFeedbackSeq += 1
        applyUsage(xp)   // Saves inventory and growth together, with existing evolution effects.
        if state.active == nil { return .graduated }
        if state.active!.stageIndex > beforeStage { return .evolved }
        return .progressed
    }
}
