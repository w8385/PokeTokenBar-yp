import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct SearchShopProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 4, tree: EvoNode(speciesID: 4, children: [EvoNode(speciesID: 5, children: [])]),
                rarity: .common, names: [4: ["ko": "파이리"], 5: ["ko": "리자드"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

private let thunderbolt = 85

@MainActor
final class ShopSearchTests: XCTestCase {
    private func store(language: AppLanguage = .ko, inventory: [String: Int] = [:]) throws -> CompanionStore {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("shop-search-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: scratch) }
        var state = CompanionState()
        state.language = language
        state.installBaselineSet = true
        state.usedSinceInstall = 9_000_000_000
        state.active = MonState(baseID: 4, pathIDs: [4, 5], stageIndex: 0, usedAtStage: 0,
                                rarity: .common, totalForms: 2,
                                profile: PokemonProfile.generate(seed: 5, instanceID: "raised"))
        state.inventory = inventory
        let file = scratch.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        return CompanionStore(provider: SearchShopProvider(), fileURL: file,
                              defaults: UserDefaults(suiteName: "shop-search-\(UUID())")!)
    }

    private func kinds(_ results: ShopSearchResults) -> [ItemKind] {
        let entries = results.entriesBeforeHeld + results.entriesAfterHeld + results.megaStones
        return entries.compactMap { if case .item(let kind) = $0 { kind } else { nil } }
            + results.battleSections.flatMap(\.kinds) + results.evolutionItems
    }

    private func stones(_ results: ShopSearchResults) -> [MegaStone] {
        results.megaStones.compactMap { if case .megaStone(let stone) = $0 { stone } else { nil } }
    }

    /// Every item the shop sells, as its tabs list them.
    private func shopListedKinds(_ shop: CompanionStore) -> [ItemKind] {
        let entries = shop.shopEntries(in: nil) + shop.megaStoneShopEntries
        return entries.compactMap { if case .item(let kind) = $0 { kind } else { nil } }
            + shop.shopBattleSections.flatMap(\.kinds) + shop.shopEvolutionItems
    }

    // MARK: matching

    func testAnEnglishNameFindsTheItemInTheKoreanUI() throws {
        let shop = try store(language: .ko)
        XCTAssertEqual(kinds(shop.shopSearch("life orb")), [.lifeOrb])
        XCTAssertEqual(kinds(shop.shopSearch("LIFE-ORB")), [.lifeOrb])
        XCTAssertEqual(kinds(shop.shopSearch("생명의구슬")), [.lifeOrb])
        XCTAssertEqual(kinds(shop.shopSearch("いのちのたま")), [.lifeOrb])
        let egg = shop.shopSearch("pokemon egg")
        XCTAssertTrue((egg.entriesBeforeHeld + egg.entriesAfterHeld).contains(.egg(nil)), "accents fold away")
    }

    func testEveryItemTheShopSellsSitsInATabAndIsFoundByItsEnglishName() throws {
        let shop = try store(language: .ko)
        let listed = Set(shopListedKinds(shop))
        let english = L(.en)
        for kind in ItemKind.allCases where kind.shopPrice != nil {
            XCTAssertTrue(listed.contains(kind), "\(kind) sits in a shop tab")
            XCTAssertTrue(kinds(shop.shopSearch(english.itemName(kind))).contains(kind), "\(kind)")
        }
    }

    func testAnEffectWordFindsTheItemInTheCurrentLanguageOnly() throws {
        let korean = try store(language: .ko)
        XCTAssertTrue(kinds(korean.shopSearch("공격할 때마다")).contains(.lifeOrb))
        XCTAssertFalse(kinds(korean.shopSearch("at the cost of some HP")).contains(.lifeOrb),
                       "effect text matches in the current language only")
        let english = try store(language: .en)
        XCTAssertTrue(kinds(english.shopSearch("at the cost of some HP")).contains(.lifeOrb))
        let orb = english.shopSearch("orb")
        XCTAssertFalse((orb.entriesBeforeHeld + orb.entriesAfterHeld).contains(.egg(.uncommon)),
                       "\"or better\" in an effect sentence is not \"orb\"")
        XCTAssertTrue(kinds(orb).contains(.lifeOrb))
    }

    func testATMMoveNameReturnsTheTM() throws {
        let shop = try store(language: .ko)
        let results = shop.shopSearch("thunderbolt")
        XCTAssertTrue(results.machines.contains { $0.id == thunderbolt })
        XCTAssertTrue(shop.shopSearch("10만볼트").machines.contains { $0.id == thunderbolt })
    }

    func testAMegaStoneNameReturnsTheStoneOnce() throws {
        let shop = try store(language: .ko)
        let stone = try XCTUnwrap(MegaStone.all.first)
        XCTAssertTrue(stones(shop.shopSearch(stone.name(in: .en))).contains(stone))
        XCTAssertTrue(stones(shop.shopSearch(stone.name(in: .ko))).contains(stone))
        for query in ["stellar crystal", "metal coat"] {
            let found = kinds(shop.shopSearch(query))
            XCTAssertEqual(found.count, Set(found).count, "\(query) lists each item once")
            XCTAssertEqual(found.count, 1, query)
        }
    }

    func testAScoutTicketIsFoundByItsName() throws {
        let shop = try store(language: .ko)
        XCTAssertEqual(shop.shopSearch("national scout").scoutPools, [.national])
    }

    // MARK: order and the empty cases

    func testAnEmptyQueryIsNotASearchAndLeavesTodaysLists() throws {
        let shop = try store(language: .ko)
        for query in ["", "  ", "-"] {
            XCTAssertFalse(ShopSearch.isActive(query), "'\(query)'")
            XCTAssertTrue(shop.shopSearch(query).isEmpty, "'\(query)'")
        }
        XCTAssertTrue(ShopSearch.isActive("orb"))
        XCTAssertEqual(ShopSearch.sections(shop.shopBattleSections, in: nil), shop.shopBattleSections)
    }

    func testResultsKeepTodaysOrder() throws {
        let shop = try store(language: .en)
        let results = shop.shopSearch("e")
        func assertSubsequence<T: Equatable>(_ part: [T], of whole: [T], _ what: String) {
            var rest = whole[...]
            for element in part {
                guard let index = rest.firstIndex(of: element) else {
                    return XCTFail("\(what): \(element) out of order")
                }
                rest = rest[rest.index(after: index)...]
            }
        }
        let today = shop.shopEntries(in: nil).filter { $0.category != .heldItem }
        XCTAssertGreaterThan(results.entriesBeforeHeld.count + results.entriesAfterHeld.count, 1)
        assertSubsequence(results.entriesBeforeHeld + results.entriesAfterHeld, of: today, "entries")
        XCTAssertGreaterThan(results.battleSections.count, 1)
        assertSubsequence(results.battleSections.map(\.group), of: shop.shopBattleSections.map(\.group), "groups")
        for section in results.battleSections {
            let all = try XCTUnwrap(shop.shopBattleSections.first { $0.group == section.group }).kinds
            assertSubsequence(section.kinds, of: all, "\(section.group)")
        }
        assertSubsequence(results.evolutionItems, of: shop.shopAllViewEvolutionItems, "evolution")
        assertSubsequence(results.megaStones, of: shop.megaStoneShopEntries, "mega stones")
    }

    func testANoMatchReturnsNothing() throws {
        let shop = try store(language: .ko)
        XCTAssertTrue(shop.shopSearch("zzqxv").isEmpty)
    }

    // MARK: held-item sub-tabs

    func testSubTabsOfferOnlyGroupsWithItemsInEnumOrder() throws {
        let shop = try store()
        XCTAssertEqual(ShopSearch.subTabGroups(shop.shopBattleSections), BattleItemGroup.allCases)
        let some = BattleItemGroup.sections(of: [.heatRock, .leftovers, .everstone])
        XCTAssertEqual(ShopSearch.subTabGroups(some), [.bulk, .weather, .other])
        let withEmpty = some + [BattleItemSection(group: .attack, kinds: [])]
        XCTAssertEqual(ShopSearch.subTabGroups(withEmpty), [.bulk, .weather, .other], "an empty group gets no tab")
    }

    func testEachSubTabShowsOnlyItsGroup() throws {
        let sections = try store().shopBattleSections
        for group in BattleItemGroup.allCases {
            let shown = ShopSearch.sections(sections, in: group)
            XCTAssertEqual(shown.map(\.group), [group])
            XCTAssertEqual(shown.first?.kinds, sections.first { $0.group == group }?.kinds)
        }
    }

    // MARK: what the view draws

    func testTheEmptyLineShowsOnlyWhenASearchFindsNothing() throws {
        let shop = try store(language: .en)
        let none = shop.shopScreen(category: nil, query: "zzqxv", heldGroup: nil)
        XCTAssertEqual(none.results, ShopSearchResults())
        XCTAssertTrue(none.showsEmptyLine)
        let some = shop.shopScreen(category: nil, query: "life orb", heldGroup: nil)
        XCTAssertFalse(some.showsEmptyLine)
        XCTAssertEqual(some.results?.battleSections.map(\.group), [.attack])
        let browse = shop.shopScreen(category: nil, query: " ", heldGroup: nil)
        XCTAssertNil(browse.results, "a blank query is today's view")
        XCTAssertFalse(browse.showsEmptyLine)
        XCTAssertEqual(browse.heldSections, shop.shopBattleSections)
    }

    func testTheHeldItemTabShowsTheSubTabRowAndOnlyThePickedGroup() throws {
        let shop = try store(language: .en)
        let weather = shop.shopScreen(category: .heldItem, query: "", heldGroup: .weather)
        XCTAssertEqual(weather.subTabs, BattleItemGroup.allCases)
        XCTAssertEqual(weather.shownSubTab, .weather)
        XCTAssertEqual(weather.heldSections.map(\.group), [.weather])
        let all = shop.shopScreen(category: .heldItem, query: "", heldGroup: nil)
        XCTAssertEqual(all.heldSections, shop.shopBattleSections, "All is today's stacked view")
        for category in [nil] + ItemCategory.allCases.filter({ $0 != .heldItem }) {
            let other = shop.shopScreen(category: category, query: "", heldGroup: .weather)
            XCTAssertEqual(other.subTabs, [], "no sub-tab row under \(String(describing: category))")
            XCTAssertEqual(other.heldSections, shop.shopBattleSections, "the all view stays stacked")
        }
    }

    func testSearchWinsOverEveryChipAndThePickedSubTab() throws {
        let shop = try store(language: .en)
        let expected = shop.shopSearch("life orb")
        for category in [nil] + ItemCategory.allCases {
            let screen = shop.shopScreen(category: category, query: "life orb", heldGroup: .weather)
            XCTAssertEqual(screen.results, expected, "\(String(describing: category))")
            XCTAssertNil(screen.shownSubTab, "the sub-tab row shows as cleared")
        }
    }

    func testTheTMChipShowsGlobalResultsWhileSearchingAndItsOwnTabAfter() throws {
        let shop = try store(language: .en)
        let searching = shop.shopScreen(category: .machine, query: "ice beam", heldGroup: nil)
        XCTAssertNotNil(searching.results)
        XCTAssertFalse(searching.showsMachineTab)
        XCTAssertTrue(searching.hasMachineTab, "the TM tab stays alive under a search")
        let cleared = shop.shopScreen(category: .machine, query: "", heldGroup: nil)
        XCTAssertNil(cleared.results)
        XCTAssertTrue(cleared.showsMachineTab && cleared.hasMachineTab)
        XCTAssertFalse(shop.shopScreen(category: nil, query: "", heldGroup: nil).hasMachineTab)
    }

    func testTheTMTabKeepsItsOwnFieldThroughASearchSetAndClear() async throws {
        let shop = try store(language: .en)
        let l = shop.l
        let host = OffscreenRender.host(
            ShopView(store: shop, nav: PopoverNavigation(), initialCategory: .machine, machineQuery: "thunder")
                .frame(width: PopoverMetrics.contentWidth).environment(\.colorScheme, .light),
            size: CGSize(width: PopoverMetrics.contentWidth, height: 520), appearance: .aqua)
        try await OffscreenRender.settle(host)
        let global = try XCTUnwrap(field(in: host, placeholder: l.shopSearchPrompt))
        let machine = try XCTUnwrap(field(in: host, placeholder: l.shopMachineSearchPrompt))
        XCTAssertEqual(machine.stringValue, "thunder")
        type("punch", into: machine)
        try await OffscreenRender.settle(host)
        let browsing = machine.convert(machine.bounds, to: host)

        type("ice beam", into: global)
        try await OffscreenRender.settle(host) { machine.convert(machine.bounds, to: host) != browsing }

        type("", into: global)
        try await OffscreenRender.settle(host) { field(in: host, placeholder: l.shopMachineSearchPrompt)?.stringValue == "punch" }
        let back = try XCTUnwrap(field(in: host, placeholder: l.shopMachineSearchPrompt))
        XCTAssertEqual(back.convert(back.bounds, to: host), browsing)
    }

    func testTheBagChipsAreUnchanged() async throws {
        let bag = try store(language: .en, inventory: ["rareCandy": 1, "leftovers": 1, "heatRock": 1, "fireStone": 1])
        XCTAssertEqual(bag.bagCategories, [.growth, .evolution, .heldItem])
        let host = OffscreenRender.host(
            BagView(store: bag, nav: PopoverNavigation(), initialCategory: .heldItem)
                .frame(width: PopoverMetrics.contentWidth).environment(\.colorScheme, .light),
            size: CGSize(width: PopoverMetrics.contentWidth, height: 520), appearance: .aqua)
        try await OffscreenRender.settle(host)
        XCTAssertNil(field(in: host, placeholder: bag.l.shopSearchPrompt), "the bag has no shop search")
    }

    private func field(in view: NSView, placeholder: String) -> NSTextField? {
        NativeControls.descendants(view).compactMap { $0 as? NSTextField }.first { $0.placeholderString == placeholder }
    }

    private func type(_ text: String, into field: NSTextField) {
        field.stringValue = text
        NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: field)
    }
}
