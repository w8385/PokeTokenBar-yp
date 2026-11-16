import XCTest
@testable import PokeTokenBar

private struct TypedProvider: PokeProviding, PokemonDetailProviding {
    static let types: [Int: [String]] = [25: ["electric"], 6: ["fire", "flying"], 95: ["rock", "ground"], 133: ["normal"]]

    func line(baseSpeciesID: Int) async throws -> EvoLine { try await BoxDexProvider().line(baseSpeciesID: baseSpeciesID) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        try SpeciesFacts.details(speciesID)
    }
}

private final class TestClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

@MainActor
final class BoxFilterAndUndoTests: XCTestCase {
    private let ids = (raised: BoxDexFixture.raisedID, pikachu: BoxDexFixture.pikachuID,
                       charizard: BoxDexFixture.charizardID, onix: BoxDexFixture.onixID, eevee: BoxDexFixture.eeveeID)

    private func makeStore(clock: TestClock = TestClock()) async throws -> CompanionStore {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("box-filter-\(UUID()).json")
        try JSONEncoder().encode(BoxDexFixture.state(language: .en)).write(to: file)
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        let store = CompanionStore(provider: TypedProvider(), clock: { clock.now }, fileURL: file)
        for id in TypedProvider.types.keys { await store.loadPokemonDetails(speciesID: id) }
        return store
    }

    private func result(_ store: CompanionStore, _ configure: (inout BoxFilter) -> Void,
                        fighting: Set<String> = []) -> Set<String> {
        var filter = BoxFilter()
        configure(&filter)
        return Set(store.filteredBoxIndividuals(filter: filter, fightingIDs: fighting).map(\.id))
    }

    // MARK: Box filters

    func testTypeFilterMatchesAnyPickedTypeOfEitherSlot() async throws {
        let store = try await makeStore()
        XCTAssertEqual(result(store) { $0.types = [.fire] }, [ids.charizard])
        XCTAssertEqual(result(store) { $0.types = [.flying] }, [ids.charizard], "the second type counts")
        XCTAssertEqual(result(store) { $0.types = [.electric, .rock] }, [ids.pikachu, ids.onix], "any of the picked types")
        XCTAssertEqual(result(store) { $0.types = [.dragon] }, [])
    }

    func testRarityFilter() async throws {
        let store = try await makeStore()
        XCTAssertEqual(result(store) { $0.rarity = .rare }, [ids.pikachu, ids.charizard, ids.onix, ids.eevee])
        XCTAssertEqual(result(store) { $0.rarity = .legendary }, [])
        XCTAssertFalse(result(store) { $0.rarity = .common }.contains(ids.pikachu))
    }

    func testLevelFilterSplitsAtFifty() async throws {
        let store = try await makeStore()
        XCTAssertEqual(result(store) { $0.level = .fiftyPlus }, [ids.charizard])
        XCTAssertEqual(result(store) { $0.level = .underFifty }, [ids.raised, ids.pikachu, ids.onix, ids.eevee])
        XCTAssertEqual(result(store) { $0.level = .any }.count, 5)
    }

    func testLineupFilterUsesTheBattleLineup() async throws {
        let store = try await makeStore()
        XCTAssertEqual(result(store, { $0.inLineupOnly = true }, fighting: [ids.pikachu, ids.eevee]),
                       [ids.pikachu, ids.eevee])
        XCTAssertEqual(result(store, { $0.inLineupOnly = true }), [], "nobody in the lineup, nobody listed")
    }

    func testTradableFilterDropsRaisedFightingAndLocked() async throws {
        let store = try await makeStore()
        store.lockForTrade(ids.eevee)
        let tradable = result(store, { $0.tradableOnly = true }, fighting: [ids.pikachu])
        XCTAssertEqual(tradable, [ids.charizard, ids.onix])
    }

    func testFiltersCombine() async throws {
        let store = try await makeStore()
        XCTAssertEqual(result(store) { $0.types = [.fire, .electric]; $0.level = .fiftyPlus }, [ids.charizard])
        XCTAssertEqual(result(store) { $0.shinyOnly = true; $0.level = .underFifty; $0.rarity = .rare }, [ids.pikachu])
        XCTAssertEqual(result(store, { $0.hasItemOnly = true; $0.tradableOnly = true }, fighting: [ids.pikachu]),
                       [ids.charizard])
        let searched = store.filteredBoxIndividuals(query: "Pika", filter: {
            var f = BoxFilter(); f.types = [.electric]; return f
        }())
        XCTAssertEqual(searched.map(\.id), [ids.pikachu])
        XCTAssertEqual(result(store) { $0.types = [.fire]; $0.level = .underFifty }, [], "an empty intersection stays empty")
    }

    // MARK: Persistence

    private func defaults() throws -> UserDefaults {
        let suite = "box-filter-tests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testSortAndFiltersSurviveARelaunchButTheSearchTextDoesNot() throws {
        let defaults = try defaults()
        let first = BoxFilterStore(defaults: defaults)
        first.filter.sort = .level
        first.filter.shinyOnly = true
        first.filter.types = [.fire, .water]
        first.filter.rarity = .rare
        first.filter.tradableOnly = true
        first.filter.level = .fiftyPlus
        first.searchText = "char"

        let second = BoxFilterStore(defaults: defaults)
        XCTAssertEqual(second.filter, first.filter)
        XCTAssertEqual(second.searchText, "")
    }

    func testClearResetsEverythingIncludingTheStoredCopy() throws {
        let defaults = try defaults()
        let store = BoxFilterStore(defaults: defaults)
        store.filter.sort = .name
        store.filter.types = [.ghost]
        store.searchText = "x"
        store.clear()
        XCTAssertEqual(store.filter, BoxFilter())
        XCTAssertEqual(store.searchText, "")
        XCTAssertEqual(BoxFilterStore(defaults: defaults).filter, BoxFilter())
    }

    func testUnreadableStoredFilterFallsBackToDefaults() throws {
        let defaults = try defaults()
        defaults.set(Data("not json".utf8), forKey: BoxFilterStore.defaultsKey)
        XCTAssertEqual(BoxFilterStore(defaults: defaults).filter, BoxFilter())
        defaults.set(Data(#"{"sort":"future-option","shinyOnly":true}"#.utf8), forKey: BoxFilterStore.defaultsKey)
        let partial = BoxFilterStore(defaults: defaults).filter
        XCTAssertEqual(partial.sort, .recent)
        XCTAssertTrue(partial.shinyOnly)
    }

    func testSearchTextAndFiltersSurviveATabSwitch() {
        let navigation = PopoverNavigation()
        navigation.tab = .box
        navigation.boxFilters.searchText = "pika"
        navigation.tab = .shop
        navigation.tab = .box
        XCTAssertEqual(navigation.boxFilters.searchText, "pika")
    }

    // MARK: One-tap buy and undo

    private func candyReceipt(_ store: CompanionStore) throws -> PurchaseReceipt {
        XCTAssertTrue(store.buy(.rareCandy, count: 2))
        return try XCTUnwrap(store.purchaseReceipts[ItemKind.rareCandy.rawValue])
    }

    func testUndoRefundsExactlyAndRemovesTheItems() async throws {
        let store = try await makeStore()
        let (spent, tokens, owned) = (store.state.spentTokens, store.availableTokens, store.itemCount(.rareCandy))
        let receipt = try candyReceipt(store)
        XCTAssertEqual(store.itemCount(.rareCandy), owned + 2)
        XCTAssertEqual(receipt.cost, (store.price(of: .rareCandy) ?? 0) * 2)

        XCTAssertTrue(store.undoPurchase(receipt))
        XCTAssertEqual(store.state.spentTokens, spent)
        XCTAssertEqual(store.availableTokens, tokens)
        XCTAssertEqual(store.itemCount(.rareCandy), owned)
        XCTAssertNil(store.state.inventory[ItemKind.rareCandy.rawValue], "a row that reaches zero is removed")
        XCTAssertNil(store.purchaseReceipts[ItemKind.rareCandy.rawValue])
        XCTAssertFalse(store.undoPurchase(receipt), "a refund happens once")
    }

    func testUndoIsBlockedOnceTheItemWasEquipped() async throws {
        let store = try await makeStore()
        let kind = try XCTUnwrap(store.purchasableItems.first {
            $0.isEquippable && !$0.isPassive && store.itemCount($0) == 0 && store.canBuy($0)
        })
        XCTAssertTrue(store.buy(kind))
        let receipt = try XCTUnwrap(store.purchaseReceipts[kind.rawValue])
        XCTAssertTrue(store.canUndo(receipt))
        let spent = store.state.spentTokens

        XCTAssertTrue(store.equip(.item(kind), to: ids.eevee))
        XCTAssertFalse(store.canUndo(receipt))
        XCTAssertFalse(store.undoPurchase(receipt))
        XCTAssertEqual(store.state.spentTokens, spent, "nothing was refunded")
        XCTAssertEqual(store.heldItemRef(of: ids.eevee), .item(kind))
    }

    func testUndoClosesAfterFiveSeconds() async throws {
        let clock = TestClock()
        let store = try await makeStore(clock: clock)
        let receipt = try candyReceipt(store)
        clock.now.addTimeInterval(PurchaseReceipt.window - 0.5)
        XCTAssertTrue(store.canUndo(receipt))
        clock.now.addTimeInterval(1)
        XCTAssertFalse(store.canUndo(receipt))
        let spent = store.state.spentTokens
        XCTAssertFalse(store.undoPurchase(receipt))
        XCTAssertEqual(store.state.spentTokens, spent)
        store.dismissReceipt(receipt)
        XCTAssertNil(store.purchaseReceipts[ItemKind.rareCandy.rawValue])
    }

    func testMegaStoneAndScoutTicketPurchasesCanBeUndone() async throws {
        let store = try await makeStore()
        let spent = store.state.spentTokens
        let stone = try XCTUnwrap(MegaStone.all.first { store.canBuy($0) })
        XCTAssertTrue(store.buy(stone))
        XCTAssertTrue(store.buyScoutTicket(try XCTUnwrap(ScoutPool.all.first)))
        for key in [stone.inventoryKey, try XCTUnwrap(ScoutPool.all.first).inventoryKey] {
            XCTAssertTrue(store.undoPurchase(try XCTUnwrap(store.purchaseReceipts[key])))
        }
        XCTAssertEqual(store.state.spentTokens, spent)
    }

    func testANewPurchaseOfTheSameRowReplacesTheOlderReceipt() async throws {
        let store = try await makeStore()
        let first = try candyReceipt(store)
        let second = try candyReceipt(store)
        XCTAssertFalse(store.canUndo(first))
        XCTAssertTrue(store.canUndo(second))
    }
}
