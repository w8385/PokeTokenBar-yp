import Foundation
import XCTest
@testable import PokeTokenBar

private struct SpeciesClauseProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class SpeciesClauseTests: XCTestCase {
    private static let eternatus = 890, rotom = 479, pikachu = 25, snorlax = 143

    private func entry(_ species: Int, id: String, form: String? = nil) -> DexEntry {
        var profile = PokemonProfile.generate(seed: 7, instanceID: id)
        profile.level = 30
        var entry = DexEntry(baseID: species, finalID: species, chainOrder: [species], rarity: .common, caughtAt: nil,
                             isShiny: false, profile: profile, names: [species: ["ko": id, "en": id]])
        entry.id = id
        entry.form = form.map { PokemonForm($0) }
        return entry
    }

    private func store(_ dex: [DexEntry], held: [String: String] = [:]) -> CompanionStore {
        var state = CompanionState()
        state.installBaselineSet = true
        var profile = PokemonProfile.generate(seed: 7, instanceID: "raised")
        profile.level = 42
        state.active = MonState(baseID: 4, pathIDs: [4, 5], stageIndex: 1, usedAtStage: 0,
                                rarity: .common, totalForms: 3, profile: profile)
        state.dex = dex
        state.heldItems = held
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("species-\(UUID()).json")
        try? JSONEncoder().encode(state).write(to: url)
        return CompanionStore(provider: SpeciesClauseProvider(), fileURL: url, rng: SeededRNG(seed: 1))
    }

    private func battle(_ ids: [String]) -> BattleEntryStore {
        let battle = BattleEntryStore(defaults: UserDefaults(suiteName: "species-\(UUID())")!)
        ids.forEach { battle.add($0) }
        return battle
    }

    private func dex(_ store: CompanionStore, _ id: String) throws -> DexEntry {
        try XCTUnwrap(store.state.dex.first { $0.id == id })
    }

    private func threeEternatus() -> CompanionStore {
        store([entry(Self.eternatus, id: "e1"), entry(Self.eternatus, id: "e2"), entry(Self.pikachu, id: "p"),
               entry(Self.eternatus, id: "e3")])
    }

    func testThePickerHidesTheSameSpeciesIncludingAnotherForm() throws {
        let store = store([entry(Self.rotom, id: "rotom"), entry(Self.rotom, id: "wash", form: "wash"),
                           entry(Self.pikachu, id: "p")])
        let battle = battle(["rotom"])

        XCTAssertEqual(BattleEntry.speciesBlockedCandidates(state: store.state, slots: battle.slots, replacing: nil),
                       ["wash"])
        XCTAssertFalse(battle.place(try dex(store, "wash"), at: 1, in: store))
        XCTAssertEqual(battle.slots.map(\.instanceID), ["rotom"])
    }

    func testReplacingThatSpeciesOwnSlotIsAllowed() throws {
        let store = store([entry(Self.rotom, id: "rotom"), entry(Self.rotom, id: "wash", form: "wash"),
                           entry(Self.pikachu, id: "p")])
        let battle = battle(["p", "rotom"])

        XCTAssertTrue(BattleEntry.speciesBlockedCandidates(state: store.state, slots: battle.slots, replacing: "rotom")
            .isEmpty)
        XCTAssertTrue(battle.place(try dex(store, "wash"), at: 1, in: store))
        XCTAssertEqual(battle.slots.map(\.instanceID), ["p", "wash"])
    }

    func testMembersOfAPreRuleLineupCanStillMoveAndLeave() throws {
        let store = threeEternatus()
        let battle = battle(["e1", "e2", "p"])

        XCTAssertTrue(battle.place(try dex(store, "e2"), at: 0, in: store))
        XCTAssertEqual(battle.slots.map(\.instanceID), ["e2", "e1", "p"])
        battle.move("p", by: -1)
        XCTAssertEqual(battle.slots.map(\.instanceID), ["e2", "p", "e1"])
        XCTAssertTrue(battle.place(try dex(store, "e1"), at: 2, in: store))
        XCTAssertEqual(battle.slots.map(\.instanceID), ["e2", "p"])
    }

    func testAPreRuleSaveWithThreeEternatusUploadsOneAndIsNotRewritten() {
        let store = threeEternatus()
        let slots = battle(["e1", "e2", "p", "e3"]).slots

        let party = BattleEntry.party(state: store.state, slots: slots, moveChoices: [:], rentalSpeciesID: 1)

        XCTAssertEqual(party.map(\.pokemonID), [Self.eternatus, Self.pikachu])
        XCTAssertEqual(BattleEntry.duplicateSpecies(state: store.state, slots: slots), ["e2", "e3"])
        XCTAssertEqual(slots.map(\.instanceID), ["e1", "e2", "p", "e3"])
    }

    func testTheGymTeamSendsTheSameFightersItsIdsName() {
        let store = threeEternatus()
        let slots = battle(["e1", "e2", "p", "e3"]).slots

        let team = GymTeam.team(state: store.state, slots: slots, moveChoices: [:], rentalSpeciesID: 1)

        XCTAssertEqual(team.ids, ["e1", "p"])
        XCTAssertEqual(team.members.map(\.pokemonID), [Self.eternatus, Self.pikachu])
    }

    func testABenchedDuplicateDoesNotTakeAnItemFromALaterFighter() {
        let store = store([entry(Self.eternatus, id: "e1"), entry(Self.eternatus, id: "e2"),
                           entry(Self.snorlax, id: "s")],
                          held: ["e2": "leftovers", "s": "leftovers"])
        let slots = battle(["e1", "e2", "s"]).slots

        let party = BattleEntry.party(state: store.state, slots: slots, moveChoices: [:], rentalSpeciesID: 1)

        XCTAssertEqual(party.map(\.heldItem), [nil, store.state.heldItemSlug(of: "s")])
        XCTAssertTrue(BattleEntry.duplicateItemHolders(state: store.state, slots: slots).isEmpty)
    }

    func testDistinctSpeciesUploadAsPicked() {
        let store = store([entry(Self.eternatus, id: "e1"), entry(Self.pikachu, id: "p"), entry(Self.snorlax, id: "s")])
        let slots = battle(["s", "e1", "p"]).slots

        let party = BattleEntry.party(state: store.state, slots: slots, moveChoices: [:], rentalSpeciesID: 1)

        XCTAssertEqual(party.map(\.pokemonID), [Self.snorlax, Self.eternatus, Self.pikachu])
        XCTAssertTrue(BattleEntry.duplicateSpecies(state: store.state, slots: slots).isEmpty)
    }
}
