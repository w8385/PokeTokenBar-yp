import XCTest
@testable import PokeTokenBar

private struct RewardProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []),
                rarity: .common, names: [baseSpeciesID: ["en": "Mon", "ko": "몬"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: 151, captureRate: 255)] }
}

@MainActor
final class DexRegionRewardTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ptb-region-reward-\(UUID().uuidString).json")
    }

    private func write(owned range: ClosedRange<Int>, seeded: Bool = true, inventory: [String: Int] = [:],
                       to url: URL) throws {
        var state = CompanionState()
        state.language = .en
        state.dexCompletionsSeeded = seeded
        state.inventory = inventory
        state.dex = [DexEntry(baseID: range.lowerBound, finalID: range.upperBound,
                              chainOrder: Array(range), rarity: .common, caughtAt: Date())]
        try JSONEncoder().encode(state).write(to: url)
    }

    private func store(at url: URL) -> CompanionStore {
        CompanionStore(provider: RewardProvider(), fileURL: url)
    }

    func testRewardIsWorthOneRareEggInRareCandies() {
        XCTAssertEqual(DexRegionReward.candyCount, 8)
        XCTAssertEqual(DexRegionReward.candyCount * RareCandy.price, FreshEgg.price(guaranteeing: .rare))
    }

    func testCompletingARegionGrantsOnceAndASecondCheckGrantsNothing() async throws {
        let url = tempURL()
        try write(owned: 1...150, to: url)
        let s = store(at: url)
        XCTAssertEqual(s.itemCount(.rareCandy), 0)
        XCTAssertFalse(s.isDexRegionRewarded(.kanto))

        await s.hatch(baseID: 151)   // Mew completes Kanto

        XCTAssertTrue(s.isDexRegionRewarded(.kanto))
        XCTAssertEqual(s.itemCount(.rareCandy), DexRegionReward.candyCount)
        XCTAssertEqual(s.itemCount(.shinyCharm), 1)
        XCTAssertTrue(s.latestEvent?.text.contains("×\(DexRegionReward.candyCount)") ?? false)

        s.checkDexCompletions()
        s.setLanguage(.ko)
        XCTAssertEqual(s.itemCount(.rareCandy), DexRegionReward.candyCount)
        XCTAssertEqual(s.itemCount(.shinyCharm), 1)

        let reloaded = store(at: url)
        XCTAssertEqual(reloaded.itemCount(.rareCandy), DexRegionReward.candyCount)
        XCTAssertTrue(reloaded.isDexRegionRewarded(.kanto))
    }

    func testRegionCompleteBeforeTheUpdateIsRewardedOnceOnTheNextLaunch() throws {
        for seeded in [true, false] {
            let url = tempURL()
            try write(owned: PokedexRegion.kanto.dexRange, seeded: seeded, to: url)
            let first = store(at: url)
            XCTAssertEqual(first.itemCount(.rareCandy), DexRegionReward.candyCount, "seeded=\(seeded)")
            XCTAssertEqual(first.itemCount(.shinyCharm), 1)
            XCTAssertTrue(first.isDexRegionRewarded(.kanto))

            let second = store(at: url)
            XCTAssertEqual(second.itemCount(.rareCandy), DexRegionReward.candyCount, "no second payout, seeded=\(seeded)")
        }
    }

    func testCharmIsGrantedOnlyWithTheFirstRewardAndNeverDuplicated() throws {
        let owned = tempURL()
        try write(owned: 1...251, inventory: [ItemKind.shinyCharm.rawValue: 1], to: owned)
        let withCharm = store(at: owned)
        XCTAssertEqual(withCharm.itemCount(.shinyCharm), 1)
        XCTAssertEqual(withCharm.itemCount(.rareCandy), DexRegionReward.candyCount * 2)

        let fresh = tempURL()
        try write(owned: 1...251, to: fresh)
        let both = store(at: fresh)
        XCTAssertEqual(both.itemCount(.shinyCharm), 1, "two regions at once still bring one charm")
        XCTAssertEqual(both.itemCount(.rareCandy), DexRegionReward.candyCount * 2)
        XCTAssertTrue(both.isDexRegionRewarded(.kanto) && both.isDexRegionRewarded(.johto))
    }

    func testAnIncompleteRegionGrantsNothing() throws {
        let url = tempURL()
        try write(owned: 1...150, to: url)
        let s = store(at: url)
        XCTAssertEqual(s.itemCount(.rareCandy), 0)
        XCTAssertTrue(s.state.rewardedDexRegions.isEmpty)
    }

    func testOldSavesWithoutTheKeyLoadAndCorruptValuesFallBackToEmpty() throws {
        let missing = try JSONDecoder().decode(CompanionState.self, from: Data(#"{"usedSinceInstall": 5}"#.utf8))
        XCTAssertTrue(missing.rewardedDexRegions.isEmpty)
        XCTAssertEqual(missing.usedSinceInstall, 5)
        let corrupt = try JSONDecoder().decode(CompanionState.self,
                                               from: Data(#"{"usedSinceInstall": 5, "rewardedDexRegions": 7}"#.utf8))
        XCTAssertTrue(corrupt.rewardedDexRegions.isEmpty)
        XCTAssertEqual(corrupt.usedSinceInstall, 5)
        var state = CompanionState()
        state.rewardedDexRegions = ["kanto"]
        let round = try JSONDecoder().decode(CompanionState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(round.rewardedDexRegions, ["kanto"])
    }

    func testRewardNotificationNamesTheItemsInEveryLanguage() {
        for language in AppLanguage.allCases {
            let text = L(language).notifDexRegionRewardBody("RRR", items: "III")
            XCTAssertTrue(text.contains("RRR") && text.contains("III"), "\(language)")
            XCTAssertFalse(L(language).dexRegionRewardedHelp.isEmpty)
        }
    }
}
