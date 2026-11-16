import XCTest
@testable import PokeTokenBar

@MainActor
final class TimeModeTests: XCTestCase {
    /// 01:00 local, so a 12 hour test never crosses midnight by accident.
    private final class Clock {
        var now = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000)).addingTimeInterval(3600)
    }

    private let line = EvoLine(
        baseID: 1,
        tree: EvoNode(speciesID: 1, children: [EvoNode(speciesID: 2, children: [EvoNode(speciesID: 3, children: [])])]),
        rarity: .common,
        names: [1: ["en": "P1"], 2: ["en": "P2"], 3: ["en": "P3"]])

    private var suites: [String] = []

    override func tearDown() {
        for suite in suites { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        suites = []
        super.tearDown()
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("time-mode-\(UUID().uuidString).json")
    }

    private func store(_ json: String, clock: Clock, url: URL? = nil) -> CompanionStore {
        let url = url ?? tempURL()
        try? json.data(using: .utf8)!.write(to: url)
        let suite = "time-mode-\(UUID())"
        suites.append(suite)
        return CompanionStore(provider: StubProvider(value: line), clock: { clock.now }, fileURL: url,
                              rng: SeededRNG(seed: 7), defaults: UserDefaults(suiteName: suite)!)
    }

    private func egg(mode: String = "time", baseline: Bool = true, extra: String = "", clock: Clock,
                     url: URL? = nil) -> CompanionStore {
        store("{\"installBaselineSet\":\(baseline),\"usedSinceInstall\":0,\"spentTokens\":0,\"lastDate\":\"d\","
              + "\"active\":null,\"dex\":[],\"collectedFinals\":[],\"eggUsage\":0,\"pendingHatchID\":1,"
              + "\"growthMode\":\"\(mode)\"\(extra)}", clock: clock, url: url)
    }

    /// Ticks every 30 s of both clocks with the user active; returns the tokens credited.
    @discardableResult
    private func tick(_ store: CompanionStore, _ clock: Clock, uptime: inout TimeInterval, times: Int,
                      idle: TimeInterval = 1, present: Bool = true, step: TimeInterval = 30) -> Int {
        var total = 0
        for _ in 0..<times {
            uptime += step
            clock.now += step
            total += store.creditActiveTime(uptime: uptime, idle: idle, present: present)
        }
        return total
    }

    // MARK: rate

    func testAnActiveDayAtTheCapIsFortyMillionTokens() {
        XCTAssertEqual(Int(PokemonBalance.timeDailyCap / 3600) * PokemonBalance.timeTokensPerActiveHour, 40_000_000)
        XCTAssertEqual(PokemonBalance.timeDailyCap, 8 * 3600)
    }

    func testRateMathAtDifficultyOne() {
        let perHour = Double(PokemonBalance.timeTokensPerActiveHour)
        func hours(_ tokens: Int) -> Double { Double(tokens) / perHour }
        XCTAssertEqual(hours(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 0)), 5, accuracy: 0.01)
        XCTAssertEqual(hours(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 2, stageIndex: 0)), 10, accuracy: 0.01)
        XCTAssertEqual(hours(PokemonBalance.phaseThreshold(rarity: .rare, totalForms: 3, stageIndex: 0)), 20, accuracy: 0.01)
        XCTAssertEqual(hours(PokemonBalance.graduationTotal(.common)), 30, accuracy: 0.01)
        XCTAssertEqual(hours(HeldItem.price), 120, accuracy: 0.01)
        XCTAssertEqual(hours(RareCandy.price), 20, accuracy: 0.01)
    }

    // MARK: crediting

    func testActiveTimeCreditsGrowthAndWalletButNotUsage() {
        let clock = Clock(); var up: TimeInterval = 1000
        let s = egg(clock: clock)
        s.creditActiveTime(uptime: up, idle: 1, present: true)   // anchor
        let credited = tick(s, clock, uptime: &up, times: 10)
        XCTAssertEqual(credited, 10 * 41_666)
        XCTAssertEqual(s.state.eggUsage, credited)
        XCTAssertEqual(s.state.timeCredit, credited)
        XCTAssertEqual(s.availableTokens, credited)
        XCTAssertEqual(s.state.usedSinceInstall, 0)
        XCTAssertNil(s.state.claimedTodayTokensByProvider)
    }

    func testGrowthDifficultyScalesTheThresholdNotTheCredit() {
        for (difficulty, expected) in [(1.0, 0.25), (0.5, 0.5)] {
            let clock = Clock(); var up: TimeInterval = 1000
            let s = egg(clock: clock)
            s.setGrowthDifficulty(difficulty)
            s.creditActiveTime(uptime: up, idle: 1, present: true)
            let credited = tick(s, clock, uptime: &up, times: 6)   // 3 minutes
            XCTAssertEqual(credited, 6 * 41_666, "credit ignores difficulty")
            XCTAssertEqual(s.eggProgress, Double(credited) / Double(PokemonBalance.eggHatchThreshold) / difficulty, accuracy: 1e-9)
            XCTAssertEqual(s.eggProgress, expected, accuracy: 0.01)
        }
    }

    func testShopDifficultyScalesPricesNotTheWallet() {
        let clock = Clock(); var up: TimeInterval = 0
        let s = egg(clock: clock)
        s.creditActiveTime(uptime: up, idle: 1, present: true)
        tick(s, clock, uptime: &up, times: 100)
        let wallet = s.availableTokens
        s.setShopDifficulty(0.5)
        XCTAssertEqual(s.availableTokens, wallet)
        XCTAssertEqual(s.price(of: .mint), Mint.price / 2)
    }

    // MARK: what is not active

    func testIdleForMoreThanFiveMinutesCreditsNothing() {
        let clock = Clock(); var up: TimeInterval = 1000
        let s = egg(clock: clock)
        s.creditActiveTime(uptime: up, idle: 1, present: true)
        XCTAssertEqual(tick(s, clock, uptime: &up, times: 20, idle: PokemonBalance.timeIdleLimit + 1), 0)
        XCTAssertEqual(s.state.timeCredit, 0)
        XCTAssertEqual(tick(s, clock, uptime: &up, times: 1, idle: PokemonBalance.timeIdleLimit + 0.5), 0)
    }

    func testReturningFromIdleCreditsOnlyTimeSinceTheLastInput() {
        var meter = ActiveTimeMeter()
        XCTAssertEqual(meter.step(uptime: 0, idle: 1000, present: true), 0)
        XCTAssertEqual(meter.step(uptime: 30, idle: 1030, present: true), 0)
        XCTAssertEqual(meter.step(uptime: 60, idle: 4, present: true), 4)
        XCTAssertEqual(meter.step(uptime: 90, idle: 5, present: true), 30)
    }

    func testSleepScreenOffAndLockCreditNothingAndTheNextTickOnlyAnchors() {
        let clock = Clock(); var up: TimeInterval = 1000
        let s = egg(clock: clock)
        s.creditActiveTime(uptime: up, idle: 1, present: true)
        XCTAssertEqual(tick(s, clock, uptime: &up, times: 4, present: false), 0)
        XCTAssertEqual(tick(s, clock, uptime: &up, times: 1), 0, "first tick after the break re-anchors")
        XCTAssertGreaterThan(tick(s, clock, uptime: &up, times: 1), 0)
        s.noteActivityBreak()
        XCTAssertEqual(tick(s, clock, uptime: &up, times: 1), 0)
    }

    func testOneTickNeverCreditsMoreThanTheStepCap() {
        let clock = Clock(); var up: TimeInterval = 1000
        let s = egg(clock: clock)
        s.creditActiveTime(uptime: up, idle: 1, present: true)
        let credited = tick(s, clock, uptime: &up, times: 1, step: 6 * 3600)
        XCTAssertEqual(credited, PokemonBalance.timeTokens(forActiveSeconds: PokemonBalance.timeMaxStep))
    }

    // MARK: cap and clock

    func testDailyCapStopsAtEightActiveHoursAndResetsNextDay() {
        let clock = Clock(); var up: TimeInterval = 1000
        let s = egg(clock: clock)
        s.creditActiveTime(uptime: up, idle: 1, present: true)
        let credited = tick(s, clock, uptime: &up, times: 12 * 120)   // 12 hours in 30 s ticks
        XCTAssertEqual(s.state.timeActiveSeconds, PokemonBalance.timeDailyCap, accuracy: 0.001)
        XCTAssertLessThanOrEqual(credited, 40_000_000)
        XCTAssertGreaterThan(credited, 39_900_000)
        let afterCap = s.state.timeCredit
        clock.now += 86_400
        tick(s, clock, uptime: &up, times: 2)
        XCTAssertGreaterThan(s.state.timeCredit, afterCap)
    }

    func testCapSurvivesARestart() {
        let clock = Clock(); var up: TimeInterval = 1000
        let url = tempURL()
        let first = egg(clock: clock, url: url)
        first.creditActiveTime(uptime: up, idle: 1, present: true)
        tick(first, clock, uptime: &up, times: 12 * 120)
        let banked = first.state.timeCredit
        let again = store(try! String(contentsOf: url, encoding: .utf8), clock: clock, url: url)
        up = 5
        again.creditActiveTime(uptime: up, idle: 1, present: true)
        XCTAssertEqual(tick(again, clock, uptime: &up, times: 20), 0)
        XCTAssertEqual(again.state.timeCredit, banked)
    }

    func testWallClockJumpsDoNotMintTime() {
        for jump in [5 * 3600.0, -5 * 3600.0, 30 * 86_400.0] {
            let clock = Clock(); var up: TimeInterval = 1000
            let s = egg(clock: clock)
            s.creditActiveTime(uptime: up, idle: 1, present: true)
            let before = tick(s, clock, uptime: &up, times: 2)
            clock.now += jump
            up += 30
            let after = s.creditActiveTime(uptime: up, idle: 1, present: true)
            XCTAssertEqual(after, 41_666, "a \(jump)s clock change still credits one 30 s interval")
            XCTAssertEqual(before, 2 * 41_666)
        }
    }

    // MARK: exclusivity

    private func usageStore(mode: String, clock: Clock) -> CompanionStore {
        store("{\"installBaselineSet\":true,\"usedSinceInstall\":7,\"spentTokens\":0,\"lastDate\":\"d1\","
              + "\"claimedTodayTokensByProvider\":{\"p\":100},\"active\":null,\"dex\":[],\"collectedFinals\":[],"
              + "\"eggUsage\":0,\"pendingHatchID\":1,\"growthMode\":\"\(mode)\"}", clock: clock)
    }

    private func feed(_ s: CompanionStore, _ total: Int) {
        s.update(todayTokensByProvider: ["p": total], todayDate: "d1", monthTotal: total, burnTier: .idle,
                 limitWarning: false, hasUsageData: true)
    }

    func testTokenUsageIsIgnoredInTimeModeButTheLedgerAdvances() {
        let clock = Clock()
        let s = usageStore(mode: "time", clock: clock)
        feed(s, 1_000_100)
        XCTAssertEqual(s.state.eggUsage, 0)
        XCTAssertEqual(s.state.usedSinceInstall, 7)
        XCTAssertEqual(s.state.claimedTodayTokensByProvider?["p"], 1_000_100)
        XCTAssertNotNil(s.state.lastUsageAt)
        s.setGrowthMode(.token)
        feed(s, 1_000_100)
        XCTAssertEqual(s.state.eggUsage, 0, "switching back never pays what was used meanwhile")
        feed(s, 1_000_600)
        XCTAssertEqual(s.state.eggUsage, 500)
        XCTAssertEqual(s.state.usedSinceInstall, 507)
    }

    func testUsageSeenOnlyAfterSwitchingBackIsNotPaidEither() {
        let clock = Clock()
        let s = usageStore(mode: "time", clock: clock)
        feed(s, 1_000_100)
        s.setGrowthMode(.token)             
        feed(s, 5_000_100)
        XCTAssertEqual(s.state.eggUsage, 0)
        XCTAssertEqual(s.state.usedSinceInstall, 7)
        feed(s, 5_000_600)
        XCTAssertEqual(s.state.eggUsage, 500, "the refresh after that pays normally")
    }

    func testRewindingTheClockDoesNotReopenTheDailyCap() {
        let clock = Clock(); var up: TimeInterval = 1000
        let s = egg(clock: clock)
        s.creditActiveTime(uptime: up, idle: 1, present: true)
        tick(s, clock, uptime: &up, times: 10 * 120)
        XCTAssertEqual(s.state.timeActiveSeconds, PokemonBalance.timeDailyCap, accuracy: 0.001)
        let banked = s.state.timeCredit
        clock.now -= 86_400
        XCTAssertEqual(tick(s, clock, uptime: &up, times: 20), 0)
        clock.now += 2 * 86_400
        XCTAssertGreaterThan(tick(s, clock, uptime: &up, times: 2), 0, "a later day still resets")
        XCTAssertGreaterThan(s.state.timeCredit, banked)
    }

    func testTheHatchCelebrationEndsOnTimeTicksWithoutAUsageUpdate() async {
        let clock = Clock(); var up: TimeInterval = 1000
        let s = egg(clock: clock)
        s.creditActiveTime(uptime: up, idle: 1, present: true)
        tick(s, clock, uptime: &up, times: 2 * 13)
        for _ in 0..<400 where s.state.active == nil { await Task.yield() }
        XCTAssertNotNil(s.state.active)
        for _ in 0..<400 where s.displayState != .levelUp { await Task.yield() }
        XCTAssertEqual(s.displayState, .levelUp)
        tick(s, clock, uptime: &up, times: 1, step: 30)
        clock.now += 10
        tick(s, clock, uptime: &up, times: 1)
        XCTAssertEqual(s.displayState, .working)
    }

    func testTimeCreditGrowsTheRaisedGraduateAndLeavesTheParkedEggAlone() throws {
        let clock = Clock(); var up: TimeInterval = 1000
        var state = CompanionState()
        state.installBaselineSet = true
        state.growthMode = .time
        var profile = PokemonProfile.generate(seed: 11, instanceID: "g")
        profile.level = 5
        state.dex = [DexEntry(id: "g", baseID: 25, finalID: 25, chainOrder: [25], rarity: .common,
                              caughtAt: Date(timeIntervalSince1970: 1_000), isShiny: false, nature: .adamant,
                              profile: profile, names: [25: ["en": "g"]], form: nil)]
        state.raisedEntryID = "g"
        let s = store(String(decoding: try JSONEncoder().encode(state), as: UTF8.self), clock: clock)
        s.creditActiveTime(uptime: up, idle: 1, present: true)
        tick(s, clock, uptime: &up, times: 2 * 60)
        XCTAssertEqual(s.state.eggUsage, 0)
        XCTAssertGreaterThan(s.state.timeCredit, 0)
        XCTAssertGreaterThan(try XCTUnwrap(s.state.dex.first?.profile?.growthTokens), 0)
    }

    func testTimeIsIgnoredInTokenMode() {
        let clock = Clock(); var up: TimeInterval = 1000
        let s = egg(mode: "token", clock: clock)
        s.creditActiveTime(uptime: up, idle: 1, present: true)
        XCTAssertEqual(tick(s, clock, uptime: &up, times: 20), 0)
        XCTAssertEqual(s.state.eggUsage, 0)
        XCTAssertEqual(s.state.timeCredit, 0)
    }

    func testTimeCreditsDoNotTouchUsageStatsOrTheLedger() {
        let clock = Clock(); var up: TimeInterval = 1000
        let s = usageStore(mode: "time", clock: clock)
        s.creditActiveTime(uptime: up, idle: 1, present: true)
        tick(s, clock, uptime: &up, times: 50)
        XCTAssertEqual(s.state.usedSinceInstall, 7)
        XCTAssertEqual(s.state.claimedTodayTokensByProvider, ["p": 100])
        XCTAssertGreaterThan(s.state.timeCredit, 0)
        XCTAssertEqual(SaveSummary(state: s.state).lifetimeTokens, 7)
    }

    func testSwitchingKeepsBalancesAndOnlyChangesTheSource() {
        let clock = Clock(); var up: TimeInterval = 1000
        let s = egg(clock: clock)
        s.creditActiveTime(uptime: up, idle: 1, present: true)
        tick(s, clock, uptime: &up, times: 10)
        let wallet = s.availableTokens, eggUsage = s.state.eggUsage
        s.setGrowthMode(.token)
        XCTAssertEqual(s.availableTokens, wallet)
        XCTAssertEqual(s.state.eggUsage, eggUsage)
        s.setGrowthMode(.time)
        XCTAssertEqual(s.availableTokens, wallet)
        XCTAssertEqual(tick(s, clock, uptime: &up, times: 1), 0, "no retroactive credit: the first tick re-anchors")
    }

    // MARK: no coding agent at all

    func testTimeModeHatchesAnEggWithNoUsageDataAndNoBaseline() async {
        let clock = Clock(); var up: TimeInterval = 1000
        let s = egg(baseline: false, clock: clock)
        s.update(todayTokensByProvider: [:], todayDate: "d1", monthTotal: 0, burnTier: .idle,
                 limitWarning: false, hasUsageData: false)
        XCTAssertTrue(s.state.installBaselineSet)
        s.creditActiveTime(uptime: up, idle: 1, present: true)
        tick(s, clock, uptime: &up, times: 2 * 13)   // 13 minutes > the 1M egg threshold
        for _ in 0..<400 where s.state.active == nil { await Task.yield() }
        XCTAssertNotNil(s.state.active, "the egg hatched from time alone")
        s.update(todayTokensByProvider: ["p": 5_000_000], todayDate: "d1", monthTotal: 0, burnTier: .idle,
                 limitWarning: false, hasUsageData: true)
        XCTAssertEqual(s.state.usedSinceInstall, 0, "a provider appearing later is seeded, not credited")
    }

    func testTickAloneSetsTheBaselineWhenNoUpdateHasRun() {
        let clock = Clock(); var up: TimeInterval = 1000
        let s = egg(baseline: false, clock: clock)
        s.creditActiveTime(uptime: up, idle: 1, present: true)
        tick(s, clock, uptime: &up, times: 2)
        XCTAssertTrue(s.state.installBaselineSet)
        XCTAssertGreaterThan(s.state.eggUsage, 0)
    }

    // MARK: save

    func testAnOldSaveWithoutTheFieldIsTokenMode() {
        let s = egg(mode: "token", clock: Clock())
        XCTAssertEqual(s.growthMode, .token)
        let old = store("{\"installBaselineSet\":true,\"usedSinceInstall\":5,\"active\":null,\"dex\":[]}", clock: Clock())
        XCTAssertEqual(old.growthMode, .token)
        XCTAssertEqual(old.state.timeCredit, 0)
        let junk = store("{\"growthMode\":\"warp\",\"timeCredit\":\"x\"}", clock: Clock())
        XCTAssertEqual(junk.growthMode, .token)
    }

    func testTimeModeAndItsLedgerSurviveARoundTrip() throws {
        let clock = Clock(); var up: TimeInterval = 1000
        let url = tempURL()
        let s = egg(clock: clock, url: url)
        s.creditActiveTime(uptime: up, idle: 1, present: true)
        tick(s, clock, uptime: &up, times: 10)
        let reloaded = store(try String(contentsOf: url, encoding: .utf8), clock: clock, url: url)
        XCTAssertEqual(reloaded.growthMode, .time)
        XCTAssertEqual(reloaded.state.timeCredit, s.state.timeCredit)
        XCTAssertEqual(reloaded.state.timeActiveSeconds, s.state.timeActiveSeconds, accuracy: 0.001)
        XCTAssertEqual(reloaded.state.timeActiveDay, s.state.timeActiveDay)
        let envelope = try SaveTransfer.decode(SaveTransfer.encode(state: s.state, appVersion: "t", deviceName: "d", now: clock.now))
        XCTAssertEqual(envelope.state.growthMode, .time)
        XCTAssertEqual(envelope.state.timeCredit, s.state.timeCredit)
    }

    func testImportKeepsThisMacsCapLedgerAndClampsHugeValues() {
        var current = CompanionState()
        current.timeActiveDay = "2026-11-16"
        current.timeActiveSeconds = 7000
        var incoming = CompanionState()
        incoming.growthMode = .time
        incoming.timeActiveDay = "2020-01-01"
        incoming.timeActiveSeconds = 1
        let rebased = SaveTransfer.rebasedForThisDevice(incoming, current: current, todayTokensByProvider: [:],
                                                        todayDate: "d", hasUsageData: false)
        XCTAssertEqual(rebased.growthMode, .time)
        XCTAssertEqual(rebased.timeActiveDay, "2026-11-16")
        XCTAssertEqual(rebased.timeActiveSeconds, 7000)
        var hostile = CompanionState()
        hostile.timeCredit = Int.max
        hostile.timeActiveSeconds = .infinity
        let clean = SaveTransfer.sanitized(hostile)
        XCTAssertEqual(clean.timeCredit, SaveTransfer.maxTokenValue)
        XCTAssertEqual(clean.timeActiveSeconds, 0)
    }

    // MARK: hint

    func testHintAppearsAfterThreeDaysWithoutUsageAndCanBeDismissed() {
        let clock = Clock()
        let s = egg(mode: "token", clock: clock)
        XCTAssertFalse(s.showsIdleTokenHint)
        clock.now += 3 * 86_400 - 60
        XCTAssertFalse(s.showsIdleTokenHint)
        clock.now += 120
        XCTAssertTrue(s.showsIdleTokenHint)
        s.dismissIdleTokenHint()
        XCTAssertFalse(s.showsIdleTokenHint)
    }

    func testTheHintCountdownSurvivesARestartWithoutAnyUsageData() {
        let clock = Clock(); var up: TimeInterval = 1000
        let url = tempURL()
        let first = egg(mode: "token", clock: clock, url: url)
        first.creditActiveTime(uptime: up, idle: 1, present: true)
        let started = first.state.tokenModeSince
        XCTAssertNotNil(started)
        clock.now += 2 * 86_400
        let again = store(try! String(contentsOf: url, encoding: .utf8), clock: clock, url: url)
        up += 1
        XCTAssertEqual(again.state.tokenModeSince, started)
        XCTAssertFalse(again.showsIdleTokenHint)
        clock.now += 1.5 * 86_400
        XCTAssertTrue(again.showsIdleTokenHint, "counted from the first launch, not from the restart")
    }

    func testUsageResetsTheHintAndTimeModeNeverShowsIt() {
        let clock = Clock()
        let s = usageStore(mode: "token", clock: clock)
        clock.now += 4 * 86_400
        XCTAssertTrue(s.showsIdleTokenHint)
        feed(s, 5_000)
        XCTAssertFalse(s.showsIdleTokenHint)
        clock.now += 4 * 86_400
        XCTAssertTrue(s.showsIdleTokenHint)
        s.setGrowthMode(.time)
        XCTAssertFalse(s.showsIdleTokenHint)
        s.setGrowthMode(.token)
        XCTAssertFalse(s.showsIdleTokenHint, "switching back starts a fresh three days")
    }
}
