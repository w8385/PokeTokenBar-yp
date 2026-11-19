import XCTest
@testable import PokeTokenBar

private struct PrizeProvider: PokeProviding {
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []),
                rarity: .legendary, names: [baseSpeciesID: ["en": "M\(baseSpeciesID)"]])
    }
}

/// Never rolls a shiny on its own: 1 % 64 and 1 % 48 are not 0.
private struct NeverShinyRNG: RandomNumberGenerator {
    mutating func next() -> UInt64 { 1 }
}

@MainActor
final class HiddenBossPrizeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let activeMon = "{\"baseID\":10,\"pathIDs\":[10],\"stageIndex\":0,\"usedAtStage\":200000000,"
        + "\"rarity\":\"common\",\"totalForms\":3,\"isShiny\":false}"

    private func url() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("hidden-boss-prize-\(UUID().uuidString).json")
    }

    /// A save with a raised Pokémon; `extra` is spliced into the top-level JSON object.
    private func store(file: URL, extra: String = "", rng: some RandomNumberGenerator = SeededRNG(seed: 3)) throws -> CompanionStore {
        let json = "{\"economyVersion\":3,\"installBaselineSet\":true,\"usedSinceInstall\":50000000000,\"spentTokens\":0,\"lastDate\":\"d\","
            + "\"language\":\"en\",\"active\":\(activeMon),\"dex\":[],\"collectedFinals\":[]\(extra)}"
        try Data(json.utf8).write(to: file)
        return CompanionStore(provider: PrizeProvider(), clock: { self.now }, fileURL: file, rng: rng)
    }

    private func hallOfFame(_ regions: String...) -> String {
        let entries = regions.map { "\"\($0)\":{\"gyms\":[1,2,3,4,5,6,7,8],\"hallOfFame\":true}" }
        return ",\"gymBadges\":{\"regions\":{\(entries.joined(separator: ","))}}"
    }

    private func opponent(_ region: String, _ suffix: String) throws -> GymOpponent {
        let catalog = try GymCatalog.decode(GymFixtures.catalogData(regions: [(region, region)], hidden: true))
        return try XCTUnwrap(catalog.region(region)?.opponent("\(region)-\(suffix)"))
    }

    private func clearHidden(_ region: String, _ s: CompanionStore) throws {
        let reward = try XCTUnwrap(GymRewards.reward(for: opponent(region, "hidden"), region: region,
                                                     badges: s.state.gymBadges, ownedTMs: []))
        s.applyGymReward(reward, trainer: "Hidden", region: region)
    }

    func testCandiesAreWorthOneLegendaryEggAtShopPrices() {
        XCTAssertEqual(HiddenBossPrize.candyCount, FreshEgg.price(guaranteeing: .legendary) / RareCandy.price)
        XCTAssertEqual(HiddenBossPrize.candyCount, 16)
    }

    func testEachRegionHasItsFixedEggAndItems() {
        let eggs = Dictionary(uniqueKeysWithValues: HiddenBossPrize.all.map { ($0.region, $0.eggSpeciesID) })
        XCTAssertEqual(eggs, [.kanto: 150, .johto: 251, .hoenn: 384, .sinnoh: 493, .unova: 494, .kalos: 718,
                              .alola: 800, .galar: 890, .paldea: 1024])
        let items = Dictionary(uniqueKeysWithValues: HiddenBossPrize.all.map { ($0.region, $0.itemKeys) })
        XCTAssertEqual(items[.kanto], ["mega-stone:mewtwonite-x", "mega-stone:mewtwonite-y"])
        XCTAssertEqual(items[.sinnoh], ItemKind.plates.map(\.rawValue))
        XCTAssertEqual(items[.sinnoh]?.count, 17)
        XCTAssertEqual(items[.unova], [ItemKind.charcoal.rawValue])
        XCTAssertEqual(items[.kalos], ["mega-stone:zygardite"])
        XCTAssertEqual(items[.galar], [ItemKind.blackSludge.rawValue])
        XCTAssertEqual(items[.paldea], [ItemKind.stellarCrystal.rawValue])
        for region in [PokedexRegion.johto, .hoenn, .alola] { XCTAssertEqual(items[region], [], "\(region)") }
    }

    func testEveryPrizeEggHasANameInEveryLanguage() {
        for prize in HiddenBossPrize.all {
            for language in AppLanguage.allCases {
                XCTAssertFalse(L(language).prizeEggName(prize.eggSpeciesID).contains("#"), "\(prize.region) \(language)")
            }
        }
    }

    func testTheHiddenBossDecodesUnderItsRegionAndAnOldBotHasNone() throws {
        let region = try XCTUnwrap(GymFixtures.catalog(hidden: true).region("kanto"))
        XCTAssertEqual(region.hidden?.id, "kanto-hidden")
        XCTAssertEqual(region.hidden?.finale, 1)
        XCTAssertEqual(region.opponent("kanto-hidden")?.kind, "hidden")
        XCTAssertNil(GymFixtures.catalog().region("kanto")?.hidden)
    }

    func testBadgesSavedBeforeTheHiddenBossDecodeAsNotBeaten() throws {
        let json = Data("{\"regions\":{\"kanto\":{\"gyms\":[1],\"hallOfFame\":true,\"orgBeaten\":true}}}".utf8)
        let badges = try JSONDecoder().decode(GymBadges.self, from: json)
        XCTAssertTrue(badges.region("kanto").hallOfFame)
        XCTAssertFalse(badges.region("kanto").hiddenBeaten)
    }

    func testFirstHiddenBossClearPaysTheTMEggCandiesAndItems() throws {
        let file = url()
        defer { try? FileManager.default.removeItem(at: file) }
        let s = try store(file: file, extra: hallOfFame("kanto"))
        let reward = try XCTUnwrap(GymRewards.reward(for: opponent("kanto", "hidden"), region: "kanto",
                                                     badges: s.state.gymBadges, ownedTMs: []))
        XCTAssertEqual(reward.kind, .hiddenBoss)
        XCTAssertEqual(reward.prize?.region, .kanto)
        let tm = try XCTUnwrap(reward.tmMoveID)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(MachineCatalog.moves.first { $0.id == tm }).power, GymRewards.finaleMinPower)

        s.applyGymReward(reward, trainer: "Hidden", region: "Kanto")

        XCTAssertTrue(s.state.gymBadges.region("kanto").hiddenBeaten)
        XCTAssertEqual(MachineMove.ownedIDs(in: s.state.inventory), [tm])
        XCTAssertEqual(s.prizeEggCount(speciesID: 150), 1)
        XCTAssertEqual(s.itemCount(.rareCandy), 16)
        XCTAssertEqual(s.state.inventory["mega-stone:mewtwonite-x"], 1)
        XCTAssertEqual(s.state.inventory["mega-stone:mewtwonite-y"], 1)
        let text = try XCTUnwrap(s.latestEvent?.text)
        XCTAssertTrue(text.hasSuffix("Prize: Shiny Mewtwo Egg, Rare Candy ×16, Mewtwonite X, Mewtwonite Y"), text)
    }

    func testAReClearPaysNothingAgain() throws {
        let file = url()
        defer { try? FileManager.default.removeItem(at: file) }
        let s = try store(file: file, extra: hallOfFame("kanto"))
        try clearHidden("kanto", s)
        XCTAssertNil(GymRewards.reward(for: try opponent("kanto", "hidden"), region: "kanto",
                                       badges: s.state.gymBadges, ownedTMs: []))
    }

    func testTheChampionPaysOnlyTheHallOfFameAndItsTM() throws {
        let file = url()
        defer { try? FileManager.default.removeItem(at: file) }
        let s = try store(file: file)
        let reward = try XCTUnwrap(GymRewards.reward(for: opponent("kanto", "champion"), region: "kanto",
                                                     badges: s.state.gymBadges, ownedTMs: []))
        XCTAssertNil(reward.prize)

        s.applyGymReward(reward, trainer: "Champion", region: "Kanto")

        XCTAssertTrue(s.state.gymBadges.region("kanto").hallOfFame)
        XCTAssertFalse(s.state.gymBadges.region("kanto").hiddenBeaten)
        XCTAssertEqual(s.prizeEggCount(speciesID: 150), 0)
        XCTAssertEqual(s.itemCount(.rareCandy), 0)
        XCTAssertFalse(try XCTUnwrap(s.latestEvent?.text).contains("Prize:"))
    }

    func testAnEarlierHallOfFamePaysNothingOnLaunch() throws {
        let file = url()
        defer { try? FileManager.default.removeItem(at: file) }
        let s = try store(file: file, extra: hallOfFame("kanto", "sinnoh"))
        XCTAssertTrue(s.ownedPrizeEggs.isEmpty)
        XCTAssertEqual(s.itemCount(.rareCandy), 0)
        XCTAssertFalse((s.latestEvent?.text ?? "").contains("Prize:"))
    }

    func testAnOwnedStellarCrystalIsNotPaidTwice() throws {
        let file = url()
        defer { try? FileManager.default.removeItem(at: file) }
        let s = try store(file: file, extra: hallOfFame("paldea") + ",\"inventory\":{\"stellarCrystal\":1}")
        try clearHidden("paldea", s)
        XCTAssertEqual(s.itemCount(.stellarCrystal), 1)
        XCTAssertEqual(s.prizeEggCount(speciesID: 1024), 1)
        XCTAssertFalse(try XCTUnwrap(s.latestEvent?.text).contains(L(.en).itemName(.stellarCrystal)))
    }

    func testThePrizeEggHatchesAsItsSpeciesAndShiny() async throws {
        let file = url()
        defer { try? FileManager.default.removeItem(at: file) }
        let s = try store(file: file, extra: ",\"inventory\":{\"shiny-egg:150\":1}")
        XCTAssertEqual(s.bagCategories, [.egg])
        XCTAssertTrue(s.hatchPrizeEgg(speciesID: 150))
        XCTAssertEqual(s.prizeEggCount(speciesID: 150), 0)
        XCTAssertNil(s.state.active)
        XCTAssertEqual(s.state.pendingHatchID, 150)
        XCTAssertTrue(s.state.shinyEgg)

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        json["eggUsage"] = PokemonBalance.eggHatchThreshold
        try JSONSerialization.data(withJSONObject: json).write(to: file)
        let hatching = CompanionStore(provider: PrizeProvider(), clock: { self.now }, fileURL: file, rng: NeverShinyRNG())
        await hatching.hatchIfNeeded()
        XCTAssertEqual(hatching.state.active?.baseID, 150)
        XCTAssertEqual(hatching.state.active?.isShiny, true)
        XCTAssertFalse(hatching.state.shinyEgg)
    }

    func testThePrizeArceusEggIsItsNormalForm() throws {
        let file = url()
        defer { try? FileManager.default.removeItem(at: file) }
        let s = try store(file: file, extra: ",\"inventory\":{\"shiny-egg:493\":1}")
        XCTAssertTrue(s.hatchPrizeEgg(speciesID: 493))
        XCTAssertEqual(s.state.pendingForm, PokemonForm.lineForms(baseID: 493).first)
    }

    func testTheSameEggWithoutThePrizeFlagHatchesPlain() async throws {
        let file = url()
        defer { try? FileManager.default.removeItem(at: file) }
        let json = "{\"economyVersion\":3,\"installBaselineSet\":true,\"usedSinceInstall\":1,\"spentTokens\":0,\"lastDate\":\"d\","
            + "\"active\":null,\"dex\":[],\"collectedFinals\":[],\"eggUsage\":\(PokemonBalance.eggHatchThreshold),"
            + "\"pendingHatchID\":150,\"scoutedEgg\":true}"
        try Data(json.utf8).write(to: file)
        let s = CompanionStore(provider: PrizeProvider(), clock: { self.now }, fileURL: file, rng: NeverShinyRNG())
        await s.hatchIfNeeded()
        XCTAssertEqual(s.state.active?.baseID, 150)
        XCTAssertEqual(s.state.active?.isShiny, false)
    }

    func testThePrizeEggNeedsAPokemonToSendOff() throws {
        let file = url()
        defer { try? FileManager.default.removeItem(at: file) }
        let json = "{\"economyVersion\":3,\"installBaselineSet\":true,\"usedSinceInstall\":1,\"spentTokens\":0,\"lastDate\":\"d\","
            + "\"active\":null,\"dex\":[],\"collectedFinals\":[],\"inventory\":{\"shiny-egg:150\":1}}"
        try Data(json.utf8).write(to: file)
        let s = CompanionStore(provider: PrizeProvider(), clock: { self.now }, fileURL: file, rng: SeededRNG(seed: 3))
        XCTAssertFalse(s.canHatchPrizeEgg)
        XCTAssertFalse(s.hatchPrizeEgg(speciesID: 150))
        XCTAssertEqual(s.prizeEggCount(speciesID: 150), 1)
    }

    func testAShopEggIsNeverForcedShiny() throws {
        let file = url()
        defer { try? FileManager.default.removeItem(at: file) }
        let s = try store(file: file, extra: ",\"shinyEgg\":true")
        XCTAssertTrue(s.buyEgg(nil))
        XCTAssertFalse(s.state.shinyEgg)
    }
}
