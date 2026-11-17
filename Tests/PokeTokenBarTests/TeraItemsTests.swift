import Foundation
import XCTest
@testable import PokeTokenBar

private struct NoProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class TeraItemsTests: XCTestCase {
    private func tempFile() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tera-items-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir.appendingPathComponent("state.json")
    }

    /// A save with a graduated Ogerpon, Terapagos and Pikachu and a wallet that can buy anything.
    private func store(inventory: [String: Int] = [:], held: [String: String] = [:]) throws -> CompanionStore {
        var state = CompanionState()
        state.installBaselineSet = true
        state.usedSinceInstall = 50_000_000_000
        state.dex = [("ogerpon", 1017), ("terapagos", 1024), ("pikachu", 25), ("ogerpon2", 1017)].map { id, species in
            var profile = PokemonProfile.generate(seed: UInt64(species), instanceID: id)
            profile.level = 50
            var entry = DexEntry(baseID: species, finalID: species, chainOrder: [species], rarity: .rare,
                                 caughtAt: Date(timeIntervalSince1970: 1_700_000_000), profile: profile, names: [:])
            entry.id = id
            return entry
        }
        state.inventory = inventory
        state.heldItems = held
        let file = try tempFile()
        try JSONEncoder().encode(state).write(to: file)
        return CompanionStore(provider: NoProvider(), fileURL: file)
    }

    private let masks: [ItemKind] = [.tealMask, .wellspringMask, .hearthflameMask, .cornerstoneMask]

    func testTheBotSlugsMatchTheBotsItemNames() {
        XCTAssertEqual(masks.compactMap(\.heldItemSlug), ["teal-mask", "wellspring-mask", "hearthflame-mask", "cornerstone-mask"])
        XCTAssertEqual(ItemKind.stellarCrystal.heldItemSlug, "stellar-crystal")
    }

    func testMasksAreSoldInTheHeldItemTierAndTheCrystalAtTheMegaStonePrice() throws {
        let s = try store()
        let held = s.shopEntries(in: .heldItem)
        for mask in masks {
            XCTAssertTrue(held.contains(.item(mask)), "\(mask)")
            XCTAssertEqual(s.price(of: .item(mask)), HeldItem.price)
        }
        XCTAssertFalse(held.contains(.item(.stellarCrystal)))
        XCTAssertTrue(s.shopEntries(in: .megaStone).contains(.item(.stellarCrystal)))
        XCTAssertFalse(s.shopEntries(in: nil).contains(.item(.stellarCrystal)), "the crystal is not in the price list; it sells in the Mega tab and shows under Signature with the battle items")
        XCTAssertEqual(s.price(of: .item(.stellarCrystal)), MegaStone.price)
        XCTAssertEqual(ItemKind.stellarCrystal.category, .megaStone)
    }

    func testTheCrystalComesFirstAmongTheStonesOnlyForAnOwnedTerapagos() throws {
        let owned: Set<Int> = [1017, 1024, 25]
        let ownedStones = MegaStone.all.filter { owned.contains($0.speciesID) }.count
        let owner = try store().megaStoneShopEntries
        XCTAssertEqual(owner.firstIndex(of: .item(.stellarCrystal)), ownedStones,
                       "an owned Terapagos puts its crystal right after the stones you can use")
        XCTAssertEqual(owner.count, MegaStone.all.count + 1)

        var bare = CompanionState()
        bare.installBaselineSet = true
        let file = try tempFile()
        try JSONEncoder().encode(bare).write(to: file)
        let without = CompanionStore(provider: NoProvider(), fileURL: file).megaStoneShopEntries
        XCTAssertEqual(without.last, .item(.stellarCrystal))
    }

    func testTheCrystalCanBeBoughtOnlyOnceWhereverItEnds() throws {
        let s = try store()
        XCTAssertTrue(s.canBuy(.stellarCrystal))
        XCTAssertEqual(s.maxBuyCount(.stellarCrystal), 1)
        XCTAssertTrue(s.buy(.stellarCrystal))
        XCTAssertFalse(s.canBuy(.stellarCrystal), "in the bag")
        XCTAssertFalse(s.buy(.stellarCrystal))
        XCTAssertEqual(s.itemCount(.stellarCrystal), 1)

        XCTAssertTrue(s.equip(.stellarCrystal, to: "terapagos"))
        XCTAssertEqual(s.itemCount(.stellarCrystal), 0)
        XCTAssertFalse(s.canBuy(.stellarCrystal), "on a holder")
        XCTAssertTrue(s.isSoldOut(.stellarCrystal))

        XCTAssertTrue(s.unequip(from: "terapagos"))
        XCTAssertTrue(s.isSoldOut(.stellarCrystal))
    }

    func testMasksAreNotLimitedToOneCopy() throws {
        let s = try store()
        XCTAssertGreaterThan(s.maxBuyCount(.tealMask), 1)
        XCTAssertTrue(s.buy(.tealMask, count: 2))
        XCTAssertEqual(s.itemCount(.tealMask), 2)
    }

    func testAMaskChangesTheHoldersSpriteAndTypesOnlyOnOgerpon() throws {
        let s = try store(inventory: ["wellspringMask": 1, "tealMask": 1, "hearthflameMask": 1])
        XCTAssertTrue(s.equip(.wellspringMask, to: "ogerpon"))
        XCTAssertEqual(s.megaSpriteID(instanceID: "ogerpon", speciesID: 1017), 10273)
        XCTAssertEqual(s.teraForm(of: "ogerpon", speciesID: 1017)?.types, ["grass", "water"])

        XCTAssertTrue(s.equip(.tealMask, to: "ogerpon"))
        XCTAssertNil(s.megaSpriteID(instanceID: "ogerpon", speciesID: 1017), "the teal mask is the base form")
        XCTAssertEqual(s.itemCount(.wellspringMask), 1, "the swapped mask went back to the bag")

        XCTAssertTrue(s.equip(.hearthflameMask, to: "pikachu"))
        XCTAssertNil(s.megaSpriteID(instanceID: "pikachu", speciesID: 25), "a mask on the wrong species changes nothing")
        XCTAssertNil(s.teraForm(of: "pikachu", speciesID: 25))
    }

    func testEachMaskAndTheCrystalNamesItsFormSprite() {
        XCTAssertEqual(masks.map { $0.formSprite?.id }, [nil, 10273, 10274, 10275])
        XCTAssertEqual(ItemKind.stellarCrystal.formSprite?.id, 10277)
        XCTAssertEqual(ItemKind.stellarCrystal.formSprite?.stats, [160, 105, 110, 130, 110, 85])
        XCTAssertEqual(masks.compactMap(\.holderSpeciesID), [1017, 1017, 1017, 1017])
        XCTAssertEqual(ItemKind.stellarCrystal.holderSpeciesID, 1024)
        XCTAssertNil(ItemKind.leftovers.holderSpeciesID)
    }

    func testTheCrystalShowsStellarTerapagosAndNothingElse() throws {
        let s = try store(inventory: ["stellarCrystal": 1])
        XCTAssertTrue(s.equip(.stellarCrystal, to: "terapagos"))
        XCTAssertEqual(s.megaSpriteID(instanceID: "terapagos", speciesID: 1024), 10277)
        XCTAssertEqual(s.megaSpriteID(forSpecies: 1024), 10277)

        XCTAssertTrue(s.unequip(from: "terapagos"))
        XCTAssertNil(s.megaSpriteID(forSpecies: 1024))
        XCTAssertTrue(s.equip(.stellarCrystal, to: "ogerpon"))
        XCTAssertNil(s.megaSpriteID(instanceID: "ogerpon", speciesID: 1017))
    }

    func testEachFormIsItsOwnStaticSpriteFile() {
        let kinds: [ItemKind] = [.wellspringMask, .hearthflameMask, .cornerstoneMask, .stellarCrystal]
        let formIDs = kinds.compactMap { $0.formSprite?.id } + [10276]
        XCTAssertEqual(formIDs, [10273, 10274, 10275, 10277, 10276])
        for id in formIDs {
            let still = SpriteStore.spriteURL(speciesID: id, animated: false, shiny: false)
            XCTAssertEqual(still.lastPathComponent, "\(id).png")
            XCTAssertEqual(SpriteStore.cacheKey(speciesID: id, animated: false, shiny: false), "\(id)-s")
            XCTAssertFalse(PokemonAssets.hasAnimatedSprite(speciesID: id), "\(id) has no animated sprite to fall back on")
        }
    }

    func testAnItemOnTheWrongSpeciesDoesNotMakeItsRealHolderADuplicate() throws {
        for kind in [ItemKind.wellspringMask, .stellarCrystal] {
            let holder = kind == .stellarCrystal ? "terapagos" : "ogerpon"
            let s = try store(held: ["pikachu": kind.rawValue, holder: kind.rawValue])
            let lineup = ["pikachu", holder].map { BattleEntrySlot(instanceID: $0) }
            XCTAssertEqual(BattleEntry.duplicateItemHolders(state: s.state, slots: lineup), [], "\(kind)")
        }
        let twins = try store(held: ["ogerpon": ItemKind.tealMask.rawValue, "ogerpon2": ItemKind.tealMask.rawValue])
        let both = ["ogerpon", "ogerpon2"].map { BattleEntrySlot(instanceID: $0) }
        XCTAssertEqual(BattleEntry.duplicateItemHolders(state: twins.state, slots: both), ["ogerpon2"])
    }

    func testAMaskOnTheWrongSpeciesIsNotAClashButTwoRealHoldersAre() throws {
        let mask = ItemKind.tealMask.rawValue
        let mixed = try store(held: ["pikachu": mask, "ogerpon": mask])
        let slots = ["pikachu", "ogerpon"].map { BattleEntrySlot(instanceID: $0) }
        XCTAssertFalse(BattleEntry.equipClash(mask, onto: "ogerpon", state: mixed.state, slots: slots))
        XCTAssertFalse(BattleEntry.equipClash(mask, onto: "pikachu", state: mixed.state, slots: slots))
        XCTAssertFalse(BattleEntry.itemClash("ogerpon", replacing: nil, among: ["pikachu"], state: mixed.state))
        XCTAssertFalse(BattleEntry.itemClash("pikachu", replacing: nil, among: ["ogerpon"], state: mixed.state))

        let twins = try store(held: ["ogerpon": mask, "ogerpon2": mask])
        let both = ["ogerpon", "ogerpon2"].map { BattleEntrySlot(instanceID: $0) }
        XCTAssertTrue(BattleEntry.equipClash(mask, onto: "ogerpon2", state: twins.state, slots: both))
        XCTAssertTrue(BattleEntry.itemClash("ogerpon2", replacing: nil, among: ["ogerpon"], state: twins.state))
    }

    func testTheUploadedItemIsTheSlugEvenOnTheWrongSpecies() throws {
        let s = try store(held: ["ogerpon": ItemKind.cornerstoneMask.rawValue, "pikachu": ItemKind.tealMask.rawValue,
                                 "terapagos": ItemKind.stellarCrystal.rawValue])
        XCTAssertEqual(s.state.heldItemSlug(of: "ogerpon"), "cornerstone-mask")
        XCTAssertEqual(s.state.heldItemSlug(of: "terapagos"), "stellar-crystal")
        XCTAssertEqual(s.state.heldItemSlug(of: "pikachu"), "teal-mask", "the bot ignores it; the app does not second-guess")
    }

    func testEveryLanguageHasTextForTheNewItems() {
        for language in AppLanguage.allCases {
            let l = L(language)
            for kind in masks + [.stellarCrystal] {
                XCTAssertFalse(l.itemName(kind).isEmpty, "\(language) \(kind) name")
                XCTAssertFalse(l.itemDescription(kind).isEmpty, "\(language) \(kind) description")
                XCTAssertFalse(l.heldItemEffect(kind).isEmpty, "\(language) \(kind) effect")
            }
        }
        XCTAssertEqual(L(.ko).itemName(.stellarCrystal), "별빛 결정")
        XCTAssertEqual(L(.en).itemName(.stellarCrystal), "Stellar Crystal")
        XCTAssertEqual(L(.ko).itemName(.tealMask), "벽록의가면")
        XCTAssertTrue(L(.en).heldItemEffect(.wellspringMask).contains("Grass/Water"))
        XCTAssertTrue(L(.en).heldItemEffect(.hearthflameMask).contains("Atk"))
    }
}
