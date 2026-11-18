import XCTest
@testable import PokeTokenBar

@MainActor
final class BoxRegionRarityChipsTests: XCTestCase {
    private let ids = (raised: BoxDexFixture.raisedID, pikachu: BoxDexFixture.pikachuID,
                       charizard: BoxDexFixture.charizardID, onix: BoxDexFixture.onixID, eevee: BoxDexFixture.eeveeID,
                       xatu: BoxChipsFixture.xatuID, lucario: BoxChipsFixture.lucarioID)

    private func visible(_ store: CompanionStore, _ filters: BoxFilterStore) -> Set<String> {
        Set(store.filteredBoxIndividuals(query: filters.searchText, filter: filters.filter).map(\.id))
    }

    private func filterStore() throws -> BoxFilterStore {
        try BoxChipsFixture.navigation(test: self).boxFilters
    }

    func testRegionChipFiltersToThatRegionAndASecondTapClears() async throws {
        let store = try await BoxChipsFixture.makeStore(language: .en, test: self)
        let filters = try filterStore()

        filters.filter.toggleRegion(.johto)
        XCTAssertEqual(visible(store, filters), [ids.xatu])
        XCTAssertEqual(BoxScopeChips.regionChips(store.boxIndividuals, filter: filters.filter).filter(\.isSelected).map(\.value),
                       [.johto])

        filters.filter.toggleRegion(.kanto)
        XCTAssertEqual(visible(store, filters), [ids.raised, ids.pikachu, ids.charizard, ids.onix, ids.eevee],
                       "one region at a time; the current species decides, so Charmeleon and Mega Charizard are Kanto")

        filters.filter.toggleRegion(.kanto)
        XCTAssertNil(filters.filter.region)
        XCTAssertEqual(visible(store, filters).count, 7)
    }

    func testRegionFollowsTheCurrentSpeciesNotTheBaseOne() async throws {
        let store = try await BoxChipsFixture.makeStore(language: .en, test: self) { state in
            state.dex.append(DexEntry(id: "steelix", baseID: 95, finalID: 208, chainOrder: [95, 208], rarity: .rare,
                                      caughtAt: Date(timeIntervalSince1970: 1_700_000_700), names: [95: ["en": "Onix"], 208: ["en": "Steelix"]]))
        }
        var filter = BoxFilter()
        filter.region = .johto
        XCTAssertEqual(Set(store.filteredBoxIndividuals(filter: filter).map(\.id)), [ids.xatu, "steelix"],
                       "an Onix that became Steelix is Johto")
        filter.region = .kanto
        XCTAssertFalse(store.filteredBoxIndividuals(filter: filter).map(\.id).contains("steelix"))
        XCTAssertEqual(BoxScopeChips.regionChips(store.boxIndividuals, filter: BoxFilter())
            .first { $0.value == .johto }?.count, 2)
    }

    func testGradeChipFiltersAndThePanelSeesTheSameValue() async throws {
        let store = try await BoxChipsFixture.makeStore(language: .en, test: self)
        let filters = try filterStore()

        filters.filter.toggleRarity(.uncommon)
        XCTAssertEqual(visible(store, filters), [ids.lucario])
        XCTAssertEqual(filters.filter.rarity, .uncommon, "the panel's rarity section reads this value")
        XCTAssertEqual(BoxScopeChips.rarityChips(store.boxIndividuals, filter: filters.filter).filter(\.isSelected).map(\.value),
                       [.uncommon])

        filters.filter.toggleRarity(.rare)
        XCTAssertEqual(filters.filter.rarity, .rare, "one grade at a time")
        filters.filter.toggleRarity(.rare)
        XCTAssertNil(filters.filter.rarity)
    }

    func testRegionGradeAndTypeCombine() async throws {
        let store = try await BoxChipsFixture.makeStore(language: .en, test: self)
        let filters = try filterStore()
        filters.filter.toggleRegion(.kanto)
        filters.filter.toggleRarity(.rare)
        XCTAssertEqual(visible(store, filters), [ids.pikachu, ids.charizard, ids.onix, ids.eevee],
                       "Xatu is rare but Johto; the raised Charmeleon is Kanto but common")
        filters.filter.types = [.fire]
        XCTAssertEqual(visible(store, filters), [ids.charizard])
        filters.filter.types = [.psychic]
        XCTAssertEqual(visible(store, filters), [], "Xatu is psychic but outside Kanto")
        filters.filter.region = .johto
        XCTAssertEqual(visible(store, filters), [ids.xatu])
        filters.searchText = "Pika"
        XCTAssertEqual(visible(store, filters), [])
    }

    func testChipsCountBoxIndividualsAndDisableTheEmptyOnes() async throws {
        let store = try await BoxChipsFixture.makeStore(language: .en, test: self)
        let regions = BoxScopeChips.regionChips(store.boxIndividuals, filter: BoxFilter())
        XCTAssertEqual(regions.map(\.value), PokedexRegion.allCases)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: regions.map { ($0.value, $0.count) }),
                       [.kanto: 5, .johto: 1, .hoenn: 0, .sinnoh: 1, .unova: 0, .kalos: 0, .alola: 0, .galar: 0, .paldea: 0])
        XCTAssertEqual(regions.filter(\.isEnabled).map(\.value), [.kanto, .johto, .sinnoh])

        let rarities = BoxScopeChips.rarityChips(store.boxIndividuals, filter: BoxFilter())
        XCTAssertEqual(rarities.map(\.value), [.legendary, .rare, .uncommon, .common], "the Pokédex order")
        XCTAssertEqual(rarities.map(\.count), [0, 5, 1, 1])
        XCTAssertEqual(rarities.filter { !$0.isEnabled }.map(\.value), [.legendary])

        var stale = BoxFilter()
        stale.region = .paldea
        XCTAssertTrue(try XCTUnwrap(BoxScopeChips.regionChips(store.boxIndividuals, filter: stale)
            .first { $0.value == .paldea }).isEnabled, "a saved pick whose last member left can still be tapped off")
    }

    func testClearResetsRegionAndTheBadgeCountsIt() throws {
        let filters = try filterStore()
        XCTAssertEqual(filters.filter.menuActiveCount, 0)
        filters.filter.toggleRegion(.johto)
        XCTAssertEqual(filters.filter.menuActiveCount, 1)
        filters.filter.toggleRarity(.rare)
        XCTAssertEqual(filters.filter.menuActiveCount, 2)
        filters.clear()
        XCTAssertNil(filters.filter.region)
        XCTAssertEqual(filters.filter, BoxFilter())
    }

    func testRegionSurvivesARelaunchAndAnOldSavedFilterDecodes() throws {
        let suite = "box-chips-decode-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }

        let first = BoxFilterStore(defaults: defaults)
        first.filter.region = .sinnoh
        XCTAssertEqual(BoxFilterStore(defaults: defaults).filter.region, .sinnoh)

        let old = #"{"sort":"level","shinyOnly":true,"hasItemOnly":false,"types":["fire"],"rarity":"rare","inLineupOnly":false,"tradableOnly":true,"level":"fiftyPlus"}"#
        defaults.set(Data(old.utf8), forKey: BoxFilterStore.defaultsKey)
        let decoded = BoxFilterStore(defaults: defaults).filter
        XCTAssertNil(decoded.region)
        XCTAssertEqual(decoded.sort, .level)
        XCTAssertTrue(decoded.shinyOnly)
        XCTAssertEqual(decoded.types, [.fire])
        XCTAssertEqual(decoded.rarity, .rare)
        XCTAssertTrue(decoded.tradableOnly)
        XCTAssertEqual(decoded.level, .fiftyPlus)

        defaults.set(Data(#"{"region":"orre","rarity":"rare"}"#.utf8), forKey: BoxFilterStore.defaultsKey)
        let unknown = BoxFilterStore(defaults: defaults).filter
        XCTAssertNil(unknown.region, "a region this build does not know is dropped")
        XCTAssertEqual(unknown.rarity, .rare, "and the rest of the filter is kept")
    }
}
