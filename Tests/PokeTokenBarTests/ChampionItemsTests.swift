import XCTest
@testable import PokeTokenBar

@MainActor
final class ChampionItemsTests: XCTestCase {
    func testEveryNewItemUploadsASlugTheBotItemTableKnows() throws {
        let known = try BattleData.knownItems()
        XCTAssertTrue(known.contains("leftovers"))
        XCTAssertEqual(ItemKind.championBattleItems.count, 44)
        var state = CompanionState()
        for (index, kind) in ItemKind.championBattleItems.enumerated() {
            state.heldItems["mon\(index)"] = kind.rawValue
            let slug = try XCTUnwrap(state.heldItemSlug(of: "mon\(index)"), "\(kind)")
            XCTAssertTrue(known.contains(slug), "the bot has no item \(slug)")
        }
    }

    func testNewItemsAreSoldAndHeldLikeOtherBattleItems() {
        for kind in ItemKind.championBattleItems {
            XCTAssertTrue(kind.isHeldItem, "\(kind)")
            XCTAssertTrue(kind.isEquippable, "\(kind)")
            XCTAssertEqual(kind.category, .heldItem, "\(kind)")
            XCTAssertEqual(kind.shopPrice, HeldItem.price, "\(kind)")
        }
    }

    func testEachTypeHasOneResistBerryAndEachTypeButNormalOnePlate() {
        let berries = ItemKind.resistBerries.compactMap(\.resistedType)
        XCTAssertEqual(Set(berries), Set(PokemonType.allCases.map(\.rawValue)))
        XCTAssertEqual(berries.count, 18)
        let plates = ItemKind.plates.compactMap(\.plateType)
        XCTAssertEqual(Set(plates), Set(PokemonType.allCases.map(\.rawValue)).subtracting(["normal"]))
        XCTAssertEqual(plates.count, 17)
        XCTAssertTrue(ItemKind.plates.allSatisfy { $0.boostedType == nil }, "plates stay out of the one-item-per-type boost set")
    }

    func testOrbsAndOriginItemsNameTheirOwnSpecies() {
        XCTAssertEqual(ItemKind.redOrb.holderSpeciesID, 383)
        XCTAssertEqual(ItemKind.blueOrb.holderSpeciesID, 382)
        XCTAssertEqual(ItemKind.adamantCrystal.holderSpeciesID, 483)
        XCTAssertEqual(ItemKind.lustrousGlobe.holderSpeciesID, 484)
        XCTAssertEqual(ItemKind.griseousCore.holderSpeciesID, 487)
        XCTAssertEqual(ItemKind.rustedSword.holderSpeciesID, 888)
        XCTAssertEqual(ItemKind.rustedShield.holderSpeciesID, 889)
        XCTAssertEqual(ItemKind.ultranecroziumZ.holderSpeciesID, 800)
        XCTAssertEqual(ItemKind.megaSlotItems, [.redOrb, .blueOrb, .ultranecroziumZ], "the crowned weapons leave the Mega slot free")
        XCTAssertNil(ItemKind.punchingGlove.holderSpeciesID)
        XCTAssertNil(ItemKind.flamePlate.holderSpeciesID, "a plate works on any holder")
    }

    func testEveryNewItemHasEffectTextInEveryLanguage() {
        for language in AppLanguage.allCases {
            for kind in ItemKind.championBattleItems {
                XCTAssertFalse(L(language).heldItemEffect(kind).isEmpty, "\(kind) \(language)")
            }
        }
    }
}
