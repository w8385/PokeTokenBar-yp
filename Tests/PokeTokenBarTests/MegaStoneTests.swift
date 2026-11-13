import Foundation
import XCTest
@testable import PokeTokenBar

private struct MegaNoProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class MegaStoneTests: XCTestCase {
    private func entry(_ finalID: Int, id: String) -> DexEntry {
        var entry = DexEntry(baseID: finalID, finalID: finalID, chainOrder: [finalID], rarity: .common, caughtAt: nil,
                             profile: PokemonProfile.generate(seed: 7, instanceID: id))
        entry.id = id
        return entry
    }

    private func state(inventory: [String: Int] = [:], held: [String: String] = [:], tokens: Int = 0) -> CompanionState {
        var state = CompanionState()
        state.installBaselineSet = true
        state.usedSinceInstall = tokens
        state.dex = [entry(6, id: "zard"), entry(25, id: "pikachu"), entry(718, id: "zygarde")]
        state.inventory = inventory
        state.heldItems = held
        return state
    }

    private func store(_ state: CompanionState) throws -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mega-\(UUID().uuidString).json")
        try JSONEncoder().encode(state).write(to: url)
        return CompanionStore(provider: MegaNoProvider(), clock: { Date(timeIntervalSince1970: 1_700_000_000) },
                              fileURL: url, rng: SeededRNG(seed: 1))
    }

    private let charizardX = MegaStone.stone(slug: "charizardite-x")!
    private let charizardY = MegaStone.stone(slug: "charizardite-y")!

    func testCatalogHasOneStoneForEveryMegaFormExceptRayquaza() {
        XCTAssertEqual(MegaStone.all.count, 92)
        XCTAssertEqual(Set(MegaStone.all.map(\.slug)).count, 92)
        XCTAssertEqual(Set(MegaStone.all.map(\.megaID)).count, 92)
        XCTAssertTrue(MegaStone.all.allSatisfy { $0.stats.count == 6 && !$0.types.isEmpty && $0.speciesID != 384 })
        XCTAssertEqual(MegaStone.stones(for: 6).map(\.slug), ["charizardite-x", "charizardite-y"])
    }

    func testLookupByInventoryKeyAndNames() {
        XCTAssertEqual(MegaStone.stone(inventoryKey: "mega-stone:charizardite-x"), charizardX)
        XCTAssertNil(MegaStone.stone(inventoryKey: "mega-stone:nothing"))
        XCTAssertNil(MegaStone.stone(inventoryKey: "leftovers"))
        XCTAssertEqual(charizardX.name(in: .en), "Charizardite X")
        XCTAssertEqual(charizardX.name(in: .ru), "Charizardite X")
        XCTAssertEqual(charizardX.variantSuffix, "X")
        XCTAssertNil(MegaStone.stone(slug: "venusaurite")?.variantSuffix)
    }

    func testBuyingSpendsTokensAndAddsTheStone() throws {
        let store = try store(state(tokens: 10_000_000_000))
        let price = store.price(of: .megaStone(charizardX))

        XCTAssertTrue(store.buy(charizardX))

        XCTAssertEqual(store.megaStoneCount(charizardX), 1)
        XCTAssertEqual(store.availableTokens, 10_000_000_000 - price)
    }

    func testBuyingRefusesWhenTheBalanceIsShort() throws {
        let store = try store(state(tokens: 1_000_000))

        XCTAssertFalse(store.canBuy(charizardX))
        XCTAssertFalse(store.buy(charizardX))
        XCTAssertEqual(store.megaStoneCount(charizardX), 0)
    }

    func testStonesSellOnlyInTheirOwnCategoryAndOwnedSpeciesComeFirst() throws {
        let store = try store(state())

        XCTAssertTrue(store.shopCategories.contains(.megaStone))
        XCTAssertFalse(store.shopEntries.contains { $0.category == .megaStone })
        let entries = store.shopEntries(in: .megaStone)
        XCTAssertEqual(entries.count, 92)
        let slugs = entries.compactMap { entry -> String? in
            if case .megaStone(let stone) = entry { return stone.slug } else { return nil }
        }
        XCTAssertEqual(Array(slugs.prefix(3)), ["charizardite-x", "charizardite-y", "zygardite"])
    }

    func testEquipTakesTheStoneOutOfTheBagAndUnequipReturnsIt() throws {
        let store = try store(state(inventory: [charizardX.inventoryKey: 1]))

        XCTAssertTrue(store.equip(charizardX, to: "zard"))
        XCTAssertEqual(store.heldMegaStone(of: "zard"), charizardX)
        XCTAssertEqual(store.megaStoneCount(charizardX), 0)
        XCTAssertNil(store.heldItem(of: "zard"))

        XCTAssertTrue(store.unequip(from: "zard"))
        XCTAssertNil(store.heldMegaStone(of: "zard"))
        XCTAssertEqual(store.megaStoneCount(charizardX), 1)
    }

    func testEquippingAStoneSwapsAHeldItemBackAndAnotherStoneToo() throws {
        let store = try store(state(inventory: [ItemKind.leftovers.rawValue: 1, charizardX.inventoryKey: 1,
                                                charizardY.inventoryKey: 1]))
        store.equip(.leftovers, to: "zard")

        XCTAssertTrue(store.equip(charizardX, to: "zard"))
        XCTAssertEqual(store.itemCount(.leftovers), 1)
        XCTAssertTrue(store.equip(charizardY, to: "zard"))
        XCTAssertEqual(store.megaStoneCount(charizardX), 1)
        XCTAssertEqual(store.heldMegaStone(of: "zard"), charizardY)
    }

    func testEquipRefusesAStoneTheBagLacks() throws {
        let store = try store(state())

        XCTAssertFalse(store.equip(charizardX, to: "zard"))
        XCTAssertNil(store.heldMegaStone(of: "zard"))
    }

    func testTheStoneDoesNothingOnAnotherSpecies() throws {
        let store = try store(state(inventory: [charizardX.inventoryKey: 1]))
        store.equip(charizardX, to: "pikachu")

        XCTAssertNil(store.megaStone(of: "pikachu", speciesID: 25))
        XCTAssertNil(store.megaSpriteID(instanceID: "pikachu", speciesID: 25))
        XCTAssertEqual(store.megaStone(of: "pikachu", speciesID: 6), charizardX)
    }

    func testAStoneHeldByAReleasedPokemonOrUnknownStoneIsHandledOnLoad() throws {
        var state = state(held: ["gone": charizardX.inventoryKey, "pikachu": "mega-stone:retired"])
        var gone = entry(10, id: "gone")
        gone.releasedAt = Date(timeIntervalSince1970: 1)
        state.dex.append(gone)
        let store = try store(state)

        XCTAssertNil(store.heldMegaStone(of: "gone"))
        XCTAssertEqual(store.megaStoneCount(charizardX), 1)
        XCTAssertNil(store.state.heldItems["pikachu"])
        XCTAssertEqual(store.state.inventory["mega-stone:retired"], nil)
    }

    func testPartyCarriesTheStoneSlug() {
        let state = state(held: ["zard": charizardX.inventoryKey])

        let party = BattleEntry.party(state: state, slots: [BattleEntrySlot(instanceID: "zard")], rentalSpeciesID: 4)

        XCTAssertEqual(party.first?.heldItem, "charizardite-x")
    }

    func testTheSpriteChangesOnlyWhileTheMatchingStoneIsHeld() throws {
        let store = try store(state(inventory: [charizardX.inventoryKey: 1]))
        XCTAssertTrue(store.setRepresentativeSpeciesID(6))
        XCTAssertNil(store.representativeSubject.megaSpriteID)

        store.equip(charizardX, to: "zard")
        XCTAssertEqual(store.representativeSubject.megaSpriteID, charizardX.megaID)
        XCTAssertEqual(store.representativeSubject.spriteSpeciesID, charizardX.megaID)
        XCTAssertEqual(store.representativeSubject.speciesID, 6)

        store.unequip(from: "zard")
        XCTAssertNil(store.representativeSubject.megaSpriteID)
        XCTAssertEqual(store.representativeSubject.spriteSpeciesID, 6)
    }

    func testAMegaFormWithoutASpriteKeepsTheBaseSprite() throws {
        let zygardite = MegaStone.stone(slug: "zygardite")!
        let store = try store(state(inventory: [zygardite.inventoryKey: 1]))
        store.setRepresentativeSpeciesID(718)

        store.equip(zygardite, to: "zygarde")

        XCTAssertNil(store.representativeSubject.megaSpriteID)
        XCTAssertEqual(store.representativeSubject.spriteSpeciesID, 718)
    }

    func testTheRaisedPokemonShowsTheMegaFormAtHome() throws {
        var state = state(inventory: [charizardX.inventoryKey: 1])
        state.active = MonState(baseID: 4, pathIDs: [4, 5, 6], stageIndex: 2, usedAtStage: 0, rarity: .common, totalForms: 3,
                                profile: PokemonProfile.generate(seed: 5, instanceID: "raised"))
        let store = try store(state)
        XCTAssertNil(store.currentMegaSpriteID)

        store.equip(charizardX, to: "raised")

        XCTAssertEqual(store.currentMegaSpriteID, charizardX.megaID)
        XCTAssertEqual(store.currentSpeciesID, 6)
        XCTAssertEqual(store.representativeSubject.megaSpriteID, charizardX.megaID)
    }

    func testOlderSavesWithStonesStillRoundTrip() throws {
        let original = state(inventory: [charizardX.inventoryKey: 2], held: ["zard": charizardY.inventoryKey])
        let decoded = try JSONDecoder().decode(CompanionState.self, from: JSONEncoder().encode(original))

        XCTAssertEqual(decoded.inventory[charizardX.inventoryKey], 2)
        XCTAssertEqual(decoded.heldItems["zard"], charizardY.inventoryKey)
    }
}
