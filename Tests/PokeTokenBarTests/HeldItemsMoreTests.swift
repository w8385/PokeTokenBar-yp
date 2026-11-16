import Foundation
import XCTest
@testable import PokeTokenBar

private func node(_ id: Int, _ children: [EvoNode] = [], item: String? = nil) -> EvoNode {
    EvoNode(speciesID: id, children: children,
            methods: item.map { [EvoMethod(trigger: "use-item", item: $0)] } ?? [EvoMethod(trigger: "level-up")])
}

private struct LineProvider: PokeProviding {
    let tree: EvoNode
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: tree.speciesID, tree: tree, rarity: .common, names: [:])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class EverstoneTests: XCTestCase {
    private func store(tree: EvoNode, state: CompanionState = CompanionState(),
                       inventory: [ItemKind: Int] = [:]) throws -> CompanionStore {
        var state = state
        state.installBaselineSet = true
        for (kind, count) in inventory { state.inventory[kind.rawValue] = count }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("everstone-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let suite = "everstone-\(UUID())"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        return CompanionStore(provider: LineProvider(tree: tree), clock: { Date(timeIntervalSince1970: 1_700_000_000) },
                              fileURL: file, rng: SeededRNG(seed: 1), dittoDisguiseRollingEnabled: false,
                              defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
    }

    private func hatched(tree: EvoNode, inventory: [ItemKind: Int]) async throws -> (CompanionStore, String) {
        let s = try store(tree: tree, inventory: inventory)
        await s.hatch(baseID: tree.speciesID)
        return (s, try XCTUnwrap(s.state.active?.profile?.instanceID))
    }

    func testAHolderKeepsItsFormWhileGrowthBanksAndEvolvesWhenTheStoneComesOff() async throws {
        let (s, id) = try await hatched(tree: node(1, [node(2, [node(3)])]), inventory: [.everstone: 1])
        XCTAssertTrue(s.equip(.everstone, to: id))
        let threshold = s.tokensToNext

        s.applyUsage(threshold + 5)
        s.applyUsage(threshold)

        XCTAssertEqual(s.currentSpeciesID, 1)
        XCTAssertEqual(s.state.active?.usedAtStage, 2 * threshold + 5, "growth keeps banking at the current stage")
        XCTAssertTrue(s.unequip(from: id))
        XCTAssertEqual(s.currentSpeciesID, 2, "the stone comes off and the waiting evolution happens")
        XCTAssertNotNil(s.state.active, "it did not graduate past the form it was held at")
    }

    func testTheEvolutionResumesOnTheNextUsageTickAfterAnotherItemReplacesTheStone() async throws {
        let (s, id) = try await hatched(tree: node(1, [node(2)]), inventory: [.everstone: 1, .leftovers: 1])
        XCTAssertTrue(s.equip(.everstone, to: id))
        s.applyUsage(s.tokensToNext)
        XCTAssertEqual(s.currentSpeciesID, 1)

        XCTAssertTrue(s.equip(.leftovers, to: id))

        XCTAssertEqual(s.currentSpeciesID, 2)
        XCTAssertEqual(s.itemCount(.everstone), 1)
    }

    func testAnEvolutionStoneIsKeptWhileTheHolderWearsTheEverstone() async throws {
        let (s, id) = try await hatched(tree: node(1, [node(2, item: "fire-stone")]),
                                        inventory: [.everstone: 1, .fireStone: 1])
        XCTAssertTrue(s.equip(.everstone, to: id))

        XCTAssertEqual(s.useEvolutionStone(.fireStone), .everstone)
        XCTAssertEqual(s.itemCount(.fireStone), 1, "the stone is not used up")
        XCTAssertEqual(s.currentSpeciesID, 1)

        XCTAssertTrue(s.unequip(from: id))
        XCTAssertEqual(s.useEvolutionStone(.fireStone), .evolved)
        XCTAssertEqual(s.currentSpeciesID, 2)
    }

    func testALinkingCordDoesNothingOnAnEverstoneHolderAndIsNotSpent() async throws {
        var state = CompanionState()
        var entry = DexEntry(baseID: 1, finalID: 1, chainOrder: [1], rarity: .common, caughtAt: nil,
                             profile: PokemonProfile.generate(seed: 7, instanceID: "kadabra"))
        entry.id = "kadabra"
        state.dex = [entry]
        state.heldItems = ["kadabra": ItemKind.everstone.rawValue]
        let s = try store(tree: node(1), state: state, inventory: [.linkingCord: 1])

        let result = await s.useLinkingCord(on: "kadabra")

        XCTAssertEqual(result, .everstone)
        XCTAssertEqual(s.itemCount(.linkingCord), 1)
    }

    func testTheNoteIsOneLineNamingTheStoneInEveryLanguage() {
        XCTAssertEqual(L(.ko).heldItemEffect(.everstone), "변함없는돌: 진화하지 않아요")
        for language in AppLanguage.allCases {
            let note = L(language).heldItemEffect(.everstone)
            XCTAssertTrue(note.hasPrefix(L(language).itemName(.everstone)), "\(language)")
            XCTAssertFalse(note.contains("\n"), "\(language)")
        }
    }

    func testTheEverstoneIsUploadedAsASlugTheBotIgnores() {
        var state = CompanionState()
        state.heldItems = ["a": ItemKind.everstone.rawValue]
        XCTAssertEqual(state.heldItemSlug(of: "a"), "everstone", "the bot ignores a slug it does not know")
    }
}

final class NewItemsClauseTests: XCTestCase {
    private func state(held: [String: String]) -> CompanionState {
        var state = CompanionState()
        state.dex = ["a", "b"].enumerated().map { index, id in
            var entry = DexEntry(baseID: 10 + index, finalID: 10 + index, chainOrder: [10 + index], rarity: .common,
                                 caughtAt: nil, profile: PokemonProfile.generate(seed: 7, instanceID: id))
            entry.id = id
            return entry
        }
        state.heldItems = held
        return state
    }

    func testTheItemClauseCoversEveryNewHeldItem() {
        let slots = [BattleEntrySlot(instanceID: "a"), BattleEntrySlot(instanceID: "b")]
        for kind in ItemKind.allCases where kind.heldItemSlug != nil {
            let state = state(held: ["a": kind.rawValue, "b": kind.rawValue])

            XCTAssertEqual(BattleEntry.duplicateItemHolders(state: state, slots: slots), ["b"], "\(kind)")
            XCTAssertTrue(BattleEntry.equipClash(kind.rawValue, onto: "b", state: self.state(held: ["a": kind.rawValue]),
                                                 slots: slots), "\(kind)")
            let party = BattleEntry.party(state: state, slots: slots, moveChoices: [:], rentalSpeciesID: 4)
            XCTAssertEqual(party.map(\.heldItem), [kind.heldItemSlug, nil], "\(kind)")
        }
    }

    func testDifferentNewItemsDoNotClash() {
        let slots = [BattleEntrySlot(instanceID: "a"), BattleEntrySlot(instanceID: "b")]
        let state = state(held: ["a": ItemKind.quickClaw.rawValue, "b": ItemKind.everstone.rawValue])

        XCTAssertEqual(BattleEntry.duplicateItemHolders(state: state, slots: slots), [])
        XCTAssertFalse(BattleEntry.equipClash(ItemKind.sitrusBerry.rawValue, onto: "b", state: state, slots: [slots[1]]))
    }
}

final class MoreHeldItemsTests: XCTestCase {
    private var newItems: [ItemKind] {
        ItemKind.allCases.filter(\.isHeldItem)
    }

    func testEveryItemTheBotKnowsCanBeBoughtAndNothingElseIsUploaded() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("bot/ypoke/items.py"), encoding: .utf8)
        for kind in ItemKind.allCases {
            guard let slug = kind.heldItemSlug, kind != .everstone else { continue }
            XCTAssertTrue(source.contains("\"\(slug)\""), "the bot has no item \(slug)")
        }
    }

    func testTheShopSellsEveryBattleItemAtTheHeldItemTier() {
        let battle: [ItemKind] = [.everstone, .choiceSpecs, .assaultVest, .eviolite, .rockyHelmet, .sitrusBerry, .lumBerry,
                                  .whiteHerb, .blackSludge, .shellBell, .bigRoot, .muscleBand, .wiseGlasses, .scopeLens,
                                  .quickClaw, .brightPowder, .wideLens, .weaknessPolicy, .focusBand, .flameOrb, .toxicOrb,
                                  .heatRock, .dampRock, .smoothRock, .icyRock]
        let boosts: [ItemKind] = [.mysticWater, .miracleSeed, .magnet, .neverMeltIce, .blackBelt, .poisonBarb, .softSand,
                                  .sharpBeak, .twistedSpoon, .silverPowder, .hardStone, .spellTag, .dragonFang,
                                  .blackGlasses, .silkScarf, .fairyFeather]
        for kind in battle + boosts {
            XCTAssertTrue(kind.isHeldItem, "\(kind)")
            XCTAssertEqual(kind.shopPrice, HeldItem.price, "\(kind)")
            XCTAssertEqual(kind.category, .heldItem, "\(kind)")
            XCTAssertTrue(kind.isEquippable, "\(kind)")
        }
        XCTAssertTrue(newItems.count >= 7 + battle.count + boosts.count)
    }

    func testEveryTypeHasOneBoostItem() {
        let types = ItemKind.allCases.compactMap(\.boostedType)
        XCTAssertEqual(Set(types).count, 18)
        XCTAssertEqual(types.count, 18, "no type has two items")
    }

    func testMetalCoatAndRazorClawFightWithoutLeavingTheEvolutionShelf() {
        for kind in [ItemKind.metalCoat, .razorClaw] {
            XCTAssertEqual(kind.heldItemSlug, kind.evolutionHeldSlug)
            XCTAssertFalse(kind.isHeldItem)
            XCTAssertEqual(kind.category, .evolution)
            XCTAssertEqual(kind.shopPrice, EvolutionStone.price)
            XCTAssertTrue(kind.isEquippable)
        }
        XCTAssertEqual(ItemKind.metalCoat.boostedType, "steel")
    }

    func testEquippedItemsAreUploadedBySlug() {
        for kind in newItems + [.metalCoat, .razorClaw] {
            var state = CompanionState()
            state.heldItems = ["a": kind.rawValue]
            XCTAssertEqual(state.heldItemSlug(of: "a"), kind.heldItemSlug, "\(kind)")
        }
    }

    func testEveryBattleItemHasAnOfficialNameAndAnEffectInEveryLanguage() {
        for kind in newItems + [.metalCoat, .razorClaw] {
            for language in AppLanguage.allCases {
                let l = L(language)
                XCTAssertFalse(l.heldItemEffect(kind).isEmpty, "\(kind) \(language)")
                XCTAssertFalse(l.itemName(kind).isEmpty, "\(kind) \(language)")
                XCTAssertNotEqual(l.itemName(kind), kind.heldItemSlug, "\(kind) \(language) shows the slug")
            }
            XCTAssertFalse(L(.ko).itemDescription(kind).isEmpty, "\(kind)")
        }
        XCTAssertEqual(L(.ko).itemName(.everstone), "변함없는돌")
    }

    func testTypeBoostTextNamesTheTypeInTheReadersLanguage() {
        XCTAssertEqual(L(.ko).heldItemEffect(.charcoal), "불꽃타입 기술의 데미지가 1.2배.")
        XCTAssertEqual(L(.en).heldItemEffect(.fairyFeather), "Fairy-type moves deal ×1.2 damage.")
        XCTAssertTrue(L(.ko).itemAppNote(.metalCoat).contains("강철타입 기술의 데미지가 1.2배."))
    }
}
