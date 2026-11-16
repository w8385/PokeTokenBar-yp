import Foundation
import XCTest
@testable import PokeTokenBar

private struct OfflineProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class GymStoreTests: XCTestCase {
    private func entry(_ species: Int, id: String, level: Int = 30) -> DexEntry {
        var profile = PokemonProfile.generate(seed: UInt64(species), instanceID: id)
        profile.level = level
        var entry = DexEntry(baseID: species, finalID: species, chainOrder: [species], rarity: .common, caughtAt: nil,
                             isShiny: false, profile: profile, names: [species: ["ko": "\(species)", "en": "\(species)"]])
        entry.id = id
        return entry
    }

    private func makeState(owning count: Int) -> CompanionState {
        var state = CompanionState()
        state.language = .ko
        state.dex = (0..<count).map { entry(10 + $0, id: "mon\($0)", level: 20 + $0) }
        return state
    }

    private func store(_ state: CompanionState, file: URL) throws -> CompanionStore {
        try JSONEncoder().encode(state).write(to: file)
        return CompanionStore(provider: OfflineProvider(), fileURL: file, rng: SeededRNG(seed: 1))
    }

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("gym-store-\(UUID()).json")
    }

    private var gym: GymOpponent { GymFixtures.catalog().region("kanto")!.gyms[1] }

    func testFirstClearIsSavedAndNotGrantedAgainAfterARelaunch() throws {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let first = try store(makeState(owning: 1), file: file)
        let reward = try XCTUnwrap(GymRewards.reward(for: gym, region: "kanto", badges: first.state.gymBadges,
                                                     ownedTMs: MachineMove.ownedIDs(in: first.state.inventory)))
        let tm = try XCTUnwrap(reward.tmMoveID)

        first.applyGymReward(reward, trainer: "관장2", region: "Kanto")
        XCTAssertTrue(first.ownsTM(tm))
        XCTAssertTrue(first.state.gymBadges.hasGymBadge("kanto", index: 2))
        XCTAssertEqual(first.state.inventory[MachineMove.inventoryKey(tm)], 1)

        let relaunched = CompanionStore(provider: OfflineProvider(), fileURL: file, rng: SeededRNG(seed: 1))
        XCTAssertTrue(relaunched.state.gymBadges.hasGymBadge("kanto", index: 2))
        XCTAssertTrue(relaunched.ownsTM(tm))
        XCTAssertNil(GymRewards.reward(for: gym, region: "kanto", badges: relaunched.state.gymBadges,
                                       ownedTMs: MachineMove.ownedIDs(in: relaunched.state.inventory)))
    }

    func testRewardWithoutATMStillSavesTheBadge() throws {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let store = try store(makeState(owning: 1), file: file)
        let reward = try XCTUnwrap(GymRewards.reward(for: gym, region: "kanto", badges: GymBadges(), ownedTMs: [], catalog: []))
        store.applyGymReward(reward, trainer: "관장2", region: "Kanto")

        XCTAssertTrue(store.state.gymBadges.hasGymBadge("kanto", index: 2))
        XCTAssertTrue(MachineMove.ownedIDs(in: store.state.inventory).isEmpty)
    }

    func testRewardAnnouncesItselfOnThePet() throws {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let store = try store(makeState(owning: 1), file: file)
        let reward = try XCTUnwrap(GymRewards.reward(for: gym, region: "kanto", badges: GymBadges(), ownedTMs: []))
        let before = store.latestEvent?.seq ?? 0
        store.applyGymReward(reward, trainer: "관장2", region: "Kanto")

        XCTAssertGreaterThan(store.latestEvent?.seq ?? 0, before)
        XCTAssertTrue(store.latestEvent?.text.contains("관장2") == true)
    }

    func testTeamIsTheWholeEntryUpToSixWithItsChosenMoves() {
        let state = makeState(owning: 8)
        let slots = (0..<7).map { BattleEntrySlot(instanceID: "mon\($0)") }
        let choices = ["mon1": MoveChoice(pokemonID: 11, moves: [33, 45])]
        let team = GymTeam.team(state: state, slots: slots, moveChoices: choices, rentalSpeciesID: 1)

        XCTAssertEqual(team.members.count, 6)
        XCTAssertEqual(team.ids.count, 6)
        XCTAssertEqual(team.members[1].moves, [33, 45])
        XCTAssertFalse(team.ids.contains { $0.hasPrefix("rental") })
    }

    func testTMMoveIsDroppedFromTheTeamWhileTheTMIsNotOwned() {
        var state = makeState(owning: 1)
        let choice = ["mon0": MoveChoice(pokemonID: 10, moves: [33, 85], machine: [85])]
        let slots = [BattleEntrySlot(instanceID: "mon0")]

        XCTAssertEqual(GymTeam.team(state: state, slots: slots, moveChoices: choice, rentalSpeciesID: 1).members[0].moves, [33])
        state.inventory[MachineMove.inventoryKey(85)] = 1
        XCTAssertEqual(GymTeam.team(state: state, slots: slots, moveChoices: choice, rentalSpeciesID: 1).members[0].moves, [33, 85])
    }

    func testNothingOwnedFightsWithTheRentalStarter() {
        let team = GymTeam.team(state: CompanionState(), slots: [], moveChoices: [:], rentalSpeciesID: 4)

        XCTAssertEqual(team.ids, [GymTeam.rentalID(4)])
        XCTAssertEqual(team.members.map(\.pokemonID), [4])
        XCTAssertEqual(team.members.first?.rental, true)
    }

    func testChangingTheRentalStarterChangesTheTeamIdentity() {
        let first = GymTeam.team(state: CompanionState(), slots: [], moveChoices: [:], rentalSpeciesID: 4)
        let second = GymTeam.team(state: CompanionState(), slots: [], moveChoices: [:], rentalSpeciesID: 7)

        XCTAssertNotEqual(first.ids, second.ids)
    }
}
