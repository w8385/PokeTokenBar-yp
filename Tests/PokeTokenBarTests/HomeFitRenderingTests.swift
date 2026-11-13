import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct HeavyProvider: UsageProvider {
    let id: String
    let displayName: String
    var reportsCost = true
    let today: DailyUsage
    let enrichment: ProviderEnrichment
    func fetchDaily() async throws -> DailyUsage? { today }
    func fetchEnrichment() async -> ProviderEnrichment { enrichment }
}

private struct HeavyClaudeLimits: ClaudeLimitsProviding {
    let status: LimitStatus
    func fetch(allowKeychainPrompt: Bool) async throws -> LimitStatus { status }
}
private struct HeavyCodexLimits: CodexLimitsProviding {
    let status: CodexRateLimitStatus
    func fetch() async throws -> CodexRateLimitStatus? { status }
}
private struct HeavyStatus: ProviderStatusProviding {
    func fetch() async -> [String: ProviderStatus] {
        ["claude_code": ProviderStatus(indicator: .minor, description: "Elevated errors on Claude Opus")]
    }
}
private struct HeavyPokemon: PokeProviding, PokemonDetailProviding {
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        PokemonDetails(speciesID: speciesID, name: "gyarados", height: 65, weight: 2350, baseExperience: 189,
                       genderRate: 4, types: ["water", "flying"], baseStats: [:], abilities: [], moves: [])
    }
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 129, tree: EvoNode(speciesID: 129, children: [EvoNode(speciesID: 130, children: [])]),
                rarity: .common, names: [129: ["ko": "잉어킹"], 130: ["ko": "갸라도스"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// Home with everything a heavy user sees at once: Claude session + weekly + weekly-model limits,
/// Codex limits, a third provider, an incident banner, a streak and an update banner.
@MainActor
struct HeavyHome {
    let store: UsageStore
    let companion: CompanionStore
    let updater: UpdateChecker
    let nav = PopoverNavigation()
    let language: AppLanguage

    static func make(language: AppLanguage = .ko, withUpdate: Bool = true,
                     defaults: UserDefaults) async throws -> HeavyHome {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("HeavyHome-\(UUID()).json")
        var state = CompanionState()
        state.language = language
        state.active = MonState(baseID: 129, pathIDs: [129, 130], stageIndex: 1,
                                usedAtStage: 170_100_000, rarity: .common, totalForms: 2, nature: .hardy)
        try JSONEncoder().encode(state).write(to: file)
        let companion = CompanionStore(provider: HeavyPokemon(), fileURL: file, defaults: defaults)

        let formatter = LocalUsageReader.localDayFormatter()
        let now = Date()
        let monthStart = LocalUsageReader.startOfMonth(now)
        let dayCount = Calendar.current.component(.day, from: now)
        let series = (0..<dayCount).map { offset -> DailyUsage in
            let date = Calendar.current.date(byAdding: .day, value: offset, to: monthStart)!
            let tokens = (offset % 6 + 1) * 2_300_000
            return DailyUsage(date: formatter.string(from: date), inputTokens: tokens / 2, outputTokens: tokens / 2,
                              cacheCreationTokens: 0, cacheReadTokens: 0, totalTokens: tokens,
                              totalCost: Double(tokens) / 1_000_000 * 3)
        }
        let todayKey = formatter.string(from: now)
        func provider(_ id: String, _ name: String, scale: Int) -> HeavyProvider {
            var today = DailyUsage(date: todayKey, inputTokens: 1_200_000 * scale, outputTokens: 400_000 * scale,
                                   cacheCreationTokens: 3_100_000 * scale, cacheReadTokens: 9_800_000 * scale,
                                   totalTokens: 14_500_000 * scale, totalCost: 21.4 * Double(scale))
            today.models = ["claude-opus-4-5": 9_000_000 * scale, "claude-sonnet-4-5": 4_000_000 * scale,
                            "claude-haiku-4-5": 1_500_000 * scale]
            let blockEnd = ISO8601DateFormatter().string(from: now.addingTimeInterval(2 * 3600))
            let blockStart = ISO8601DateFormatter().string(from: now.addingTimeInterval(-3 * 3600))
            let enrichment = ProviderEnrichment(
                activeBlock: BlockUsage(id: "b", startTime: blockStart, endTime: blockEnd, isActive: true,
                                        totalTokens: 6_000_000 * scale, costUSD: 9, tokensPerMinute: 40_000),
                blocksOK: true,
                weekTotal: PeriodUsage(period: formatter.string(from: LocalUsageReader.startOfWeek(now)),
                                       totalTokens: 61_000_000 * scale, totalCost: 140),
                monthTotal: PeriodUsage(period: LocalUsageReader.monthKey(now),
                                        totalTokens: 190_000_000 * scale, totalCost: 520),
                monthDaily: series, periodsOK: true)
            return HeavyProvider(id: id, displayName: name, today: today, enrichment: enrichment)
        }

        func iso(_ hours: Double) -> String { ISO8601DateFormatter().string(from: now.addingTimeInterval(hours * 3600)) }
        let claudeJSON = """
        {"five_hour":{"utilization":42,"resets_at":"\(iso(2))"},
         "seven_day":{"utilization":63,"resets_at":"\(iso(72))"},
         "seven_day_opus":{"utilization":28,"resets_at":"\(iso(72))"},
         "seven_day_sonnet":{"utilization":11,"resets_at":"\(iso(72))"},
         "limits":[{"kind":"weekly_scoped","percent":35,"resets_at":"\(iso(72))",
                    "scope":{"model":{"display_name":"Claude Design"}}}]}
        """
        var claude = try JSONDecoder().decode(LimitStatus.self, from: Data(claudeJSON.utf8))
        claude.planDisplayName = "Ultra"
        claude.accountEmail = "dev@example.com"
        let epoch = Int(now.timeIntervalSince1970)
        let codexJSON = """
        {"rateLimits":{"limitId":"codex","planType":"pro",
          "primary":{"usedPercent":33,"windowDurationMins":300,"resetsAt":\(epoch + 7200)},
          "secondary":{"usedPercent":57,"windowDurationMins":10080,"resetsAt":\(epoch + 259_200)}}}
        """
        let codex = try JSONDecoder().decode(CodexRateLimitStatus.self, from: Data(codexJSON.utf8))

        let store = UsageStore(
            providers: [provider("claude_code", "Claude Code", scale: 1), provider("codex", "Codex", scale: 1),
                        provider("gemini", "Gemini CLI", scale: 1)],
            claudeLimitsProvider: HeavyClaudeLimits(status: claude), discoverClaudeConfigDirs: { [] },
            readDefaultIdentity: { nil }, claudeUsageEntries: { _ in [] },
            codexLimitsProvider: HeavyCodexLimits(status: codex), statusProvider: HeavyStatus(),
            autoRefresh: false, defaults: defaults)
        await store.refresh(scheduleEmptyRetry: false)
        companion.update(todayTokensByProvider: [:], todayDate: todayKey, monthTotal: 0, burnTier: .idle,
                         limitWarning: false, hasUsageData: true)
        try await Task.sleep(for: .milliseconds(300))

        var fetched: UpdateChecker.LatestRelease?
        if withUpdate {
            fetched = UpdateChecker.LatestRelease(tag: "v2.5.7-yp99", url: "https://github.com/w8385/PokeTokenBar-yp/releases/tag/v2.5.7-yp99")
        }
        let updater = UpdateChecker(currentVersion: "2.5.7-yp1", defaults: defaults, fetchLatest: { fetched })
        await updater.check(minInterval: 0)
        return HeavyHome(store: store, companion: companion, updater: updater, language: language)
    }

    /// The popover as the app builds it, offered `screenHeight` of visible screen.
    func popover(screenHeight: CGFloat = 5000) -> some View {
        PopoverView(screenHeight: screenHeight)
            .environment(store).environment(companion).environment(updater).environment(nav)
            .environment(\.colorScheme, .dark)
            .environment(\.controlActiveState, .active)
    }
}

@MainActor
final class HomeFitRenderingTests: XCTestCase {
    private func heavy() async throws -> (HeavyHome, () -> Void) {
        let suite = "HomeFit-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let home = try await HeavyHome.make(defaults: defaults)
        return (home, { defaults.removePersistentDomain(forName: suite) })
    }

    private func settle(_ view: some View, width: CGFloat, height: CGFloat? = nil) async throws -> NSHostingView<AnyView> {
        let host = NSHostingView(rootView: AnyView(view
            .background(Color(nsColor: NSColor(calibratedWhite: 0.16, alpha: 1)))))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height ?? 2000)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: width, height: height ?? 2000),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.orderFront(nil)
        addTeardownBlock { window.close() }
        try await Task.sleep(for: .milliseconds(400))
        host.layoutSubtreeIfNeeded()
        return host
    }

    /// Sizes the host to the popover's own fitting height, as NSPopover does, and reports whether
    /// its tallest vertical scroll view has content below the fold.
    private func fit(_ host: NSHostingView<AnyView>) -> (height: CGFloat, scrolls: Bool) {
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        var scrollViews: [NSScrollView] = []
        func collect(_ view: NSView) {
            if let scroll = view as? NSScrollView { scrollViews.append(scroll) }
            view.subviews.forEach(collect)
        }
        collect(host)
        let tallest = scrollViews.max { $0.frame.height < $1.frame.height }
        let overflow = (tallest?.documentView?.frame.height ?? 0) - (tallest?.contentView.bounds.height ?? 0)
        return (size.height, overflow > 1)
    }

    private func saveShot(_ host: NSHostingView<AnyView>, as name: String) throws {
        guard let dir = ProcessInfo.processInfo.environment["PTB_HOMEFIT_SHOTS"] else { return }
        let size = host.bounds.size
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    func testHeavyHomeShowsEverythingWithoutScrolling() async throws {
        let (home, cleanup) = try await heavy()
        defer { cleanup() }
        XCTAssertNotNil(home.updater.available)
        XCTAssertGreaterThan(home.store.currentStreak.days, 1)
        XCTAssertEqual(home.store.snapshots.count, 3)

        let host = try await settle(home.popover(screenHeight: 1000), width: PopoverMetrics.width)
        let result = fit(host)
        print("HOMEFIT heavy popover height \(result.height)")
        XCTAssertFalse(result.scrolls, "heavy Home must show all of it at once")
        XCTAssertLessThanOrEqual(result.height, 1000 - PopoverMetrics.screenMargin)
        try saveShot(host, as: ProcessInfo.processInfo.environment["PTB_HOMEFIT_NAME"] ?? "home-after")
    }

    func testHomeScrollsInsteadOfOverflowingASmallScreen() async throws {
        let (home, cleanup) = try await heavy()
        defer { cleanup() }
        let screen: CGFloat = 640
        let host = try await settle(home.popover(screenHeight: screen), width: PopoverMetrics.width)
        let result = fit(host)
        XCTAssertTrue(result.scrolls)
        XCTAssertLessThanOrEqual(result.height, screen - PopoverMetrics.screenMargin)
    }

    func testOtherTabsKeepTheirHeight() async throws {
        let (home, cleanup) = try await heavy()
        defer { cleanup() }
        // Cap Home at exactly the tab height: then its popover is the reference every tab must match.
        let reference = PopoverMetrics.tabHeight + PopoverMetrics.chromeHeight
            + PopoverMetrics.updateBannerHeight + PopoverMetrics.screenMargin
        let homeHost = try await settle(home.popover(screenHeight: reference), width: PopoverMetrics.width)
        let homeHeight = fit(homeHost).height
        // The Bag is left out: an empty bag has no fixed height.
        for tab in [PopoverTab.shop, .battle, .collection] {
            home.nav.tab = tab
            let host = try await settle(home.popover(screenHeight: 5000), width: PopoverMetrics.width)
            XCTAssertEqual(fit(host).height, homeHeight, accuracy: 1, "\(tab)")
        }
    }
}
