import XCTest
@testable import PokeTokenBar

@MainActor
final class ClickGrowthTests: XCTestCase {
    private final class Clock { var now = Date(timeIntervalSince1970: 1_700_000_000) }

    private let line = EvoLine(
        baseID: 1,
        tree: EvoNode(speciesID: 1, children: [EvoNode(speciesID: 2, children: [EvoNode(speciesID: 3, children: [])])]),
        rarity: .common,
        names: [1: ["en": "P1"], 2: ["en": "P2"], 3: ["en": "P3"]])

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("click-\(UUID().uuidString).json")
    }

    private func freshEgg(clock: Clock, url: URL? = nil) -> CompanionStore {
        let url = url ?? tempURL()
        let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":0,\"spentTokens\":0,"
            + "\"lastDate\":\"d\",\"active\":null,\"dex\":[],\"collectedFinals\":[],\"eggUsage\":0,\"pendingHatchID\":1}"
        try? json.data(using: .utf8)!.write(to: url)
        return CompanionStore(provider: StubProvider(value: line), clock: { clock.now }, fileURL: url,
                              rng: SeededRNG(seed: 7))
    }

    /// Clicks spaced past the rate limit; returns how many counted.
    @discardableResult
    private func click(_ store: CompanionStore, _ clock: Clock, times: Int) -> Int {
        var counted = 0
        for _ in 0..<times {
            clock.now += ClickGrowth.minInterval + 0.01
            if case .counted = store.growByClick() { counted += 1 }
        }
        return counted
    }

    func testClickGrowsTheEggWithoutTouchingUsageOrWallet() {
        let clock = Clock()
        let store = freshEgg(clock: clock)
        XCTAssertEqual(store.growByClick(), .counted(ClickGrowth.tokensPerClick))
        XCTAssertEqual(store.state.eggUsage, ClickGrowth.tokensPerClick)
        XCTAssertEqual(store.state.clickGrowth, ClickGrowth.tokensPerClick)
        XCTAssertEqual(store.state.usedSinceInstall, 0)
    }

    func testDailyCapStopsCountingUntilTheNextLocalDay() {
        let clock = Clock()
        let store = freshEgg(clock: clock)
        XCTAssertEqual(click(store, clock, times: ClickGrowth.dailyCap + 50), ClickGrowth.dailyCap)
        XCTAssertTrue(store.clickCapReachedToday)
        XCTAssertEqual(store.state.clickGrowth, ClickGrowth.dailyCap * ClickGrowth.tokensPerClick)
        clock.now += 1
        XCTAssertEqual(store.growByClick(), .capped)

        clock.now += 86_400
        XCTAssertFalse(store.clickCapReachedToday)
        XCTAssertEqual(store.growByClick(), .counted(ClickGrowth.tokensPerClick))
        XCTAssertEqual(store.state.clicksToday, 1)
    }

    func testClicksFasterThanTheIntervalDoNotCount() {
        let clock = Clock()
        let store = freshEgg(clock: clock)
        XCTAssertEqual(store.growByClick(), .counted(ClickGrowth.tokensPerClick))
        clock.now += ClickGrowth.minInterval / 2
        XCTAssertEqual(store.growByClick(), .tooSoon)
        clock.now += ClickGrowth.minInterval / 2 + 0.01
        XCTAssertEqual(store.growByClick(), .counted(ClickGrowth.tokensPerClick))
        XCTAssertEqual(store.state.clicksToday, 2)
    }

    func testOldSaveLoadsWithNoClickGrowthAndNewFieldsPersist() throws {
        let clock = Clock()
        let url = tempURL()
        let store = freshEgg(clock: clock, url: url)
        XCTAssertEqual(store.state.clickGrowth, 0)
        XCTAssertEqual(store.state.clicksToday, 0)
        XCTAssertEqual(store.state.clickDay, "")

        store.growByClick()
        let reloaded = CompanionStore(provider: StubProvider(value: line), clock: { clock.now }, fileURL: url,
                                      rng: SeededRNG(seed: 7))
        XCTAssertEqual(reloaded.state.clickGrowth, ClickGrowth.tokensPerClick)
        XCTAssertEqual(reloaded.state.clicksToday, 1)
        XCTAssertEqual(reloaded.state.clickDay, store.state.clickDay)
    }

    func testImportKeepsThisDevicesClickCountForToday() {
        var current = CompanionState()
        current.clickDay = "2026-11-12"
        current.clicksToday = ClickGrowth.dailyCap
        var imported = CompanionState()
        imported.clickGrowth = 5_000_000
        let rebased = SaveTransfer.rebasedForThisDevice(imported, current: current, todayTokensByProvider: [:],
                                                        todayDate: "2026-11-12", hasUsageData: false)
        XCTAssertEqual(rebased.clicksToday, ClickGrowth.dailyCap)
        XCTAssertEqual(rebased.clickDay, "2026-11-12")
        XCTAssertEqual(rebased.clickGrowth, 5_000_000)
    }

    func testSanitizeClampsClickFields() {
        var state = CompanionState()
        state.clickGrowth = -5
        state.clicksToday = 10_000
        let clean = SaveTransfer.sanitized(state)
        XCTAssertEqual(clean.clickGrowth, 0)
        XCTAssertEqual(clean.clicksToday, ClickGrowth.dailyCap)
    }

    /// The tuning target: clicking alone at the cap takes a common egg to graduation in `targetDays`.
    func testCappedClickingGraduatesACommonLineInTargetDays() async {
        let clock = Clock()
        let store = freshEgg(clock: clock)
        var days = 0
        while store.state.dex.isEmpty, days < 60 {
            days += 1
            clock.now += 86_400
            for _ in 0..<ClickGrowth.dailyCap {
                clock.now += ClickGrowth.minInterval + 0.01
                store.growByClick()
                if store.state.active == nil, store.state.eggUsage >= store.eggHatchThreshold {
                    await store.hatchIfNeeded()
                }
            }
        }
        XCTAssertEqual(days, ClickGrowth.targetDays)
        XCTAssertEqual(store.state.dex.first?.finalID, 3)
    }

    func testAverageTokenUserGrowsClearlyFasterThanCappedClicking() {
        let commonRun = PokemonBalance.eggHatchThreshold + PokemonBalance.graduationTotal(.common)
        let clickPerDay = ClickGrowth.dailyCap * ClickGrowth.tokensPerClick
        let averageTokensPerDay = 253_000_000
        XCTAssertGreaterThanOrEqual(averageTokensPerDay, clickPerDay * 4)
        XCTAssertEqual(Int((Double(commonRun) / Double(clickPerDay)).rounded(.up)), ClickGrowth.targetDays)
    }

    func testHeartParticleKeepsItsGlyph() {
        let burst = PrayerBurst()
        burst.spawn(glyph: PrayerBurst.heart, xFraction: 0.5)
        burst.spawn(xFraction: 0.5)
        XCTAssertEqual(burst.particles.map(\.glyph), [PrayerBurst.heart, PrayerBurst.prayer])
    }
}
