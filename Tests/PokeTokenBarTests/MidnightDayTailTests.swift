import Foundation
import XCTest
@testable import PokeTokenBar

private let twoStageLine = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: [EvoNode(speciesID: 2, children: [])]),
                           rarity: .common, names: [:])

/// Polling stops while the display sleeps, so the first refresh after midnight is the first one to
/// see the new date. Whatever the agents wrote after the last refresh of the old day is only in
/// that day's final total.
@MainActor
final class MidnightDayTailTests: XCTestCase {
    private func store() -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        return CompanionStore(provider: StubProvider(value: twoStageLine), clock: { Date(timeIntervalSince1970: 1_700_000_000) },
                              fileURL: url, rng: SeededRNG(seed: 7))
    }

    private func use(_ s: CompanionStore, _ today: [String: Int], date: String,
                     days: [String: [String: Int]]? = [:]) {
        s.update(todayTokensByProvider: today, todayDate: date, monthTotal: 0, burnTier: .idle,
                 limitWarning: false, hasUsageData: true, dayTotalsByProvider: days)
    }

    private func claudeUsed100On9th() -> CompanionStore {
        let s = store()
        use(s, ["claude_code": 0], date: "2026-11-09")
        use(s, ["claude_code": 100], date: "2026-11-09")
        XCTAssertEqual(s.state.usedSinceInstall, 100)
        return s
    }

    func testScreenOffAcrossMidnightStillCreditsYesterdaysTail() {
        let s = claudeUsed100On9th()
        let days = ["claude_code": ["2026-11-09": 200, "2026-11-10": 150]]

        use(s, ["claude_code": 150], date: "2026-11-10", days: days)

        XCTAssertEqual(s.state.usedSinceInstall, 350, "the 9th's last 100 plus the 10th's 150")
        XCTAssertEqual(s.state.lastDate, "2026-11-10")
        XCTAssertEqual(s.state.claimedTodayTokensByProvider, ["claude_code": 150])

        use(s, ["claude_code": 150], date: "2026-11-10", days: days)
        XCTAssertEqual(s.state.usedSinceInstall, 350, "the next refresh does not credit the tail again")
        use(s, ["claude_code": 170], date: "2026-11-10", days: ["claude_code": ["2026-11-09": 200, "2026-11-10": 170]])
        XCTAssertEqual(s.state.usedSinceInstall, 370)
    }

    func testDayTotalEqualToTheLedgerCreditsOnlyToday() {
        let s = claudeUsed100On9th()

        use(s, ["claude_code": 150], date: "2026-11-10",
            days: ["claude_code": ["2026-11-09": 100, "2026-11-10": 150]])

        XCTAssertEqual(s.state.usedSinceInstall, 250)
    }

    func testProviderWithoutDayTotalsGetsNoTailAndAProviderNewToTheLedgerGetsNoBackCredit() {
        let s = store()
        use(s, ["claude_code": 0, "codex": 0], date: "2026-11-09")
        use(s, ["claude_code": 100, "codex": 50], date: "2026-11-09")
        XCTAssertEqual(s.state.usedSinceInstall, 150)

        use(s, ["claude_code": 10, "codex": 20, "gemini": 5], date: "2026-11-10",
            days: ["claude_code": ["2026-11-09": 300, "2026-11-10": 10],
                   "gemini": ["2026-11-09": 9_000, "2026-11-10": 5]])

        XCTAssertEqual(s.state.usedSinceInstall, 150 + 200 + 10 + 20 + 5,
                       "claude's tail only; codex has no series, gemini was never in the ledger")
    }

    func testSkippedDayIsCreditedInFull() {
        let s = claudeUsed100On9th()

        use(s, ["claude_code": 50], date: "2026-11-11",
            days: ["claude_code": ["2026-11-08": 7_000, "2026-11-09": 200, "2026-11-10": 300, "2026-11-11": 50]])

        XCTAssertEqual(s.state.usedSinceInstall, 100 + 100 + 300 + 50, "days before the ledger's date stay out")
    }

    func testFirstOfMonthCreditsTheLastDayOfThePreviousMonth() {
        let s = store()
        use(s, ["claude_code": 0], date: "2026-10-31")
        use(s, ["claude_code": 100], date: "2026-10-31")

        use(s, ["claude_code": 40], date: "2026-11-01",
            days: ["claude_code": ["2026-10-30": 500, "2026-10-31": 180, "2026-11-01": 40]])

        XCTAssertEqual(s.state.usedSinceInstall, 100 + 80 + 40)
    }

    func testDateChangeBeforeTodaysScanIsHeld() {
        let s = claudeUsed100On9th()

        use(s, ["claude_code": 150], date: "2026-11-10", days: nil)

        XCTAssertEqual(s.state.usedSinceInstall, 100)
        XCTAssertEqual(s.state.lastDate, "2026-11-09")
        XCTAssertEqual(s.state.claimedTodayTokensByProvider, ["claude_code": 100])

        use(s, ["claude_code": 160], date: "2026-11-10",
            days: ["claude_code": ["2026-11-09": 200, "2026-11-10": 160]])
        XCTAssertEqual(s.state.usedSinceInstall, 100 + 100 + 160)
    }

    func testTimeModeDateChangeIsNotHeld() {
        let s = claudeUsed100On9th()
        s.setGrowthMode(.time)

        use(s, ["claude_code": 150], date: "2026-11-10", days: nil)

        XCTAssertEqual(s.state.lastDate, "2026-11-10")
        XCTAssertEqual(s.state.claimedTodayTokensByProvider, ["claude_code": 150])
        XCTAssertEqual(s.state.usedSinceInstall, 100)
    }
}

private func usage(_ date: String, _ tokens: Int) -> DailyUsage {
    DailyUsage(date: date, inputTokens: 0, outputTokens: 0, cacheCreationTokens: 0,
               cacheReadTokens: 0, totalTokens: tokens, totalCost: 0, costCoverage: .source)
}

/// Its enrichment scan can be paused, to look at the store between phase 1 and phase 2.
private final class PausableProvider: UsageProvider, @unchecked Sendable {
    let id = "claude_code"
    let displayName = "Claude Code"
    private let lock = NSLock()
    private var daily: DailyUsage?
    private var series: [DailyUsage] = []
    private var enrichmentFails = false
    private var pauseNext = false
    private var paused: CheckedContinuation<Void, Never>?

    func set(daily: DailyUsage, series: [DailyUsage], enrichmentFails: Bool = false) {
        lock.withLock { self.daily = daily; self.series = series; self.enrichmentFails = enrichmentFails }
    }
    func pauseNextEnrichment() { lock.withLock { pauseNext = true } }
    var isPaused: Bool { lock.withLock { paused != nil } }
    func resume() { lock.withLock { paused?.resume(); paused = nil } }

    func fetchDaily() async throws -> DailyUsage? { lock.withLock { daily } }
    func fetchEnrichment() async -> ProviderEnrichment {
        if lock.withLock({ defer { pauseNext = false }; return pauseNext }) {
            await withCheckedContinuation { continuation in lock.withLock { paused = continuation } }
        }
        return lock.withLock {
            var enrichment = ProviderEnrichment()
            guard !enrichmentFails else { return enrichment }
            enrichment.periodsOK = true
            enrichment.monthDaily = series
            enrichment.recentDaily = series
            return enrichment
        }
    }
}

@MainActor
final class UsageStoreDayTotalsTests: XCTestCase {
    private let noon9th = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12))!
    private var noon10th: Date { Calendar.current.date(byAdding: .day, value: 1, to: noon9th)! }

    private func storeAfterA9thRefresh(_ provider: PausableProvider) async -> UsageStore {
        provider.set(daily: usage("2026-11-09", 100), series: [usage("2026-11-08", 7), usage("2026-11-09", 100)])
        let store = UsageStore.offline(providers: [provider],
                                       defaults: UserDefaults(suiteName: "day-totals-\(UUID().uuidString)")!,
                                       pinnedNow: noon9th)
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.dayTotalsByProvider, ["claude_code": ["2026-11-08": 7, "2026-11-09": 100]])
        return store
    }

    func testAfterMidnightTheSeriesCarriedThroughPhaseOneIsNotDayTotals() async throws {
        let provider = PausableProvider()
        let store = await storeAfterA9thRefresh(provider)
        store.pinnedNow = noon10th
        provider.set(daily: usage("2026-11-10", 150),
                     series: [usage("2026-11-08", 7), usage("2026-11-09", 200), usage("2026-11-10", 150)])
        provider.pauseNextEnrichment()

        let refresh = Task { await store.refresh(scheduleEmptyRetry: false) }
        try await waitUntil("the enrichment scan to pause") { provider.isPaused }

        XCTAssertEqual(store.todayTokensByProvider, ["claude_code": 150])
        XCTAssertEqual(store.snapshots.first?.monthDaily?.last?.date, "2026-11-09", "phase 1 carried the 9th's series")
        XCTAssertNil(store.dayTotalsByProvider)

        provider.resume()
        await refresh.value
        XCTAssertEqual(store.dayTotalsByProvider?["claude_code"]?["2026-11-09"], 200)
    }

    func testFailedEnrichmentLeavesThatProviderOut() async {
        let provider = PausableProvider()
        let store = await storeAfterA9thRefresh(provider)
        store.pinnedNow = noon10th
        provider.set(daily: usage("2026-11-10", 150), series: [], enrichmentFails: true)

        await store.refresh(scheduleEmptyRetry: false)

        XCTAssertEqual(store.dayTotalsByProvider, [:], "released, with no tail for the provider that failed")
    }
}

final class DayTailReaderTests: XCTestCase {
    func testScanOnAMondayFirstStillReadsTheLastDayOfThePreviousMonth() {
        let calendar = Calendar.current
        let noon1st = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 12))!
        let evening31st = calendar.date(from: DateComponents(year: 2026, month: 5, day: 31, hour: 23))!
        let format = LocalUsageReader.localDayFormatter()
        func entry(_ id: String, _ date: Date, _ output: Int) -> LocalUsageReader.Entry {
            LocalUsageReader.Entry(id: id, date: date, localDay: format.string(from: date), model: "m",
                                   input: 0, output: output, cacheWrite: 0, cacheRead: 0)
        }
        let entries = [entry("a", evening31st, 200), entry("b", evening31st.addingTimeInterval(1_800), 50),
                       entry("c", noon1st, 40)]

        XCTAssertLessThanOrEqual(LocalUsageReader.enrichmentScanStart(now: noon1st),
                                 calendar.startOfDay(for: evening31st))
        let recent = ProviderEnrichment.local(entries: entries, now: noon1st).recentDaily ?? []
        XCTAssertEqual(recent.first(where: { $0.date == "2026-05-31" })?.totalTokens, 250)
        XCTAssertEqual(recent.first(where: { $0.date == "2026-06-01" })?.totalTokens,
                       LocalUsageReader.daily(entries: entries, localDay: "2026-06-01")?.totalTokens,
                       "the series counts today the same way fetchDaily does")
    }
}
