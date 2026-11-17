import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct GroupShotProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 4, tree: EvoNode(speciesID: 4, children: [EvoNode(speciesID: 5, children: [])]),
                rarity: .common, names: [4: ["ko": "파이리"], 5: ["ko": "리자드"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class HeldItemGroupTests: XCTestCase {
    private static let bagSample: [ItemKind: Int] = [
        .leftovers: 1, .choiceBand: 2, .choiceSpecs: 1, .charcoal: 1, .mysticWater: 1, .metalCoat: 1,
        .razorClaw: 1, .focusSash: 1, .choiceScarf: 1, .lumBerry: 1, .heatRock: 1, .everstone: 1, .rareCandy: 3,
    ]

    private func store(language: AppLanguage = .en, inventory: [ItemKind: Int] = [:]) throws -> CompanionStore {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("held-group-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: scratch) }
        var state = CompanionState()
        state.language = language
        state.installBaselineSet = true
        state.usedSinceInstall = 90_000_000_000
        state.active = MonState(baseID: 4, pathIDs: [4, 5], stageIndex: 0, usedAtStage: 0,
                                rarity: .common, totalForms: 2,
                                profile: PokemonProfile.generate(seed: 5, instanceID: "raised"))
        state.inventory = Dictionary(uniqueKeysWithValues: inventory.map { ($0.key.rawValue, $0.value) })
        let file = scratch.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        return CompanionStore(provider: GroupShotProvider(), fileURL: file)
    }

    func testEveryBattleItemBelongsToExactlyOneGroup() {
        let battleItems = ItemKind.allCases.filter { $0.heldItemSlug != nil }
        for kind in ItemKind.allCases {
            XCTAssertEqual(kind.battleGroup != nil, kind.heldItemSlug != nil, "\(kind)")
        }
        let listed = BattleItemGroup.sections(of: ItemKind.allCases).flatMap(\.kinds)
        XCTAssertEqual(listed.count, Set(listed).count, "no item is listed twice")
        XCTAssertEqual(Set(listed), Set(battleItems))
    }

    func testGroupsAndTheirItemsKeepTheirOrder() throws {
        XCTAssertEqual(BattleItemGroup.allCases, [.attack, .typeBoost, .bulk, .speed, .status, .weather, .signature, .other])
        let sections = try store().shopBattleSections
        XCTAssertEqual(sections.map(\.group), BattleItemGroup.allCases)
        let expected: [BattleItemGroup: [ItemKind]] = [
            .attack: [.choiceBand, .choiceSpecs, .lifeOrb, .expertBelt, .muscleBand, .wiseGlasses, .punchingGlove],
            .typeBoost: [.silkScarf, .charcoal, .mysticWater, .magnet, .miracleSeed, .neverMeltIce, .blackBelt,
                         .poisonBarb, .softSand, .sharpBeak, .twistedSpoon, .silverPowder, .hardStone, .spellTag,
                         .dragonFang, .blackGlasses, .metalCoat, .fairyFeather] + ItemKind.plates,
            .bulk: [.assaultVest, .eviolite, .leftovers, .blackSludge, .sitrusBerry, .shellBell, .bigRoot, .focusSash,
                    .focusBand] + ItemKind.resistBerries,
            .speed: [.choiceScarf, .quickClaw, .scopeLens, .razorClaw, .wideLens, .brightPowder],
            .status: [.lumBerry, .whiteHerb, .weaknessPolicy, .rockyHelmet, .flameOrb, .toxicOrb],
            .weather: [.heatRock, .dampRock, .smoothRock, .icyRock],
            .signature: [.tealMask, .wellspringMask, .hearthflameMask, .cornerstoneMask, .stellarCrystal,
                         .redOrb, .blueOrb, .ultranecroziumZ, .adamantCrystal, .lustrousGlobe, .griseousCore,
                         .rustedSword, .rustedShield],
            .other: [.everstone],
        ]
        for section in sections {
            XCTAssertEqual(section.kinds, expected[section.group], "\(section.group)")
        }
        let typeBoost = try XCTUnwrap(sections.first { $0.group == .typeBoost }).kinds
        XCTAssertEqual(typeBoost.compactMap(\.boostedType), PokemonType.allCases.map(\.rawValue))
        XCTAssertEqual(typeBoost.compactMap(\.plateType), PokemonType.allCases.map(\.rawValue).filter { $0 != "normal" })
    }

    func testMetalCoatAndRazorClawSitInTheEvolutionListAndTheirBattleGroup() throws {
        let shop = try store()
        let battle = shop.shopBattleSections
        for (kind, group) in [(ItemKind.metalCoat, BattleItemGroup.typeBoost), (.razorClaw, .speed)] {
            XCTAssertTrue(shop.shopEvolutionItems.contains(kind), "\(kind)")
            XCTAssertTrue(battle.first { $0.group == group }?.kinds.contains(kind) ?? false, "\(kind)")
            XCTAssertEqual(kind.category, .evolution, "\(kind)")
            XCTAssertEqual(kind.shopPrice, EvolutionStone.price, "\(kind)")
        }
        XCTAssertTrue(shop.buy(.metalCoat))
        XCTAssertEqual(shop.state.inventory, ["metalCoat": 1], "one purchase path, one inventory key")

        let bag = try store(inventory: [.metalCoat: 2, .razorClaw: 1])
        XCTAssertEqual(bag.bagCategories, [.evolution, .heldItem])
        XCTAssertEqual(bag.ownedItems(in: .evolution).map(\.kind), [.razorClaw, .metalCoat])
        XCTAssertEqual(bag.ownedBattleSections.flatMap(\.kinds), [.metalCoat, .razorClaw])
        let allView = bag.bagListItems(in: nil).map(\.kind) + bag.ownedBattleSections.flatMap(\.kinds)
        XCTAssertEqual(allView, [.metalCoat, .razorClaw], "the all view lists each once")
        XCTAssertEqual(allView.map(bag.itemCount).reduce(0, +), 3)
    }

    func testTheShopAllViewListsEveryItemOnce() throws {
        let shop = try store()
        let flat: [ItemKind] = shop.shopEntries(in: nil).compactMap {
            guard case .item(let kind) = $0, kind.category != .heldItem else { return nil }
            return kind
        }
        let grouped = shop.shopBattleSections.flatMap(\.kinds)
        let allView = flat + grouped + shop.shopAllViewEvolutionItems
        XCTAssertEqual(allView.count, Set(allView).count, "no item is listed twice")
        XCTAssertFalse(shop.shopAllViewEvolutionItems.contains(.metalCoat))
        XCTAssertFalse(shop.shopAllViewEvolutionItems.contains(.razorClaw))
        XCTAssertEqual(Set(shop.shopEvolutionItems).subtracting(shop.shopAllViewEvolutionItems), [.metalCoat, .razorClaw])
    }

    func testTheBagAllViewListsEveryOwnedItemOnceWithBattleItemsGrouped() throws {
        let bag = try store(inventory: Self.bagSample)
        let flat = bag.bagListItems(in: nil).map(\.kind)
        let grouped = bag.ownedBattleSections.flatMap(\.kinds)
        XCTAssertEqual(flat, [.rareCandy])
        XCTAssertEqual((flat + grouped).count, Self.bagSample.count)
        XCTAssertEqual(Set(flat + grouped), Set(Self.bagSample.keys))
        XCTAssertTrue(bag.bagListItems(in: .heldItem).isEmpty)
        XCTAssertEqual(bag.ownedBattleSections.map(\.group), [.attack, .typeBoost, .bulk, .speed, .status, .weather, .other])
    }

    // MARK: PR captures

    /// Opt-in captures for the PR, dark and 720 px wide like the README shots.
    ///
    ///     PTB_HELD_GROUP_SHOT_DIR=/tmp/shots swift test --filter HeldItemGroupTests/testCaptureShopAndBag
    func testCaptureShopAndBag() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_HELD_GROUP_SHOT_DIR"] else {
            throw XCTSkip("Set PTB_HELD_GROUP_SHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for language in [AppLanguage.en, .ko] {
            let shop = try store(language: language)
            try await capture(ShopView(store: shop, nav: PopoverNavigation(), initialCategory: .heldItem),
                              store: shop, height: 560, to: directory.appendingPathComponent("shop-held-\(language.rawValue).png"))
            let bag = try store(language: language, inventory: Self.bagSample)
            try await capture(BagView(store: bag, nav: PopoverNavigation(), initialCategory: .heldItem),
                              store: bag, height: 560, to: directory.appendingPathComponent("bag-held-\(language.rawValue).png"))
        }
    }

    private func capture<V: View>(_ view: V, store: CompanionStore, height: CGFloat, to file: URL) async throws {
        let width = PopoverMetrics.width
        let content = view
            .environment(store)
            .padding(.horizontal, PopoverMetrics.padding)
            .padding(.vertical, 12)
            .frame(width: width, height: height, alignment: .top)
            .background(Color(red: 41 / 255, green: 41 / 255, blue: 42 / 255))
            .environment(\.colorScheme, .dark)
            .environment(\.locale, store.state.language.displayLocale)
        try await OffscreenRender.capture(content, size: CGSize(width: width, height: height),
                                          appearance: .darkAqua, scale: 2, to: file)
    }
}
