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

    func testClicksKeepCountingPastTheOldDailyLimit() {
        let clock = Clock()
        let store = freshEgg(clock: clock)
        XCTAssertEqual(click(store, clock, times: 250), 250)
        XCTAssertEqual(store.state.clickGrowth, 250 * ClickGrowth.tokensPerClick)
    }

    func testClicksFasterThanTheIntervalDoNotCount() {
        let clock = Clock()
        let store = freshEgg(clock: clock)
        XCTAssertEqual(store.growByClick(), .counted(ClickGrowth.tokensPerClick))
        clock.now += ClickGrowth.minInterval / 2
        XCTAssertEqual(store.growByClick(), .tooSoon)
        clock.now += ClickGrowth.minInterval / 2 + 0.01
        XCTAssertEqual(store.growByClick(), .counted(ClickGrowth.tokensPerClick))
        XCTAssertEqual(store.state.clickGrowth, 2 * ClickGrowth.tokensPerClick)
    }

    func testSaveWithTheOldDailyCountStillLoadsAndKeepsCounting() throws {
        let clock = Clock()
        let url = tempURL()
        let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":0,\"spentTokens\":0,"
            + "\"lastDate\":\"d\",\"active\":null,\"dex\":[],\"collectedFinals\":[],\"eggUsage\":0,\"pendingHatchID\":1,"
            + "\"clickGrowth\":540000,\"clickDay\":\"2026-11-12\",\"clicksToday\":200}"
        try XCTUnwrap(json.data(using: .utf8)).write(to: url)
        let store = CompanionStore(provider: StubProvider(value: line), clock: { clock.now }, fileURL: url,
                                   rng: SeededRNG(seed: 7))
        XCTAssertEqual(store.state.clickGrowth, 540_000)
        XCTAssertEqual(store.growByClick(), .counted(ClickGrowth.tokensPerClick))

        let reloaded = CompanionStore(provider: StubProvider(value: line), clock: { clock.now }, fileURL: url,
                                      rng: SeededRNG(seed: 7))
        XCTAssertEqual(reloaded.state.clickGrowth, 540_000 + ClickGrowth.tokensPerClick)
    }

    func testImportCarriesClickGrowth() {
        var imported = CompanionState()
        imported.clickGrowth = 5_000_000
        let rebased = SaveTransfer.rebasedForThisDevice(imported, current: CompanionState(), todayTokensByProvider: [:],
                                                        todayDate: "2026-11-12", hasUsageData: false)
        XCTAssertEqual(rebased.clickGrowth, 5_000_000)
    }

    func testSanitizeClampsClickGrowth() {
        var state = CompanionState()
        state.clickGrowth = -5
        XCTAssertEqual(SaveTransfer.sanitized(state).clickGrowth, 0)
    }

    func testClickingAloneGraduatesACommonLine() async {
        let clock = Clock()
        let store = freshEgg(clock: clock)
        var clicks = 0
        while store.state.dex.isEmpty, clicks < 5_000 {
            clicks += 1
            clock.now += ClickGrowth.minInterval + 0.01
            store.growByClick()
            if store.state.active == nil, store.state.eggUsage >= store.eggHatchThreshold {
                await store.hatchIfNeeded()
            }
        }
        XCTAssertLessThan(clicks, 5_000)
        XCTAssertEqual(store.state.dex.first?.finalID, 3)
    }

    func testHeartParticleKeepsItsGlyph() {
        let burst = PrayerBurst()
        burst.spawn(glyph: PrayerBurst.heart, xFraction: 0.5)
        burst.spawn(xFraction: 0.5)
        XCTAssertEqual(burst.particles.map(\.glyph), [PrayerBurst.heart, PrayerBurst.prayer])
    }
}
