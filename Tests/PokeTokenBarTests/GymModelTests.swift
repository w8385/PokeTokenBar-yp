import Foundation
import XCTest
@testable import PokeTokenBar

final class GymModelTests: XCTestCase {
    func testCatalogDecodesTheDocumentedShape() throws {
        let catalog = GymFixtures.catalog()
        let kanto = try XCTUnwrap(catalog.region("kanto"))

        XCTAssertEqual(catalog.regions.map(\.id), ["kanto", "johto"])
        XCTAssertEqual(kanto.gyms.map(\.index), Array(1...8))
        XCTAssertEqual(kanto.elite.badgesNeeded, 8)
        XCTAssertEqual(kanto.elite.battles.map(\.kind), ["elite", "elite", "elite", "elite", "champion"])
        XCTAssertEqual(kanto.elite.battles.last?.run, GymRunPosition(id: "kanto-elite", step: 5, steps: 5))
        XCTAssertEqual(kanto.hideout.battles.map(\.kind), ["grunt", "grunt", "admin", "boss"])
        XCTAssertTrue(kanto.hideout.battles.last?.isRunFinale == true)
        XCTAssertNil(kanto.gyms[0].run)
        XCTAssertEqual(kanto.opponent("kanto-champion")?.kind, "champion")
    }

    func testTrainerTextFollowsTheLanguageAndFallsBackToEnglish() throws {
        let gym = try XCTUnwrap(GymFixtures.catalog().region("kanto")?.gyms.first)

        XCTAssertEqual(gym.trainer.displayName(.ko), "관장1")
        XCTAssertEqual(gym.trainer.displayName(.en), "Leader 1")
        XCTAssertEqual(gym.trainer.displayName(.fr), "Leader 1")
        XCTAssertEqual(gym.trainer.displayName(.ja), "Leader 1")
    }

    func testOutcomeKeepsHpSharesAndTheMemberThatNeverFought() throws {
        let data = GymFixtures.outcomeData(
            gymID: "kanto-elite-2", kind: "elite", won: true, run: ("kanto-elite", 2, 5, "kanto-elite-1", "kanto-elite-3"),
            carry: [GymFixtures.carryJSON(hp: 80), nil, GymFixtures.carryJSON(hp: 35, status: "par")])
        let outcome = try GymBattleOutcome.decode(data)

        XCTAssertEqual(outcome.playerTeam.map(\.hp), [80, 0, 35, nil, 100, 60])
        XCTAssertEqual(outcome.run?.next, "kanto-elite-3")
        XCTAssertEqual(outcome.carry, [GymCarry(hp: 80, status: nil), nil, GymCarry(hp: 35, status: "par")])
        XCTAssertEqual(outcome.log[1].lines[0].side, nil)
    }

    func testBattleRequestCarriesSixMembersWithMovesAndExplicitNullCarry() throws {
        let team = (1...6).map { PartyMember(pokemonID: $0, level: 50, shiny: false, ivs: nil, moves: [33, 45, 52, 84]) }
        let request = GymBattleRequest(gymId: "kanto-elite-3", team: team,
                                       carried: [nil, GymCarry(hp: 40, status: nil), GymCarry(hp: 12, status: "brn"), nil, nil, nil])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: request.encoded()) as? [String: Any])
        let members = try XCTUnwrap(json["team"] as? [[String: Any]])
        let carried = try XCTUnwrap(json["carried"] as? [Any])

        XCTAssertEqual(json["gym_id"] as? String, "kanto-elite-3")
        XCTAssertEqual(members.count, 6)
        XCTAssertEqual(members[0]["moves"] as? [Int], [33, 45, 52, 84])
        XCTAssertEqual(members[0]["pokemon_id"] as? Int, 1)
        XCTAssertEqual(carried.count, 6)
        XCTAssertTrue(carried[0] is NSNull)
        let second = try XCTUnwrap(carried[1] as? [String: Any])
        XCTAssertEqual(second["hp"] as? Int, 40)
        XCTAssertTrue(second["status"] is NSNull)
        XCTAssertEqual((carried[2] as? [String: Any])?["status"] as? String, "brn")
    }

    func testBattleRequestOmitsCarriedForAStandAloneGym() throws {
        let request = GymBattleRequest(gymId: "kanto-1", team: [PartyMember(pokemonID: 25, level: 30, shiny: false, ivs: nil)])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: request.encoded()) as? [String: Any])

        XCTAssertNil(json["carried"])
    }

    func testSaveFromBeforeGymsDecodesWithoutBadges() throws {
        var state = CompanionState()
        state.gymBadges.update("kanto") { $0.gyms = [1, 2] }
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        XCTAssertNotNil(json["gymBadges"])
        json.removeValue(forKey: "gymBadges")

        let old = try JSONDecoder().decode(CompanionState.self, from: JSONSerialization.data(withJSONObject: json))

        XCTAssertEqual(old.gymBadges, GymBadges())
    }

    func testBadgesSurviveARoundTripAndAJunkRegionDoesNotLoseTheRest() throws {
        var badges = GymBadges()
        badges.update("kanto") { $0.gyms = [1, 8]; $0.hallOfFame = true }
        badges.update("johto") { $0.orgBeaten = true }
        XCTAssertEqual(try JSONDecoder().decode(GymBadges.self, from: JSONEncoder().encode(badges)), badges)

        let junk = Data(#"{"regions":{"kanto":{"gyms":[1,2],"hallOfFame":"yes"}}}"#.utf8)
        let decoded = try JSONDecoder().decode(GymBadges.self, from: junk)
        XCTAssertEqual(decoded.region("kanto").gyms, [1, 2])
        XCTAssertFalse(decoded.region("kanto").hallOfFame)
    }

    func testEliteFourOpensWithEightBadgesOnly() throws {
        let kanto = try XCTUnwrap(GymFixtures.catalog().region("kanto"))
        var badges = GymBadges()
        badges.update("kanto") { $0.gyms = Set(1...7) }
        badges.update("johto") { $0.gyms = Set(1...8) }

        XCTAssertFalse(badges.eliteOpen(kanto))
        badges.update("kanto") { $0.gyms.insert(8) }
        XCTAssertTrue(badges.eliteOpen(kanto))
        XCTAssertEqual(badges.totalBadges, 16)
    }
}

final class GymRewardTests: XCTestCase {
    private let catalog = GymFixtures.catalog()

    private func opponent(_ id: String) throws -> GymOpponent {
        try XCTUnwrap(catalog.region("kanto")?.opponent(id))
    }

    func testFirstGymWinGivesTheBadgeAndATypeMatchingTM() throws {
        let gym = try opponent("kanto-3")
        let reward = try XCTUnwrap(GymRewards.reward(for: gym, region: "kanto", badges: GymBadges(), ownedTMs: []))
        let move = try XCTUnwrap(MachineCatalog.moves.first { $0.id == reward.tmMoveID })

        XCTAssertEqual(reward.kind, .gymBadge(index: 3))
        XCTAssertTrue(reward.badges.hasGymBadge("kanto", index: 3))
        XCTAssertEqual(move.type, "electric")
        XCTAssertLessThan(move.power, GymRewards.finaleMinPower)
        XCTAssertFalse(move.isWeather)
    }

    func testRewinGivesNothing() throws {
        let gym = try opponent("kanto-3")
        var badges = GymBadges()
        badges.update("kanto") { $0.gyms = [3] }

        XCTAssertNil(GymRewards.reward(for: gym, region: "kanto", badges: badges, ownedTMs: []))
    }

    func testTMPickSkipsOwnedMovesAndNeverRepeats() throws {
        let gym = try opponent("kanto-1")
        var owned = Set<Int>()
        var picks: [Int] = []
        for _ in 0..<5 {
            guard let reward = GymRewards.reward(for: gym, region: "kanto", badges: GymBadges(), ownedTMs: owned),
                  let move = reward.tmMoveID else { break }
            XCTAssertFalse(owned.contains(move))
            picks.append(move)
            owned.insert(move)
        }

        XCTAssertGreaterThan(picks.count, 1)
        XCTAssertEqual(Set(picks).count, picks.count)
    }

    func testLaterGymsOfferStrongerMovesOfTheSameType() throws {
        let catalog = MachineCatalog.moves
        let first = try XCTUnwrap(GymRewards.gymTM(type: "water", index: 1, owned: [], catalog: catalog))
        let last = try XCTUnwrap(GymRewards.gymTM(type: "water", index: 8, owned: [], catalog: catalog))
        let power = { (id: Int) in catalog.first { $0.id == id }?.power ?? 0 }

        XCTAssertLessThanOrEqual(power(first), power(last))
    }

    func testChampionAndBossGiveAHeavyHitterAndTheSameOneEachTime() throws {
        let champion = try opponent("kanto-champion")
        let boss = try opponent("kanto-hideout-4")
        let hall = try XCTUnwrap(GymRewards.reward(for: champion, region: "kanto", badges: GymBadges(), ownedTMs: []))
        let again = try XCTUnwrap(GymRewards.reward(for: champion, region: "kanto", badges: GymBadges(), ownedTMs: []))
        let org = try XCTUnwrap(GymRewards.reward(for: boss, region: "kanto", badges: GymBadges(), ownedTMs: []))

        XCTAssertEqual(hall.kind, .hallOfFame)
        XCTAssertEqual(hall.tmMoveID, again.tmMoveID)
        XCTAssertEqual(org.kind, .orgBadge)
        for reward in [hall, org] {
            let move = try XCTUnwrap(MachineCatalog.moves.first { $0.id == reward.tmMoveID })
            XCTAssertGreaterThanOrEqual(move.power, GymRewards.finaleMinPower)
        }
        XCTAssertTrue(hall.badges.region("kanto").hallOfFame)
        XCTAssertTrue(org.badges.region("kanto").orgBeaten)
    }

    func testEliteMembersGruntsAndAdminsGiveNothing() throws {
        for id in ["kanto-elite-1", "kanto-elite-4", "kanto-hideout-1", "kanto-hideout-3"] {
            XCTAssertNil(GymRewards.reward(for: try opponent(id), region: "kanto", badges: GymBadges(), ownedTMs: []), id)
        }
    }

    func testAnExhaustedPoolStillGivesTheBadge() throws {
        let gym = try opponent("kanto-1")
        let reward = try XCTUnwrap(GymRewards.reward(for: gym, region: "kanto", badges: GymBadges(), ownedTMs: [], catalog: []))

        XCTAssertNil(reward.tmMoveID)
        XCTAssertTrue(reward.badges.hasGymBadge("kanto", index: 1))
    }
}
