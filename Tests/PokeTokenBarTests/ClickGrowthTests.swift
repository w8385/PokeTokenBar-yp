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

    func testClickGrowsTheEggWithoutTouchingUsageOrWallet() {
        let clock = Clock()
        let store = freshEgg(clock: clock)
        XCTAssertEqual(store.growByClick(), ClickGrowth.tokensPerClick)
        XCTAssertEqual(store.state.eggUsage, ClickGrowth.tokensPerClick)
        XCTAssertEqual(store.state.clickGrowth, ClickGrowth.tokensPerClick)
        XCTAssertEqual(store.state.usedSinceInstall, 0)
    }

    func testClicksKeepCountingPastTheOldDailyLimit() {
        let clock = Clock()
        let store = freshEgg(clock: clock)
        for _ in 0..<250 { store.growByClick() }
        XCTAssertEqual(store.state.clickGrowth, 250 * ClickGrowth.tokensPerClick)
    }

    func testRapidClicksWithNoTimePassingAllCount() {
        let clock = Clock()
        let store = freshEgg(clock: clock)
        for click in 1...10 {
            XCTAssertEqual(store.growByClick(), ClickGrowth.tokensPerClick, "click \(click)")
        }
        XCTAssertEqual(store.state.eggUsage, 10 * ClickGrowth.tokensPerClick)
        XCTAssertEqual(store.state.clickGrowth, 10 * ClickGrowth.tokensPerClick)
    }

    func testOverlappingXPFlashesAddUpAndOnlyTheLastOneHides() {
        var flash = XPFlash()
        let first = flash.show(ClickGrowth.tokensPerClick)
        let second = flash.show(ClickGrowth.tokensPerClick)
        XCTAssertEqual(flash.amount, 2 * ClickGrowth.tokensPerClick)
        flash.hide(first)
        XCTAssertTrue(flash.isShown, "an older flash must not hide a newer one")
        flash.hide(second)
        XCTAssertFalse(flash.isShown)
        _ = flash.show(500)
        XCTAssertEqual(flash.amount, 500, "a flash after the badge hid starts from zero")
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
        XCTAssertEqual(store.growByClick(), ClickGrowth.tokensPerClick)

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
            store.growByClick()
            if store.state.active == nil, store.state.eggUsage >= store.eggHatchThreshold {
                await store.hatchIfNeeded()
            }
        }
        XCTAssertLessThan(clicks, 5_000)
        XCTAssertEqual(store.state.dex.first?.finalID, 3)
    }
}
