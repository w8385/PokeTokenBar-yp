import XCTest
@testable import PokeTokenBar

private struct OrderProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 4, tree: EvoNode(speciesID: 4, children: []), rarity: .common, names: [4: ["en": "Charmander"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class ItemOrderTests: XCTestCase {
    private let order = ItemKind.listOrder

    func testEveryItemHasExactlyOnePlace() {
        XCTAssertEqual(order.count, ItemKind.allCases.count, "an item is listed twice or not at all")
        XCTAssertEqual(Set(order), Set(ItemKind.allCases))
        XCTAssertEqual(order.map(\.listRank), Array(order.indices))
    }

    func testTheTableReadsLikeTheScreenTabsThenHeldItemSections() {
        let plain = order.prefix { $0.battleGroup == nil }
        XCTAssertEqual(order.filter { $0.battleGroup == nil }, Array(plain), "plain items come before every held section")
        let tabs = plain.map { ItemCategory.allCases.firstIndex(of: $0.category)! }
        XCTAssertEqual(tabs, tabs.sorted(), "plain items follow the tab order")
        let groups = order.compactMap(\.battleGroup).map { BattleItemGroup.allCases.firstIndex(of: $0)! }
        XCTAssertEqual(groups, groups.sorted(), "held items follow the section order")
    }

    func testRelatedItemsSitNextToEachOther() {
        let families: [(String, [ItemKind])] = [
            ("stones", ItemKind.allCases.filter { $0.rawValue.hasSuffix("Stone") && $0.isEvolutionStone }),
            ("Choice Band and Specs", [.choiceBand, .choiceSpecs]),
            ("scrolls", [.scrollOfDarkness, .scrollOfWaters]),
            ("apples", [.tartApple, .sweetApple, .syrupyApple]),
            ("pots", [.crackedPot, .chippedPot]), ("teacups", [.unremarkableTeacup, .masterpieceTeacup]),
            ("Galarica", [.galaricaCuff, .galaricaWreath]), ("armors", [.auspiciousArmor, .maliciousArmor]),
            ("bottle caps", ItemKind.bottleCaps), ("ability items", ItemKind.abilityItems),
            ("form key items", ItemKind.formTools),
            ("type items", ItemKind.allCases.filter { $0.boostedType != nil }),
            ("plates", ItemKind.plates), ("gems", ItemKind.gems), ("incenses", ItemKind.typeIncenses),
            ("resist berries", ItemKind.resistBerries), ("cure berries", ItemKind.cureBerries),
            ("flavor berries", ItemKind.flavorBerries), ("power items", ItemKind.powerItems),
            ("memories", ItemKind.memories), ("drives", ItemKind.drives), ("terrain seeds", ItemKind.terrainSeeds),
            ("hit items", ItemKind.hitStatItems), ("weather rocks", [.heatRock, .dampRock, .smoothRock, .icyRock]),
            ("masks", [.tealMask, .wellspringMask, .hearthflameMask, .cornerstoneMask]),
            ("Primal orbs", ItemKind.primalOrbs), ("rusted weapons", ItemKind.crownedItems),
            ("Deep Sea items", [.deepSeaTooth, .deepSeaScale]), ("Metal and Quick Powder", [.metalPowder, .quickPowder]),
        ]
        for (name, family) in families {
            let ranks = family.map(\.listRank).sorted()
            XCTAssertEqual(ranks.last! - ranks.first!, family.count - 1, "\(name) are split")
        }
    }

    func testTypedFamiliesFollowTheTypeChart() {
        let chart = PokemonType.allCases.map(\.rawValue)
        let keys: [(String, (ItemKind) -> String?)] = [
            ("type items", \.boostedType), ("plates", \.plateType), ("gems", \.gemType), ("incenses", \.incenseType),
            ("resist berries", \.resistedType), ("memories", \.memoryType),
        ]
        for (name, key) in keys {
            let types = order.compactMap(key).map { chart.firstIndex(of: $0)! }
            XCTAssertEqual(types, types.sorted(), name)
            XCTAssertFalse(types.isEmpty, name)
        }
    }

    func testSignatureItemsFollowThePokedex() {
        let signature = order.filter { $0.battleGroup == .signature }
        let dex: [ItemKind: Int] = [.stick: 83, .thickClub: 104, .deepSeaTooth: 366, .deepSeaScale: 366, .soulDew: 380]
        let numbers = signature.map { $0.holderSpeciesID ?? dex[$0] ?? -1 }
        XCTAssertFalse(numbers.contains(-1), "every signature item names its species")
        XCTAssertEqual(numbers, numbers.sorted())
    }

    func testEveryItemListFollowsTheTable() throws {
        let store = try makeStore(inventory: Dictionary(uniqueKeysWithValues: ItemKind.allCases.map { ($0, 1) }))
        func assertInOrder(_ kinds: [ItemKind], _ name: String) {
            XCTAssertFalse(kinds.isEmpty, name)
            XCTAssertEqual(kinds.map(\.listRank), kinds.map(\.listRank).sorted(), name)
        }
        assertInOrder(store.ownedItems.map(\.kind), "bag")
        for category in ItemCategory.allCases {
            let kinds = store.bagListItems(in: category).map(\.kind)
            if !kinds.isEmpty { assertInOrder(kinds, "bag \(category)") }
        }
        assertInOrder(store.shopEvolutionItems, "shop evolution section")
        assertInOrder(store.shopAllViewEvolutionItems, "shop all view evolution section")
        assertInOrder(store.shopBattleSections.flatMap(\.kinds), "shop held sections")
        assertInOrder(store.ownedBattleSections.flatMap(\.kinds), "bag held sections")
        assertInOrder(store.equippableBagItems.compactMap { if case .item(let kind) = $0 { kind } else { nil } },
                      "Box held-item picker")
        assertInOrder(store.remoteBag.compactMap { ItemKind(rawValue: $0.key) }, "bag sent to the bot")
    }

    func testTheShopsMainListKeepsFamiliesTogetherAndTiesInTableOrder() throws {
        let kinds = try makeStore(inventory: [:]).purchasableItems
        for family in ItemKind.shopFamilies {
            let places = kinds.indices.filter { family.contains(kinds[$0]) }
            XCTAssertEqual(places.map { kinds[$0] }, family, "\(family) are split or out of table order")
            XCTAssertEqual(places.last! - places.first!, family.count - 1, "\(family) are split")
        }
        let plain = kinds.filter { $0.shopFamily == nil }
        for (a, b) in zip(plain, plain.dropFirst()) where a.shopPrice == b.shopPrice {
            XCTAssertLessThan(a.listRank, b.listRank, "\(a) before \(b)")
        }
    }

    private func makeStore(inventory: [ItemKind: Int]) throws -> CompanionStore {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("item-order-\(UUID()).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        var state = CompanionState()
        state.language = .en
        state.inventory = Dictionary(uniqueKeysWithValues: inventory.map { ($0.key.rawValue, $0.value) })
        try JSONEncoder().encode(state).write(to: file)
        return CompanionStore(provider: OrderProvider(), fileURL: file)
    }
}
