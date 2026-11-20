import Foundation

extension CompanionStore {
    var remoteSnapshot: RemoteSnapshot {
        RemoteSnapshot(wallet: availableTokens, bag: remoteBag, shop: remoteShop)
    }

    /// The bag as the bot shows it, with Korean names (the bot speaks Korean). Held items are on their holders.
    var remoteBag: [RemoteBagLine] {
        let ko = L(.ko)
        var lines = ownedItems.map { RemoteBagLine(key: $0.kind.rawValue, name: ko.itemName($0.kind), count: $0.count) }
        lines += ownedMegaStones().map {
            RemoteBagLine(key: $0.stone.inventoryKey, name: ko.megaStoneName($0.stone), count: $0.count)
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
                                  category: kind.category.rawValue, single: kind.isBoughtOnce || kind.isSingleCopy)
        }
        lines += MegaStone.all.filter { megaStoneOwnedTotal($0) == 0 }.map {
            RemoteShopLine(key: $0.inventoryKey, name: ko.megaStoneName($0), price: price(of: .megaStone($0)),
                           category: ItemCategory.megaStone.rawValue, single: true)
        }
        lines += machineShopMoves().filter { !ownsTM($0.id) }.map {
            RemoteShopLine(key: MachineMove.inventoryKey($0.id), name: "\(ko.moveGroupMachine) \($0.name(.ko))",
                           price: tmPrice(power: $0.power, isWeather: $0.isWeather),
                           category: ItemCategory.machine.rawValue, single: true)
        }
        lines += ScoutPool.all.map {
            RemoteShopLine(key: $0.inventoryKey, name: ko.scoutTicketName($0), price: scoutPrice,
                           category: ItemCategory.scout.rawValue, single: false)
        }
        return lines
    }
}
