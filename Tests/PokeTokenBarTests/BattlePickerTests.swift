import Foundation
import XCTest
@testable import PokeTokenBar

private struct OfflineProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class BattlePickerTests: XCTestCase {
    private func entry(_ species: Int, id: String, ko: String, en: String, level: Int = 30,
                       rarity: Rarity = .common, shiny: Bool = false, released: Bool = false) -> DexEntry {
        var profile = PokemonProfile.generate(seed: 7, instanceID: id)
        profile.level = level
        var entry = DexEntry(baseID: species, finalID: species, chainOrder: [species], rarity: rarity, caughtAt: nil,
                             isShiny: shiny, profile: profile,
                             names: [species: ["ko": ko, "en": en]],
                             releasedAt: released ? Date(timeIntervalSince1970: 1) : nil)
        entry.id = id
        return entry
    }

    private func store() -> CompanionStore {
        var state = CompanionState()
        state.language = .ko
        var profile = PokemonProfile.generate(seed: 7, instanceID: "raised")
        profile.level = 42
        state.active = MonState(baseID: 4, pathIDs: [4, 5], stageIndex: 1, usedAtStage: 0,
                                rarity: .common, totalForms: 3, profile: profile)
        state.dex = [
            entry(10, id: "caterpie", ko: "캐터피", en: "Caterpie"),
            entry(25, id: "pikachu", ko: "피카츄", en: "Pikachu", level: 60, rarity: .rare, shiny: true),
            entry(12, id: "gone", ko: "버터플", en: "Butterfree", released: true),
        ]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("battle-picker-\(UUID()).json")
        try? JSONEncoder().encode(state).write(to: url)
        return CompanionStore(provider: OfflineProvider(), fileURL: url, rng: SeededRNG(seed: 1))
    }

    private func entryStore() -> BattleEntryStore {
        BattleEntryStore(defaults: UserDefaults(suiteName: "battle-picker-\(UUID())")!)
    }

    func testSearchFindsAnOwnedCandidateByKoreanName() {
        let store = store()

        XCTAssertEqual(store.filteredBattleCandidates(query: "피카").map(\.id), ["pikachu"])
        XCTAssertEqual(store.filteredBattleCandidates(query: "pikachu").map(\.id), ["pikachu"])
        XCTAssertEqual(store.filteredBattleCandidates(query: "#10").map(\.id), ["caterpie"])
        XCTAssertEqual(store.filteredBattleCandidates(query: "없는이름").map(\.id), [])
    }

    func testPickerListsTheRaisedPokemonFirstThenByLevel() {
        XCTAssertEqual(store().filteredBattleCandidates().map(\.id), ["raised", "pikachu", "caterpie"])
    }

    func testPickerExcludesReleasedIndividuals() {
        let store = store()

        XCTAssertFalse(store.filteredBattleCandidates().map(\.id).contains("gone"))
        XCTAssertEqual(store.filteredBattleCandidates(query: "버터플").map(\.id), [])
    }

    func testRarityAndShinyFiltersNarrowTheGrid() {
        let store = store()

        XCTAssertEqual(store.filteredBattleCandidates(rarity: .rare).map(\.id), ["pikachu"])
        XCTAssertEqual(store.filteredBattleCandidates(shinyOnly: true).map(\.id), ["pikachu"])
        XCTAssertEqual(store.filteredBattleCandidates(rarity: .common, shinyOnly: true).map(\.id), [])
    }

    func testSendingFromTheDexDetailSetsOnlyTheBattleSlot() throws {
        let store = store()
        _ = store.setRepresentativeSpeciesID(10)
        let raisedBefore = store.state.active?.profile?.instanceID
        let pikachu = try XCTUnwrap(store.dexEntries.first { $0.id == "pikachu" })
        let battle = entryStore()

        XCTAssertFalse(battle.isFighting(pikachu, in: store))
        XCTAssertTrue(battle.sendToBattle(pikachu, in: store))

        XCTAssertEqual(battle.slot?.instanceID, "pikachu")
        XCTAssertTrue(battle.isFighting(pikachu, in: store))
        XCTAssertEqual(store.representativeSpeciesID, 10)
        XCTAssertEqual(store.state.active?.profile?.instanceID, raisedBefore)
        XCTAssertEqual(store.state.active?.currentID, 5)
    }

    func testTheRaisedPokemonCanBeSentFromItsSynthesizedCatchLogRow() throws {
        let store = store()
        let raised = try XCTUnwrap(store.dexEntries.first { store.isActiveDexEntry($0) })
        let battle = entryStore()

        XCTAssertTrue(battle.sendToBattle(raised, in: store))

        XCTAssertEqual(battle.slot?.instanceID, "raised")
    }

    func testAReleasedIndividualCannotBeSent() throws {
        let store = store()
        let gone = try XCTUnwrap(store.state.dex.first { $0.id == "gone" })
        let battle = entryStore()

        XCTAssertFalse(battle.sendToBattle(gone, in: store))
        XCTAssertNil(battle.slot)
    }

    func testPickingFromTheDexDoesNotMoveTheBattleSlotOfAnotherPick() throws {
        let store = store()
        let battle = entryStore()
        battle.choose("caterpie")
        let pikachu = try XCTUnwrap(store.dexEntries.first { $0.id == "pikachu" })

        XCTAssertFalse(battle.isFighting(pikachu, in: store))
        XCTAssertEqual(battle.slot?.instanceID, "caterpie")
    }

    func testBattleLevelCapAppliesOnlyAboveFifty() {
        XCTAssertFalse(BattleEntry.isLevelCapped(50))
        XCTAssertTrue(BattleEntry.isLevelCapped(51))
        XCTAssertFalse(BattleEntry.isLevelCapped(12))
    }
}
