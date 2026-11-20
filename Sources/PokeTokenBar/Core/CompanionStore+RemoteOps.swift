import Foundation

extension CompanionStore {
    var remoteSnapshot: RemoteSnapshot {
        RemoteSnapshot(wallet: availableTokens, bag: remoteBag, shop: remoteShop)
    }

    /// The bag as the bot shows it, with Korean names (the bot speaks Korean). Held items are on their holders.
    var remoteBag: [RemoteBagLine] {
        let ko = L(.ko)
        var lines = ownedItems.map {
            RemoteBagLine(key: $0.kind.rawValue, name: ko.itemName($0.kind), count: $0.count,
                          equip: $0.kind.isEquippable ? true : nil, heldItem: $0.kind.heldItemSlug)
        }
        lines += ownedMegaStones().map {
            RemoteBagLine(key: $0.stone.inventoryKey, name: ko.megaStoneName($0.stone), count: $0.count,
                          equip: true, heldItem: $0.stone.slug)
        }
        lines += ownedScoutTickets.map {
            RemoteBagLine(key: $0.pool.inventoryKey, name: ko.scoutTicketName($0.pool), count: $0.count)
        }
        lines += ownedPrizeEggs.map {
            RemoteBagLine(key: HiddenBossPrize.eggKey($0.speciesID), name: ko.prizeEggName($0.speciesID), count: $0.count)
        }
        let machines = MachineMove.ownedIDs(in: state.inventory)
        lines += MachineCatalog.moves.filter { machines.contains($0.id) }.map {
            RemoteBagLine(key: MachineMove.inventoryKey($0.id), name: "\(ko.moveGroupMachine) \($0.name(.ko))", count: 1)
        }
        return lines
    }

    /// What the shop screen sells now at this app's prices: items not sold out, mega stones not owned, TMs not owned
    /// and scout tickets. Eggs are left out: buying one replaces the Pokémon being raised.
    var remoteShop: [RemoteShopLine] {
        let ko = L(.ko)
        var listed = shopEntries(in: nil).compactMap { entry -> ItemKind? in
            if case .item(let kind) = entry { return kind }
            return nil
        }
        listed += shopBattleSections.flatMap(\.kinds) + shopEvolutionItems
        listed += megaStoneShopEntries.compactMap { entry -> ItemKind? in
            if case .item(let kind) = entry { return kind }
            return nil
        }
        var seen = Set<ItemKind>()
        var lines: [RemoteShopLine] = listed.compactMap { kind in
            guard seen.insert(kind).inserted, let price = price(of: kind), !isSoldOut(kind) else { return nil }
            return RemoteShopLine(key: kind.rawValue, name: ko.itemName(kind), price: price,
                                  category: kind.category.rawValue, categoryName: ko.categoryName(kind.category),
                                  single: kind.isBoughtOneAtATime, equip: kind.isEquippable ? true : nil,
                                  heldItem: kind.heldItemSlug)
        }
        lines += MegaStone.all.filter { megaStoneOwnedTotal($0) == 0 }.map {
            RemoteShopLine(key: $0.inventoryKey, name: ko.megaStoneName($0), price: price(of: .megaStone($0)),
                           category: ItemCategory.megaStone.rawValue, categoryName: ko.categoryName(.megaStone),
                           single: true, equip: true, heldItem: $0.slug)
        }
        lines += machineShopMoves().filter { !ownsTM($0.id) }.map {
            RemoteShopLine(key: MachineMove.inventoryKey($0.id), name: "\(ko.moveGroupMachine) \($0.name(.ko))",
                           price: tmPrice(power: $0.power, isWeather: $0.isWeather),
                           category: ItemCategory.machine.rawValue, categoryName: ko.categoryName(.machine), single: true)
        }
        lines += ScoutPool.all.map {
            RemoteShopLine(key: $0.inventoryKey, name: ko.scoutTicketName($0), price: scoutPrice,
                           category: ItemCategory.scout.rawValue, categoryName: ko.categoryName(.scout), single: false)
        }
        return lines
    }

    /// Buys `count` of what the shop sells under an inventory key through the shop's own purchase, without the undo
    /// a purchase on the shop screen offers. False when nothing was bought.
    func buyFromShop(_ key: String, count: Int) -> Bool {
        let bought: Bool
        if let kind = ItemKind(rawValue: key) {
            bought = buy(kind, count: count)
        } else if let stone = MegaStone.stone(inventoryKey: key) {
            bought = count == 1 && buy(stone)
        } else if let move = machineShopMoves().first(where: { MachineMove.inventoryKey($0.id) == key }) {
            bought = count == 1 && buyTM(moveID: move.id, power: move.power, isWeather: move.isWeather)
        } else if let pool = ScoutPool.all.first(where: { $0.inventoryKey == key }), availableTokens >= scoutPrice * count {
            bought = (0..<count).allSatisfy { _ in buyScoutTicket(pool) }
        } else {
            bought = false
        }
        if bought, let receipt = purchaseReceipts[key] { dismissReceipt(receipt) }
        return bought
    }
}
