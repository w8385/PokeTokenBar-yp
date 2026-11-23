import Foundation

extension CompanionStore {
    // MARK: 상점 (재화 = 사용한 토큰)

    /// 상점 판매 아이템 — shopPrice 있는 것만. 가격 저렴한 순, 단 구매 완료한 보유형은 맨 아래로.
    var purchasableItems: [ItemKind] {
        let sold = ItemKind.listOrder
            .filter { $0.shopPrice != nil && !$0.isEvolutionStone && !$0.isEvolutionHeld && !$0.isLinkingCord
                && $0.category != .megaStone }
        return shopOrdered(sold.map { ShopEntry.item($0) }).compactMap { entry in
            if case .item(let kind) = entry { kind } else { nil }
        }
    }

    /// Price order, except that a family (`ItemKind.shopFamilies`) stays together where its cheapest member would sit,
    /// the members in table order. Price ties and the order inside a family follow the order `entries` come in.
    /// A bought-once item already owned (the Shiny Charm) goes last: it cannot be bought again.
    private func shopOrdered(_ entries: [ShopEntry]) -> [ShopEntry] {
        func family(_ entry: ShopEntry) -> Int? {
            if case .item(let kind) = entry { kind.shopFamily } else { nil }
        }
        var cheapest: [Int: (price: Int, index: Int)] = [:]
        for (index, entry) in entries.enumerated() {
            guard let id = family(entry) else { continue }
            let known = cheapest[id] ?? (entry.price, index)
            cheapest[id] = (min(known.price, entry.price), min(known.index, index))
        }
        let keys = entries.enumerated().map { index, entry -> [Int] in
            let anchor = family(entry).flatMap { cheapest[$0] } ?? (entry.price, index)
            return [isPurchasedPassive(entry) ? 1 : 0, anchor.price, anchor.index, index]
        }
        return entries.indices.sorted { keys[$0].lexicographicallyPrecedes(keys[$1]) }.map { entries[$0] }
    }

    /// Every battle item by effect group. Metal Coat, Razor Claw and the Stellar Crystal also stay in their own tab.
    var shopBattleSections: [BattleItemSection] { BattleItemGroup.sections(of: ItemKind.listOrder) }

    /// 상점 "진화" 구역의 돌 — 별도 구역이라 `shopEntries` 의 가격순 목록에는 넣지 않는다.
    var evolutionStoneItems: [ItemKind] { ItemKind.listOrder.filter(\.isEvolutionStone) }

    /// The shop's evolution section: what is used up, the Linking Cord, then what is held.
    var shopEvolutionItems: [ItemKind] {
        ItemKind.listOrder.filter { $0.isEvolutionStone || $0.isLinkingCord || $0.isEvolutionHeld }
    }

    /// The evolution section of the all view; battle items are already listed in `shopBattleSections` there.
    var shopAllViewEvolutionItems: [ItemKind] { shopEvolutionItems.filter { $0.battleGroup == nil } }

    /// 상점 표시 순서 — 판매 아이템 + 알 3종을 하나의 가격 오름차순 목록으로 병합.
    /// 정렬 규칙은 purchasableItems 와 동일(`shopOrdered`): 구매 완료한 보유형은 맨 아래, 나머지는 가격 저렴한 순이고
    /// 가족(특성캡슐·특성패치, 은색·금색 병뚜껑 등)은 가장 싼 멤버 자리에 붙는다.
    /// 알은 즉시 액션이라 '보유' 개념이 없어 가격 순서에만 참여한다.
    ///
    /// 알은 활성 포켓몬이 없어도(알 상태) 목록에 남는다 — 구매는 `canBuyEgg` 의 `hasActive` 게이트가
    /// 막고, EggCard 가 비활성 버튼 + 사유 한 줄로 보여준다. 목록에서 통째로 빼면 "상점에 알이 원래
    /// 없다"로 읽혀서, 게이트는 유지하되 존재는 계속 보이게 한다.
    ///
    /// 등급 알끼리 붙여 '티어 사다리'로 묶어 보이게 하는 안도 검토했으나 채택하지 않았다 — 지금의 순수
    /// 가격 오름차순은 "알이 무조건 맨 아래로 append 돼 더 비싼 부적보다 아래에 놓이던" 표시 회귀를
    /// 고치며 들어온 규칙이라(ShopTests 참조), 그룹 배치는 그 회귀를 부분적으로 되살린다. 티어 관계는
    /// 카드의 등급 배지로 읽히게 한다.
    var shopEntries: [ShopEntry] {
        var entries: [ShopEntry] = purchasableItems.map { ShopEntry.item($0) }
        entries += FreshEgg.shopTiers.map { ShopEntry.egg($0) }
        return shopOrdered(entries)
    }

    /// 분류 탭 필터 — nil 은 전체. 순서는 shopEntries 그대로다(가격 오름차순 규칙 유지). 진화의 돌은
    /// 별도 구역(`evolutionStoneItems`)이라 여기에 없다.
    func shopEntries(in category: ItemCategory?) -> [ShopEntry] {
        guard let category else { return shopEntries }
        if category == .megaStone { return megaStoneShopEntries }
        return shopEntries.filter { $0.category == category }
    }

    /// 상점에 항목이 있는 분류 — 빈 분류는 탭에서 숨긴다. 메가스톤 92개·기술머신은 전체 목록에 넣지 않고 각자 탭에서만 판다.
    var shopCategories: [ItemCategory] {
        let present = Set(shopEntries.map(\.category)).union(evolutionStoneItems.map(\.category))
            .union([.scout, .megaStone, .machine])
        return ItemCategory.allCases.filter(present.contains)
    }

    /// 구매 완료한 보유형(이로치 부적 등)인지 — shopEntries 정렬에서 맨 아래로 보낼 판정.
    private func isPurchasedPassive(_ entry: ShopEntry) -> Bool {
        guard case .item(let kind) = entry else { return false }   // 알은 즉시 액션 — 보유 개념 없음
        return kind.isBoughtOnce && itemCount(kind) > 0
    }

    /// 구매 가능 — 잔액이 그 아이템 가격 이상(상점 미판매면 false). 활성/알 무관(재고는 미리 쌓아둘 수 있음).
    func canBuy(_ kind: ItemKind) -> Bool {
        guard let price = price(of: kind) else { return false }
        if isSoldOut(kind) { return false }   // 보유형·단품은 1회만(재구매 불가)
        return availableTokens >= price
    }

    /// 한 번에 살 수 있는 최대 개수 — 잔액 ÷ 가격. 보유형은 1회 구매라 최대 1, 이미 보유했거나
    /// 미판매·잔액 부족이면 0.
    func maxBuyCount(_ kind: ItemKind) -> Int {
        guard canBuy(kind), let price = price(of: kind), price > 0 else { return 0 }
        return kind.isBoughtOneAtATime ? 1 : availableTokens / price
    }

    /// 아이템 count 개 구매 — 지갑에서 price × count 차감, 인벤토리 +count. usedSinceInstall(성장·통계)·
    /// 진화 진행엔 무영향(지출 원장만 증가). 잔액 부족/미판매/범위 밖 개수면 부분 구매 없이 no-op(false).
    @discardableResult
    func buy(_ kind: ItemKind, count: Int = 1) -> Bool {
        guard count >= 1, count <= maxBuyCount(kind), let price = price(of: kind) else { return false }
        return completePurchase(key: kind.rawValue, count: count, cost: price * count)
    }

    // MARK: 구매 되돌리기 (확인창 대신 5초 안에 취소)

    func completePurchase(key: String, count: Int, cost: Int) -> Bool {
        guard spend(cost) else { return false }
        state.inventory[key, default: 0] += count
        purchaseReceipts[key] = PurchaseReceipt(inventoryKey: key, count: count, cost: cost,
                                                expiresAt: clock().addingTimeInterval(PurchaseReceipt.window))
        save()
        return true
    }

    /// Undo is open while the window lasts and the bought copies are still in the bag — an item that was
    /// equipped, used or traded away in the meantime cannot be refunded.
    func canUndo(_ receipt: PurchaseReceipt) -> Bool {
        clock() < receipt.expiresAt && purchaseReceipts[receipt.inventoryKey] == receipt
            && state.inventory[receipt.inventoryKey, default: 0] >= receipt.count
    }

    /// Gives the exact cost back and takes the copies out of the bag. False (nothing changes) when `canUndo` is false.
    @discardableResult
    func undoPurchase(_ receipt: PurchaseReceipt) -> Bool {
        guard canUndo(receipt) else { return false }
        refund(receipt.cost)
        let left = state.inventory[receipt.inventoryKey, default: 0] - receipt.count
        state.inventory[receipt.inventoryKey] = left > 0 ? left : nil
        purchaseReceipts[receipt.inventoryKey] = nil
        save()
        return true
    }

    func dismissReceipt(_ receipt: PurchaseReceipt) {
        if purchaseReceipts[receipt.inventoryKey] == receipt { purchaseReceipts[receipt.inventoryKey] = nil }
    }

    // 사탕 전용 래퍼 — 기존 호출부/테스트 호환.
    var canBuyRareCandy: Bool { canBuy(.rareCandy) }
    @discardableResult
    func buyRareCandy() -> Bool { buy(.rareCandy) }
}
