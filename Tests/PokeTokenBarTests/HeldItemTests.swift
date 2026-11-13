import Foundation
import XCTest
@testable import PokeTokenBar

private struct HeldNoProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class HeldItemTests: XCTestCase {
    private func entry(_ species: Int, id: String, released: Bool = false) -> DexEntry {
        var entry = DexEntry(baseID: species, finalID: species, chainOrder: [species], rarity: .common, caughtAt: nil,
                             profile: PokemonProfile.generate(seed: 7, instanceID: id),
                             releasedAt: released ? Date(timeIntervalSince1970: 1) : nil)
        entry.id = id
        return entry
    }

    private func state(inventory: [ItemKind: Int] = [:], held: [String: ItemKind] = [:]) -> CompanionState {
        var state = CompanionState()
        state.installBaselineSet = true
        state.dex = [entry(25, id: "pikachu"), entry(10, id: "caterpie"), entry(12, id: "gone", released: true)]
        state.inventory = Dictionary(uniqueKeysWithValues: inventory.map { ($0.key.rawValue, $0.value) })
        state.heldItems = held.mapValues(\.rawValue)
        return state
    }

    private func store(_ state: CompanionState) throws -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("held-\(UUID().uuidString).json")
        try JSONEncoder().encode(state).write(to: url)
        return CompanionStore(provider: HeldNoProvider(), clock: { Date(timeIntervalSince1970: 1_700_000_000) },
                              fileURL: url, rng: SeededRNG(seed: 1))
    }

    func testEquipMovesTheItemOutOfTheBag() throws {
        let store = try store(state(inventory: [.leftovers: 2]))

        XCTAssertTrue(store.equip(.leftovers, to: "pikachu"))

        XCTAssertEqual(store.heldItem(of: "pikachu"), .leftovers)
        XCTAssertEqual(store.itemCount(.leftovers), 1)
    }

    func testUnequipReturnsTheItemToTheBag() throws {
        let store = try store(state(inventory: [.leftovers: 1]))
        store.equip(.leftovers, to: "pikachu")
        XCTAssertEqual(store.itemCount(.leftovers), 0)

        XCTAssertTrue(store.unequip(from: "pikachu"))

        XCTAssertNil(store.heldItem(of: "pikachu"))
        XCTAssertEqual(store.itemCount(.leftovers), 1)
    }

    func testEquippingAnotherItemSwapsTheFirstBackToTheBag() throws {
        let store = try store(state(inventory: [.leftovers: 1, .lifeOrb: 1]))
        store.equip(.leftovers, to: "pikachu")

        XCTAssertTrue(store.equip(.lifeOrb, to: "pikachu"))

        XCTAssertEqual(store.heldItem(of: "pikachu"), .lifeOrb)
        XCTAssertEqual(store.itemCount(.leftovers), 1)
        XCTAssertEqual(store.itemCount(.lifeOrb), 0)
    }

    func testEquipRefusesWhatTheBagDoesNotHaveOrCannotBeHeld() throws {
        let store = try store(state(inventory: [.rareCandy: 1]))

        XCTAssertFalse(store.equip(.leftovers, to: "pikachu"))
        XCTAssertFalse(store.equip(.rareCandy, to: "pikachu"))
        XCTAssertNil(store.heldItem(of: "pikachu"))
        XCTAssertEqual(store.itemCount(.rareCandy), 1)
    }

    func testEquipRefusesAReleasedOrUnknownPokemon() throws {
        let store = try store(state(inventory: [.leftovers: 1]))

        XCTAssertFalse(store.equip(.leftovers, to: "gone"))
        XCTAssertFalse(store.equip(.leftovers, to: "nobody"))
        XCTAssertEqual(store.itemCount(.leftovers), 1)
    }

    func testAnItemHeldByAReleasedPokemonComesBackWhenTheSaveLoads() throws {
        let store = try store(state(held: ["gone": .focusSash]))

        XCTAssertNil(store.heldItem(of: "gone"))
        XCTAssertEqual(store.itemCount(.focusSash), 1)
    }

    func testReturnOrphanedHeldItemsKeepsTheHoldersOwnItem() {
        var state = state(held: ["pikachu": .lifeOrb, "gone": .charcoal])
        state.heldItems["caterpie"] = "retiredItem"

        state.returnOrphanedHeldItems()

        XCTAssertEqual(state.heldItems, ["pikachu": ItemKind.lifeOrb.rawValue])
        XCTAssertEqual(state.inventory, [ItemKind.charcoal.rawValue: 1])
    }

    func testSavesWithoutHeldItemsStillDecode() throws {
        let json = #"{"installBaselineSet":true,"usedSinceInstall":900,"lastDate":"d","dex":[],"inventory":{"mint":1}}"#

        let state = try JSONDecoder().decode(CompanionState.self, from: Data(json.utf8))

        XCTAssertEqual(state.heldItems, [:])
        XCTAssertEqual(state.inventory, ["mint": 1])
    }

    func testPartyCarriesTheHeldItemSlugOfTheFighter() {
        let state = state(held: ["pikachu": .choiceScarf])

        let pikachu = BattleEntry.party(state: state, slot: BattleEntrySlot(instanceID: "pikachu"), rentalSpeciesID: 4)
        let caterpie = BattleEntry.party(state: state, slot: BattleEntrySlot(instanceID: "caterpie"), rentalSpeciesID: 4)

        XCTAssertEqual(pikachu.first?.heldItem, "choice-scarf")
        XCTAssertNil(caterpie.first?.heldItem)
    }

    func testUploadBodyHasHeldItemOnlyWhenHolding() throws {
        let holding = PartyMember(pokemonID: 25, level: 30, shiny: false, ivs: nil, heldItem: "life-orb")
        let bare = PartyMember(pokemonID: 25, level: 30, shiny: false, ivs: nil)

        let withItem = try PartyPayload(appVersion: nil, party: [holding]).encoded()
        let without = try PartyPayload(appVersion: nil, party: [bare]).encoded()

        XCTAssertTrue(String(decoding: withItem, as: UTF8.self).contains(#""held_item":"life-orb""#))
        XCTAssertFalse(String(decoding: without, as: UTF8.self).contains("held_item"))
    }

    func testEveryHeldItemHasASlugAHeldCategoryAndAPrice() {
        let held = ItemKind.allCases.filter(\.isHeldItem)

        XCTAssertEqual(held.count, 7)
        XCTAssertTrue(held.allSatisfy { $0.category == .heldItem && $0.shopPrice == HeldItem.price && !$0.isEvolutionStone })
        XCTAssertEqual(Set(held.compactMap(\.heldItemSlug)).count, 7)
    }

    func testShopShowsTheHeldItemCategory() throws {
        let store = try store(state())

        XCTAssertTrue(store.shopCategories.contains(.heldItem))
        XCTAssertEqual(Set(store.shopEntries(in: .heldItem).compactMap { entry -> ItemKind? in
            if case .item(let kind) = entry { return kind } else { return nil }
        }), Set(ItemKind.allCases.filter(\.isHeldItem)))
    }
}
