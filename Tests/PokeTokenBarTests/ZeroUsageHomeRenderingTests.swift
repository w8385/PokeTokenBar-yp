import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct QuietHomeProvider: UsageProvider {
    let id = "fixture"
    let displayName = "Fixture"
    var reportsCost = false
    let enrichment: ProviderEnrichment
    func fetchDaily() async throws -> DailyUsage? { nil }
    func fetchEnrichment() async -> ProviderEnrichment { enrichment }
}

private struct QuietHomeClaude: ClaudeLimitsProviding {
    func fetch(allowKeychainPrompt: Bool) async throws -> LimitStatus {
        throw LimitsError.keychainInteractionNotAllowed
    }
}
private struct QuietHomeCodex: CodexLimitsProviding {
    func fetch() async throws -> CodexRateLimitStatus? { nil }
}
private struct QuietHomeAntigravity: AntigravityLimitsProviding {
    func fetch(allowKeychainPrompt: Bool) async throws -> AntigravityRateLimitStatus {
        throw LimitsError.keychainInteractionNotAllowed
    }
}
private struct QuietHomeCursor: CursorLimitsProviding {
    func fetch() async throws -> CursorRateLimitStatus? { nil }
}
private struct QuietHomeStatus: ProviderStatusProviding {
    func fetch() async -> [String: ProviderStatus] { [:] }
}
private struct QuietHomePokemon: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 129, tree: EvoNode(speciesID: 129, children: [EvoNode(speciesID: 130, children: [])]),
                rarity: .common, names: [129: ["ko": "잉어킹"], 130: ["ko": "갸라도스"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// Render the production home after the real refresh pipeline returns no usage today.
/// Optional PNG output is fixture data, isolated from the user's saves and credentials.
@MainActor
final class ZeroUsageHomeRenderingTests: XCTestCase {
    func testQuietDayKeepsHistoricalGraphVisible() async throws {
        try await render(history: true)
    }

    func testEmptyHistoryStillShowsZeroPeriodSummaries() async throws {
        try await render(history: false)
    }

    func testRecapLabelKeepsPeriodCostsOnOneLine() async throws {
        for language in [AppLanguage.en, .de] {
            try await render(history: true, language: language, costs: .source)
        }
    }

    func testUnavailablePeriodCostsKeepGermanHomeWithinPopover() async throws {
        try await render(history: true, language: .de, costs: .unavailable)
    }

    private func render(history: Bool, language: AppLanguage = .ko, costs: CostCoverage? = nil) async throws {
        let suite = "QuietHome-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json")
        defer { try? FileManager.default.removeItem(at: file) }
        var state = CompanionState()
        state.language = language
        state.active = MonState(baseID: 129, pathIDs: [129, 130], stageIndex: 1,
                                usedAtStage: 170_100_000, rarity: .common, totalForms: 2, nature: .hardy)
        try JSONEncoder().encode(state).write(to: file)
        let companion = CompanionStore(provider: QuietHomePokemon(), fileURL: file, defaults: defaults)
        companion.update(todayTokensByProvider: [:], todayDate: LocalUsageReader.todayKey(), monthTotal: 0,
                         burnTier: .idle, limitWarning: false, hasUsageData: false)
        let formatter = LocalUsageReader.localDayFormatter()
        let now = Date()
        let monthStart = LocalUsageReader.startOfMonth(now)
        let day = Calendar.current.component(.day, from: now)
        let series = (0..<day).map { offset in
            let date = Calendar.current.date(byAdding: .day, value: offset, to: monthStart)!
            let tokens = history && offset < day - 1 ? (offset % 6 + 1) * 230_000 : 0
            return DailyUsage(date: formatter.string(from: date), inputTokens: tokens, outputTokens: 0,
                              cacheCreationTokens: 0, cacheReadTokens: 0, totalTokens: tokens, totalCost: 0)
        }
        let weekKey = formatter.string(from: LocalUsageReader.startOfWeek(now))
        let enrichment = ProviderEnrichment(blocksOK: true,
            weekTotal: costs != nil
                ? PeriodUsage(period: weekKey, totalTokens: 4_800_000, totalCost: costs == .unavailable ? 0 : 31.64,
                              costCoverage: costs ?? .source)
                : PeriodUsage(period: weekKey, daily: series.filter { $0.date >= weekKey }),
            monthTotal: costs != nil
                ? PeriodUsage(period: LocalUsageReader.monthKey(now), totalTokens: 17_900_000,
                              totalCost: costs == .unavailable ? 0 : 121.30,
                              costCoverage: costs ?? .source)
                : PeriodUsage(period: LocalUsageReader.monthKey(now), daily: series),
            monthDaily: series, periodsOK: true)
        let store = UsageStore(providers: [QuietHomeProvider(reportsCost: costs != nil, enrichment: enrichment)],
            claudeLimitsProvider: QuietHomeClaude(), discoverClaudeConfigDirs: { [] },
            readDefaultIdentity: { nil }, claudeUsageEntries: { _ in [] },
            codexLimitsProvider: QuietHomeCodex(), antigravityLimitsProvider: QuietHomeAntigravity(),
            cursorLimitsProvider: QuietHomeCursor(), statusProvider: QuietHomeStatus(),
            autoRefresh: false, defaults: defaults)
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.todayTotalTokens, 0)
        XCTAssertEqual(store.monthTotalTokens, costs != nil ? 17_900_000 : series.reduce(0) { $0 + $1.totalTokens })

        let l = companion.l
        let periodRow = PeriodTotalsRow(l: l, weekTokens: store.weekTotalTokens, monthTokens: store.monthTotalTokens,
                                        weekCost: store.showsCost ? store.weekUsageCost : nil,
                                        monthCost: store.showsCost ? store.monthUsageCost : nil)
        // The row draws these strings, so a blank or untranslated one fails here.
        let labels = [l.todayTokens, l.thisWeek, l.thisMonth]
        XCTAssertFalse(labels.contains(where: \.isEmpty))
        XCTAssertEqual(Set(labels).count, labels.count, "period labels must differ in \(language.rawValue)")
        LayoutMeasure.assertLabelsNeverWrap(periodRow, within: PopoverMetrics.contentWidth,
                                            "period totals in \(language.rawValue)")

        if costs == .source {
            XCTAssertTrue(store.showsCost)
            for (cost, amount) in [(store.weekUsageCost, "$31.64"), (store.monthUsageCost, "$121.30")] {
                XCTAssertEqual(cost.text(l), amount, "period cost in \(language.rawValue)")
            }
        }
        if costs == .unavailable {
            for cost in [store.weekUsageCost, store.monthUsageCost] {
                XCTAssertEqual(cost.text(l), l.costUnavailable, "unavailable cost in \(language.rawValue)")
            }
        }
        if costs == nil {
            // The cost fixtures target the period row; the quiet-day fixtures own the chart.
            let chart = ActivityPanel(visualization: .monthlyBars, series: store.dailyTrendTotals,
                                      providers: store.trendProviders, providerOrder: store.registeredProviderIDs,
                                      showsCost: store.showsCost,
                                      window: .constant(store.dailyTrendWindow),
                                      hasAvailableHistory: store.hasDailyTrendHistory,
                                      today: LocalUsageReader.todayKey(), l: l, onCycle: {})
            let chartHeight = LayoutMeasure.size(chart, width: PopoverMetrics.contentWidth).height
            if history && day > 1 {
                XCTAssertGreaterThan(chartHeight, 20, "Historical chart missing")
            } else {
                XCTAssertEqual(chartHeight, 0, accuracy: 0.5, "Empty history must not invent a chart")
            }
        }

        if let output = ProcessInfo.processInfo.environment["PTB_ZERO_USAGE_SCREENSHOT_DIR"] {
            let height = 604.0
            let host = OffscreenRender.host(PopoverView()
                .environment(store).environment(companion).environment(UpdateChecker(defaults: defaults))
                .environment(PopoverNavigation()).environment(\.colorScheme, .dark)
                .environment(\.controlActiveState, .active)
                .frame(width: PopoverMetrics.width, height: height)
                .background(Color(nsColor: NSColor(calibratedWhite: 0.07, alpha: 1))),
                size: CGSize(width: PopoverMetrics.width, height: height), appearance: .darkAqua)
            try await OffscreenRender.settle(host)
            let directory = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let name = costs != nil ? "\(language.rawValue)-period-costs-\(costs == .source ? "known" : "unavailable").png"
                : (history ? "ko-zero-today-with-history.png" : "ko-zero-all-periods.png")
            try OffscreenRender.writePNG(of: host, to: directory.appendingPathComponent(name), scale: 2)
        }
    }
}
