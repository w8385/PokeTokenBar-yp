import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// What the bot answers for Pikachu with `egg=1`: `trainingMovesJSON` with Volt Tackle between level-up and machine.
let eggMovesJSON = """
{"ok":true,"default":[84,209],"moves":[
 {"id":84,"name":"Thunder Shock","type":"electric","power":40,"damage_class":"special","accuracy":100,"level":1,"pp":30,"source":"level"},
 {"id":209,"name":"Spark","type":"electric","power":65,"damage_class":"physical","accuracy":100,"level":20,"pp":20,"source":"level"},
 {"id":344,"name":"Volt Tackle","type":"electric","power":120,"damage_class":"physical","accuracy":100,"level":0,"pp":15,"source":"egg"},
 {"id":85,"name":"Thunderbolt","type":"electric","power":90,"damage_class":"special","accuracy":100,"level":0,"pp":15,"source":"machine"},
 {"id":89,"name":"Earthquake","type":"ground","power":100,"damage_class":"physical","accuracy":100,"level":0,"pp":10,"source":"machine"}
]}
"""

@MainActor
final class MirrorHerbTests: XCTestCase {
    private let pikachuID = "pikachu-graduate"
    private let raichuID = "raichu-graduate"
    private let caterpieID = "caterpie-graduate"

    private func store(herbs: Int = 1, tokens: Int = 1_000_000_000) async throws -> CompanionStore {
        let fixture = try TrainingFixture(self)
        let dex = [TrainingFixture.graduate(pikachuID, speciesID: 25), TrainingFixture.graduate(raichuID, speciesID: 26),
                   TrainingFixture.graduate(caterpieID, speciesID: 10)]
        let state = TrainingFixture.state(dex: dex, inventory: herbs > 0 ? ["mirrorHerb": herbs] : [:], tokens: tokens)
        return try await fixture.store(state)
    }

    private func herb(_ s: CompanionStore, _ id: String) -> Bool? { s.trainable(id: id)?.profile.mirrorHerb }

    // MARK: Store

    func testUsingTheHerbSetsTheFlagAndUsesOne() async throws {
        let s = try await store(herbs: 2)
        XCTAssertEqual(s.useMirrorHerb(on: pikachuID), .changed)
        XCTAssertEqual(herb(s, pikachuID), true)
        XCTAssertEqual(s.itemCount(.mirrorHerb), 1)
        XCTAssertEqual(s.state.spentTokens, 0)
        XCTAssertNil(herb(s, raichuID), "only the picked individual")
    }

    func testASecondUseIsRefusedAndUsesNothing() async throws {
        let s = try await store(herbs: 2)
        XCTAssertEqual(s.useMirrorHerb(on: pikachuID), .changed)
        XCTAssertEqual(s.useMirrorHerb(on: pikachuID), .unchanged)
        XCTAssertEqual(s.itemCount(.mirrorHerb), 1)
        let buyer = try await store(herbs: 0)
        XCTAssertEqual(buyer.useMirrorHerb(on: pikachuID), .changed)
        let spent = buyer.state.spentTokens
        XCTAssertEqual(buyer.useMirrorHerb(on: pikachuID), .unchanged)
        XCTAssertEqual(buyer.state.spentTokens, spent, "a second use never buys")
    }

    func testASpeciesWithoutAttackingEggMovesRefusesTheHerb() async throws {
        XCTAssertFalse(EggMoves.hasAttacking(speciesID: 10))
        let s = try await store(herbs: 1)
        XCTAssertEqual(s.useMirrorHerb(on: caterpieID), .unavailable)
        XCTAssertNil(herb(s, caterpieID))
        XCTAssertEqual(s.itemCount(.mirrorHerb), 1)
        XCTAssertFalse(s.trainingTargets(for: .mirrorHerb).contains { $0.id == caterpieID })
    }

    func testAnEvolvedSpeciesQualifiesThroughWhatItEvolvedFrom() async throws {
        XCTAssertTrue(EggMoves.hasAttacking(speciesID: 26), "Raichu has no egg moves of its own; Pichu's count")
        let s = try await store(herbs: 1)
        XCTAssertEqual(s.useMirrorHerb(on: raichuID), .changed)
        let member = try XCTUnwrap(BattleEntry.candidates(in: s.state).first { $0.id == raichuID }?.member)
        XCTAssertEqual(member.pokemonID, 26)
        XCTAssertEqual(member.mirrorHerb, true)
    }

    func testBuyAndUseDeductsOnce() async throws {
        let s = try await store(herbs: 0, tokens: MirrorHerb.price + 5)
        XCTAssertEqual(s.mirrorHerbPayment, .buy(price: MirrorHerb.price))
        XCTAssertEqual(s.useMirrorHerb(on: pikachuID), .changed)
        XCTAssertEqual(herb(s, pikachuID), true)
        XCTAssertEqual(s.state.spentTokens, MirrorHerb.price)
        XCTAssertEqual(s.availableTokens, 5)
        XCTAssertEqual(s.itemCount(.mirrorHerb), 0, "the bought herb is used, not stocked")
    }

    func testShortTokensRefuseWithoutChange() async throws {
        let s = try await store(herbs: 0, tokens: MirrorHerb.price - 1)
        XCTAssertEqual(s.mirrorHerbPayment, .short(price: MirrorHerb.price))
        XCTAssertEqual(s.useMirrorHerb(on: pikachuID), .short)
        XCTAssertNil(herb(s, pikachuID))
        XCTAssertEqual(s.state.spentTokens, 0)
    }

    func testTheBagListsEligibleBoxPokemonAndUsesTheHerbOnOne() async throws {
        let s = try await store(herbs: 1)
        XCTAssertEqual(Set(s.trainingTargets(for: .mirrorHerb).map(\.id)), [TrainingFixture.activeID, pikachuID, raichuID])
        XCTAssertEqual(s.useMirrorHerb(on: raichuID), .changed)
        XCTAssertEqual(Set(s.trainingTargets(for: .mirrorHerb).map(\.id)), [TrainingFixture.activeID, pikachuID],
                       "an individual that has the herb is no longer listed")
        XCTAssertTrue(ItemKind.mirrorHerb.isTrainingItem)
    }

    func testTheHerbSurvivesARestart() async throws {
        let fixture = try TrainingFixture(self)
        let state = TrainingFixture.state(dex: [TrainingFixture.graduate(pikachuID, speciesID: 25)],
                                          inventory: ["mirrorHerb": 1])
        let s = try await fixture.store(state)
        XCTAssertEqual(s.useMirrorHerb(on: TrainingFixture.activeID), .changed)
        XCTAssertEqual(fixture.reload().state.active?.profile?.mirrorHerb, true)
    }

    func testShopListsTheHerbAtItsPrice() async throws {
        XCTAssertEqual(ItemKind.mirrorHerb.shopPrice, MirrorHerb.price)
        XCTAssertEqual(ItemKind.mirrorHerb.category, .growth)
        let s = try await store(herbs: 0, tokens: MirrorHerb.price)
        XCTAssertTrue(s.purchasableItems.contains(.mirrorHerb))
        XCTAssertTrue(s.buy(.mirrorHerb))
        XCTAssertEqual(s.itemCount(.mirrorHerb), 1)
    }

    // MARK: Saves

    func testAnOldProfileDecodesWithoutTheFlag() throws {
        let old = #"{"instanceID":"a","seed":1,"ivs":{"hp":1,"attack":2,"defense":3,"specialAttack":4,"specialDefense":5,"speed":6},"abilityIsHidden":false,"level":12,"growthTokens":3,"moves":[]}"#
        let profile = try JSONDecoder().decode(PokemonProfile.self, from: Data(old.utf8))
        XCTAssertNil(profile.mirrorHerb)
        XCTAssertEqual(profile.level, 12)
        XCTAssertEqual(profile.ivs.speed, 6)
    }

    func testAFlagOfAnotherTypeKeepsTheRestOfTheProfile() throws {
        let odd = #"{"instanceID":"a","seed":1,"ivs":{"hp":1,"attack":2,"defense":3,"specialAttack":4,"specialDefense":5,"speed":6},"abilityIsHidden":false,"level":12,"growthTokens":3,"moves":[],"mirrorHerb":"yes"}"#
        let profile = try JSONDecoder().decode(PokemonProfile.self, from: Data(odd.utf8))
        XCTAssertNil(profile.mirrorHerb)
        XCTAssertEqual(profile.level, 12)
    }

    func testTheFlagRoundTripsAndIsLeftOutWhenUnset() throws {
        var profile = TrainingFixture.profile("round")
        let plain = String(decoding: try JSONEncoder().encode(profile), as: UTF8.self)
        XCTAssertFalse(plain.contains("mirrorHerb"))
        profile.mirrorHerb = true
        let decoded = try JSONDecoder().decode(PokemonProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(decoded, profile)
    }

    // MARK: Bot request and upload

    func testOnlyAHerbRequestAsksForEggMoves() throws {
        let plain = try XCTUnwrap(PartyUploader.movesRequest(serverURL: "http://bot-host:8790", token: "t",
                                                             pokemonID: 25, level: 42))
        XCTAssertEqual(plain.url?.absoluteString,
                       "http://bot-host:8790/v1/moves?pokemon_id=25&level=42&machine=1&status=1")
        let egg = try XCTUnwrap(PartyUploader.movesRequest(serverURL: "http://bot-host:8790", token: "t",
                                                           pokemonID: 25, level: 42, egg: true))
        XCTAssertEqual(egg.url?.absoluteString,
                       "http://bot-host:8790/v1/moves?pokemon_id=25&level=42&machine=1&status=1&egg=1")
    }

    func testEggMovesHaveTheirOwnGroup() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let moves = try decoder.decode(LearnableMoves.self, from: Data(eggMovesJSON.utf8))
        XCTAssertEqual(moves.levelUpMoves.map(\.id), [84, 209])
        XCTAssertEqual(moves.eggMoves.map(\.id), [344])
        XCTAssertEqual(moves.machineMoves.map(\.id), [85, 89])
        let status = try decoder.decode(LearnableMoves.self, from: Data(statusMovesJSON.utf8))
        XCTAssertEqual(status.eggMoves, [], "status egg moves stay in the status group")
        XCTAssertEqual(status.statusMoves.filter(\.isEgg).map(\.id), [14, 281])
    }

    func testTheUploadCarriesTheHerbAndTheEggMove() async throws {
        let rig = try await TrainingRig(eggMovesJSON: eggMovesJSON)
        defer { rig.close() }
        XCTAssertEqual(rig.store.useMirrorHerb(on: "pikachu"), .changed)
        XCTAssertTrue(rig.battle.add("pikachu"))
        XCTAssertTrue(rig.battle.add("snorlax"))
        rig.battle.chooseMove(344, at: 0, for: "pikachu", pokemonID: 25, current: [84, 209])
        await rig.uploader.tick()

        let body = try XCTUnwrap(rig.posts.all.last)
        let party = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])["party"]
        let members = try XCTUnwrap(party as? [[String: Any]])
        let pikachu = try XCTUnwrap(members.first { $0["pokemon_id"] as? Int == 25 })
        let snorlax = try XCTUnwrap(members.first { $0["pokemon_id"] as? Int == 143 })
        XCTAssertEqual(pikachu["mirror_herb"] as? Bool, true)
        XCTAssertEqual((pikachu["moves"] as? [Int])?.first, 344)
        XCTAssertNil(snorlax["mirror_herb"], "left out without the herb")
    }

    // MARK: Move training

    func testWithoutTheHerbEggMovesHaveNoChooseRowAndTheListStaysTodays() async throws {
        let rig = try await TrainingRig(eggMovesJSON: eggMovesJSON)
        defer { rig.close() }
        let host = try await rig.mount(rig.section("pikachu"))

        // Spark and Thunder Shock. The unowned TMs and the locked Volt Tackle have no choose row.
        _ = try await rig.chooseRows(in: host, count: 2)
        try await OffscreenRender.waitUntil("the display-only egg request", in: host) {
            rig.fetches.all.contains { $0.contains("egg=1") }
        }
        let plain = rig.fetches.all.filter { !$0.contains("egg=1") }
        XCTAssertEqual(plain, ["http://bot-host:8790/v1/moves?pokemon_id=25&level=42&machine=1&status=1"])
    }

    func testUsingTheHerbMakesTheEggMoveChoosable() async throws {
        let rig = try await TrainingRig(eggMovesJSON: eggMovesJSON)
        defer { rig.close() }
        let locked = try await rig.mount(rig.section("pikachu"))
        _ = try await rig.chooseRows(in: locked, count: 2)
        rig.close()

        XCTAssertEqual(rig.store.useMirrorHerb(on: "pikachu"), .changed)
        let host = try await rig.mount(rig.section("pikachu"))
        // Spark, Thunder Shock, then Volt Tackle in the egg group after the TM group.
        let rows = try await rig.chooseRows(in: host, count: 3)
        try await rig.press(try XCTUnwrap(rows.last), in: host, until: { !rig.posts.all.isEmpty })

        XCTAssertEqual(rig.battle.chosenMoves(for: "pikachu", pokemonID: 25), [344, 209])
        XCTAssertEqual(rig.posts.all.count, 1)
    }

    func testATradeLockedPokemonNeverAsksForEggMoves() async throws {
        let rig = try await TrainingRig(eggMovesJSON: eggMovesJSON)
        defer { rig.close() }
        rig.store.lockForTrade("pikachu")
        let host = try await rig.mount(rig.section("pikachu"))
        _ = try await rig.chooseRows(in: host, count: 2)
        XCTAssertFalse(rig.fetches.all.contains { $0.contains("egg=1") }, "no herb can be used, so nothing is shown")
    }
}
