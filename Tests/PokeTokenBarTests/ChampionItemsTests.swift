import XCTest
@testable import PokeTokenBar

@MainActor
final class ChampionItemsTests: XCTestCase {
    /// The keys of `ITEM_NAMES` in `bot/ypoke/items.py`, string literals and module constants alike.
    private func botItemNames() throws -> Set<String> {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("bot/ypoke/items.py"), encoding: .utf8)
        var constants: [String: String] = [:]
        for match in source.matches(of: /(?m)^([A-Z][A-Z0-9_]*) = "([a-z0-9-]+)"$/) {
            constants[String(match.1)] = String(match.2)
        }
        let start = try XCTUnwrap(source.range(of: "\nITEM_NAMES = {"))
        let end = try XCTUnwrap(source.range(of: "\n}", range: start.upperBound..<source.endIndex))
        let block = source[start.upperBound..<end.lowerBound]
        var keys = Set<String>()
        for match in block.matches(of: /(?:"([a-z0-9-]+)"|\b([A-Z][A-Z0-9_]*))\s*:/) {
            if let literal = match.1 {
                keys.insert(String(literal))
            } else if let name = match.2 {
                keys.insert(try XCTUnwrap(constants[String(name)], "unknown constant \(name)"))
            }
        }
        return keys
    }

    func testEveryNewItemUploadsASlugTheBotItemTableKnows() throws {
        let known = try botItemNames()
        XCTAssertTrue(known.contains("leftovers"), "the parser reads constant keys")
        XCTAssertEqual(ItemKind.championBattleItems.count, 41)
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
