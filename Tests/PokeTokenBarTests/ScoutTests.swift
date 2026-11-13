import XCTest
@testable import PokeTokenBar

/// Every id is a two-stage common base so a hatched line has two forms (the Ditto disguise needs that).
/// Capture rates vary with the id so the weights are not flat.
private struct ScoutProvider: PokeProviding {
    var ids: [Int] = Array(1...1025)
    var offline = false

    static func captureRate(_ id: Int) -> Int { id % 7 == 0 ? 3 : (id % 3 == 0 ? 45 : 255) }

    func baseSpeciesIndex() async throws -> [BaseSpecies] {
        if offline { throw URLError(.notConnectedToInternet) }
        return ids.map { BaseSpecies(id: $0, captureRate: Self.captureRate($0)) }
    }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID,
                tree: EvoNode(speciesID: baseSpeciesID, children: [EvoNode(speciesID: baseSpeciesID + 1, children: [])]),
                rarity: .common, names: [baseSpeciesID: ["en": "M\(baseSpeciesID)"]])
    }
}

private struct ZeroRNG: RandomNumberGenerator {
    mutating func next() -> UInt64 { 0 }
}

@MainActor
final class ScoutTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func url() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("scout-\(UUID().uuidString).json")
    }

    private let activeMon = "{\"baseID\":10,\"pathIDs\":[10],\"stageIndex\":0,\"usedAtStage\":200000000,"
        + "\"rarity\":\"common\",\"totalForms\":3,\"isShiny\":false}"

    /// A save holding `tickets` for the pool, a raised Pokémon (or an egg) and a full wallet.
    private func store(tickets: [String: Int] = ["scout.kanto": 1], active: Bool = true, used: Int = 50_000_000_000,
                       provider: any PokeProviding = ScoutProvider(), seed: UInt64 = 5,
                       file: URL? = nil) -> CompanionStore {
        let f = file ?? url()
        let inv = tickets.map { "\"\($0.key)\":\($0.value)" }.joined(separator: ",")
        let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":\(used),\"spentTokens\":0,\"lastDate\":\"d\","
            + "\"active\":\(active ? activeMon : "null"),\"dex\":[],\"collectedFinals\":[],"
            + "\"inventory\":{\(inv)}}"
        try? json.data(using: .utf8)!.write(to: f)
        return CompanionStore(provider: provider, clock: { self.now }, fileURL: f, rng: SeededRNG(seed: seed))
    }

    // MARK: 후보 뽑기

    func testKantoTicketDrawsTenDistinctSpeciesFrom1To151() async throws {
        for seed in UInt64(1)...30 {
            let s = store(seed: seed)
            let drawn = try XCTUnwrapAsync(await s.drawScout(.region(.kanto)))
            XCTAssertEqual(drawn.count, 10)
            XCTAssertEqual(Set(drawn).count, 10, "no duplicates inside one draw")
            XCTAssertTrue(drawn.allSatisfy { (1...151).contains($0) }, "seed \(seed): \(drawn)")
        }
    }

    func testEveryPoolStaysInsideItsRange() async throws {
        for pool in ScoutPool.all {
            let s = store(tickets: [pool.inventoryKey: 1])
            let drawn = try XCTUnwrapAsync(await s.drawScout(pool))
            XCTAssertEqual(drawn.count, 10)
            XCTAssertTrue(drawn.allSatisfy { pool.dexRange.contains($0) }, "\(pool.key): \(drawn)")
        }
    }

    func testRegionWithFewerThanTenShowsAllOfThem() async throws {
        let s = store(provider: ScoutProvider(ids: [1, 4, 7, 25, 200, 900]))
        let drawn = try XCTUnwrapAsync(await s.drawScout(.region(.kanto)))
        XCTAssertEqual(drawn, [1, 4, 7, 25])
    }

    func testDrawIgnoresSpeciesTheEggPoolDoesNotHave() async throws {
        // The index is the egg pool: bases only, no Ditto. A species it lacks can never be offered.
        let ids = Array(1...151).filter { $0 != PokemonOdds.dittoSpeciesID && $0 != 25 }
        for seed in UInt64(1)...20 {
            let t = store(provider: ScoutProvider(ids: ids), seed: seed)
            let drawn = try XCTUnwrapAsync(await t.drawScout(.region(.kanto)))
            XCTAssertFalse(drawn.contains(25))
            XCTAssertFalse(drawn.contains(PokemonOdds.dittoSpeciesID))
        }
    }

    func testOfflineIndexKeepsTheTicket() async {
        let s = store(provider: ScoutProvider(offline: true))
        let drawn = await s.drawScout(.region(.kanto))
        XCTAssertNil(drawn)
        XCTAssertEqual(s.scoutTicketCount(.region(.kanto)), 1)
        XCTAssertNil(s.scoutDraw(for: .region(.kanto)))
    }

    func testNoTicketNoDraw() async {
        let s = store(tickets: [:])
        let drawn = await s.drawScout(.region(.kanto))
        XCTAssertNil(drawn)
    }

    // MARK: 알과 같은 확률

    /// The scout and the egg share `SpeciesRoll.pick`; the first pick follows the capture-rate weights.
    func testFirstPickFollowsCaptureRateWeights() {
        let candidates = [BaseSpecies(id: 1, captureRate: 255), BaseSpecies(id: 2, captureRate: 100),
                          BaseSpecies(id: 3, captureRate: 30)]
        var rng: any RandomNumberGenerator = SeededRNG(seed: 42)
        var counts: [Int: Int] = [:]
        let rolls = 40_000
        for _ in 0..<rolls {
            let id = SpeciesRoll.pick(from: candidates, isCollected: { _ in false }, rng: &rng)!.id
            counts[id, default: 0] += 1
        }
        let total = 385.0
        for c in candidates {
            let expected = Double(c.captureRate) / total
            XCTAssertEqual(Double(counts[c.id] ?? 0) / Double(rolls), expected, accuracy: 0.01, "id \(c.id)")
        }
    }

    func testCollectedLinesWeighHalf() {
        let candidates = [BaseSpecies(id: 1, captureRate: 100), BaseSpecies(id: 2, captureRate: 100)]
        var rng: any RandomNumberGenerator = SeededRNG(seed: 9)
        var first = 0
        let rolls = 30_000
        for _ in 0..<rolls where SpeciesRoll.pick(from: candidates, isCollected: { $0 == 1 }, rng: &rng)!.id == 1 {
            first += 1
        }
        XCTAssertEqual(Double(first) / Double(rolls), 1.0 / 3.0, accuracy: 0.01)
    }

    /// With the same generator state an egg hatches the species `SpeciesRoll.pick` names, so the scout
    /// cannot drift from the egg odds without this failing.
    func testEggHatchUsesTheSharedRoll() async throws {
        let provider = ScoutProvider(ids: Array(1...60))
        let index = try await provider.baseSpeciesIndex()
        for seed in UInt64(1)...12 {
            let f = url()
            let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":1,\"spentTokens\":0,\"lastDate\":\"d\","
                + "\"active\":null,\"dex\":[],\"collectedFinals\":[],\"eggUsage\":\(PokemonBalance.eggHatchThreshold)}"
            try json.data(using: .utf8)!.write(to: f)
            let egg = CompanionStore(provider: provider, clock: { self.now }, fileURL: f, rng: SeededRNG(seed: seed))
            await egg.hatchIfNeeded()
            var rng: any RandomNumberGenerator = SeededRNG(seed: seed)
            let expected = SpeciesRoll.pick(from: index, isCollected: { _ in false }, rng: &rng)?.id
            XCTAssertEqual(egg.state.active?.baseID, expected, "seed \(seed)")
        }
    }

    // MARK: 닫아도 같은 후보

    func testReopeningShowsTheSameDraw() async throws {
        let s = store()
        let first = try XCTUnwrapAsync(await s.drawScout(.region(.kanto)))
        let again = await s.drawScout(.region(.kanto))
        XCTAssertEqual(again, first)
    }

    func testDrawSurvivesRestart() async throws {
        let f = url()
        let s1 = store(tickets: ["scout.johto": 1], seed: 3, file: f)
        let first = try XCTUnwrapAsync(await s1.drawScout(.region(.johto)))
        let s2 = CompanionStore(provider: ScoutProvider(offline: true), clock: { self.now },
                                fileURL: f, rng: SeededRNG(seed: 99))
        XCTAssertEqual(s2.scoutDraw(for: .region(.johto)), first)
        XCTAssertEqual(s2.scoutTicketCount(.region(.johto)), 1)
    }

    func testPendingDrawRoundTripsThroughEncodeDecode() throws {
        var st = CompanionState()
        st.scoutDraws = ["kanto": [1, 4, 7], "national": [25, 150]]
        st.scoutedEgg = true
        let round = try JSONDecoder().decode(CompanionState.self, from: JSONEncoder().encode(st))
        XCTAssertEqual(round.scoutDraws, st.scoutDraws)
        XCTAssertTrue(round.scoutedEgg)
    }

    func testOldSaveWithoutScoutFieldsLoads() throws {
        let json = #"{"installBaselineSet":true,"usedSinceInstall":900,"lastDate":"d","dex":[],"inventory":{"rareCandy":2}}"#
        let s = try JSONDecoder().decode(CompanionState.self, from: Data(json.utf8))
        XCTAssertEqual(s.scoutDraws, [:])
        XCTAssertFalse(s.scoutedEgg)
        XCTAssertEqual(s.inventory["rareCandy"], 2)
    }

    func testImportedSaveDropsForeignOrOversizedDraws() {
        var st = CompanionState()
        st.scoutDraws = ["kanto": [1, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 300], "nowhere": [1], "johto": [5]]
        let clean = SaveTransfer.sanitized(st).scoutDraws
        XCTAssertEqual(clean["kanto"], [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
        XCTAssertNil(clean["nowhere"])
        XCTAssertNil(clean["johto"], "5 is not a Johto species")
    }

    // MARK: 구매

    func testScoutIsPricedAboveEveryGuaranteedEgg() {
        for tier in FreshEgg.shopTiers {
            XCTAssertGreaterThan(ScoutTicket.price, FreshEgg.price(guaranteeing: tier))
        }
    }

    func testBuyingChargesTheWalletAndFillsTheBag() {
        let s = store(tickets: [:], used: ScoutTicket.price * 2)
        XCTAssertTrue(s.buyScoutTicket(.region(.hoenn)))
        XCTAssertEqual(s.scoutTicketCount(.region(.hoenn)), 1)
        XCTAssertEqual(s.availableTokens, ScoutTicket.price)
        XCTAssertEqual(s.ownedScoutTickets.map(\.pool), [.region(.hoenn)])
        XCTAssertEqual(s.ownedItems.count, 0, "tickets are not ItemKind items")
    }

    func testCannotBuyWithoutEnoughTokens() {
        let s = store(tickets: [:], used: ScoutTicket.price - 1)
        XCTAssertFalse(s.buyScoutTicket(.national))
        XCTAssertEqual(s.scoutTicketCount(.national), 0)
        XCTAssertEqual(s.state.spentTokens, 0)
    }

    // MARK: 고르기

    func testPickingGivesAnEggOfThatSpeciesThatHatchesNormally() async throws {
        let file = url()
        let s = store(tickets: ["scout.kanto": 2], seed: 11, file: file)
        let drawn = try XCTUnwrapAsync(await s.drawScout(.region(.kanto)))
        let target = drawn[3]
        XCTAssertTrue(s.pickScout(.region(.kanto), speciesID: target))
        XCTAssertNil(s.state.active)
        XCTAssertEqual(s.state.pendingHatchID, target)
        XCTAssertEqual(s.state.eggUsage, 0)
        XCTAssertNil(s.state.eggTier)
        XCTAssertEqual(s.scoutTicketCount(.region(.kanto)), 1)
        XCTAssertNil(s.scoutDraw(for: .region(.kanto)), "a used draw is gone; the next ticket draws fresh")
        XCTAssertEqual(s.state.dex.count, 1, "the released Pokémon stays in the dex")

        // Incubate through the saved file, as a restart would, then hatch.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        json["eggUsage"] = PokemonBalance.eggHatchThreshold
        try JSONSerialization.data(withJSONObject: json).write(to: file)
        let hatching = CompanionStore(provider: ScoutProvider(), clock: { self.now }, fileURL: file, rng: SeededRNG(seed: 2))
        await hatching.hatchIfNeeded()
        XCTAssertEqual(hatching.state.active?.baseID, target)
        XCTAssertFalse(hatching.state.scoutedEgg)
    }

    func testPickNeedsAPokemonToSendOff() async throws {
        let s = store(active: false)
        let drawn = try XCTUnwrapAsync(await s.drawScout(.region(.kanto)))
        XCTAssertFalse(s.canPickScout)
        XCTAssertFalse(s.pickScout(.region(.kanto), speciesID: drawn[0]))
        XCTAssertEqual(s.scoutTicketCount(.region(.kanto)), 1)
        XCTAssertNotNil(s.scoutDraw(for: .region(.kanto)))
    }

    func testPickMustComeFromTheDraw() async throws {
        let s = store()
        let drawn = try XCTUnwrapAsync(await s.drawScout(.region(.kanto)))
        let outsider = (1...151).first { !drawn.contains($0) }!
        XCTAssertFalse(s.pickScout(.region(.kanto), speciesID: outsider))
        XCTAssertNotNil(s.state.active)
        XCTAssertEqual(s.scoutTicketCount(.region(.kanto)), 1)
    }

    func testEachRegionKeepsItsOwnPendingDraw() async throws {
        let s = store(tickets: ["scout.kanto": 1, "scout.johto": 1])
        let kanto = try XCTUnwrapAsync(await s.drawScout(.region(.kanto)))
        let johto = try XCTUnwrapAsync(await s.drawScout(.region(.johto)))
        XCTAssertTrue(kanto.allSatisfy { (1...151).contains($0) })
        XCTAssertTrue(johto.allSatisfy { (152...251).contains($0) })
        XCTAssertEqual(s.scoutDraw(for: .region(.kanto)), kanto)
    }

    // MARK: 메타몽 위장은 산 종을 가리지 않는다

    func testScoutedEggNeverHatchesAsDisguisedDitto() async throws {
        // ZeroRNG makes the 1/128 disguise roll hit every time, so only the scout flag can stop it.
        let plain = url()
        try "{\"installBaselineSet\":true,\"usedSinceInstall\":1,\"spentTokens\":0,\"lastDate\":\"d\",\"active\":null,"
            .appending("\"dex\":[],\"collectedFinals\":[],\"eggUsage\":\(PokemonBalance.eggHatchThreshold),\"pendingHatchID\":5}")
            .data(using: .utf8)!.write(to: plain)
        let control = CompanionStore(provider: ScoutProvider(), clock: { self.now }, fileURL: plain,
                                     rng: ZeroRNG(), dittoDisguiseRollingEnabled: true)
        await control.hatchIfNeeded()
        XCTAssertNotNil(control.state.active?.dittoDisguise, "control: the disguise roll is live")

        let scouted = url()
        try "{\"installBaselineSet\":true,\"usedSinceInstall\":1,\"spentTokens\":0,\"lastDate\":\"d\",\"active\":null,"
            .appending("\"dex\":[],\"collectedFinals\":[],\"eggUsage\":\(PokemonBalance.eggHatchThreshold),\"pendingHatchID\":5,\"scoutedEgg\":true}")
            .data(using: .utf8)!.write(to: scouted)
        let s = CompanionStore(provider: ScoutProvider(), clock: { self.now }, fileURL: scouted,
                               rng: ZeroRNG(), dittoDisguiseRollingEnabled: true)
        await s.hatchIfNeeded()
        XCTAssertEqual(s.state.active?.baseID, 5)
        XCTAssertNil(s.state.active?.dittoDisguise)
    }

    func testScoutCategoryIsAlwaysInTheShopAndInTheBagOnlyWithTickets() {
        let none = store(tickets: [:])
        XCTAssertTrue(none.shopCategories.contains(.scout))
        XCTAssertFalse(none.bagCategories.contains(.scout))
        let some = store(tickets: ["scout.kanto": 1])
        XCTAssertEqual(some.bagCategories, [.scout])
    }

    // MARK: 기존 알 구매는 그대로

    func testRegularEggPurchaseIsNotMarkedAsScouted() {
        let s = store(tickets: [:])
        XCTAssertTrue(s.buyEgg(nil))
        XCTAssertFalse(s.state.scoutedEgg)
        XCTAssertNil(s.state.pendingHatchID)
    }
}

private func XCTUnwrapAsync<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) throws -> T {
    try XCTUnwrap(value, file: file, line: line)
}
