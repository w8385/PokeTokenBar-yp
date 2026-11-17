import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct TimeShotProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 4, tree: EvoNode(speciesID: 4, children: [EvoNode(speciesID: 5, children: [])]),
                rarity: .common, names: [4: ["ko": "파이리", "en": "Charmander"], 5: ["ko": "리자드", "en": "Charmeleon"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// Opt-in captures for the PR, from synthetic saves:
///
///     PTB_TIME_SHOT_DIR=/tmp/shots swift test --filter TimeModeScreenshotTests
@MainActor
final class TimeModeScreenshotTests: XCTestCase {
    func testCaptureTimeModeScreens() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_TIME_SHOT_DIR"] else {
            throw XCTSkip("Set PTB_TIME_SHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("time-shot-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        func makeStore(_ name: String, _ edit: (inout CompanionState) -> Void) throws -> (CompanionStore, UserDefaults) {
            var state = CompanionState()
            state.language = .ko
            state.installBaselineSet = true
            state.active = MonState(baseID: 4, pathIDs: [4], plannedPathIDs: [4, 5], stageIndex: 0,
                                    usedAtStage: 12_500_000, rarity: .common, totalForms: 2,
                                    profile: PokemonProfile.generate(seed: 5, instanceID: "raised"))
            edit(&state)
            let file = scratch.appendingPathComponent("\(name).json")
            try JSONEncoder().encode(state).write(to: file)
            let suite = try XCTUnwrap(UserDefaults(suiteName: "time-shot-\(UUID())"))
            return (CompanionStore(provider: TimeShotProvider(), fileURL: file, defaults: suite), suite)
        }

        let (timeStore, timeDefaults) = try makeStore("time") {
            $0.growthMode = .time
            $0.timeCredit = 12_500_000
        }
        let (hintStore, hintDefaults) = try makeStore("hint") {
            $0.growthMode = .token
            $0.usedSinceInstall = 90_000_000
            $0.tokenModeSince = Date().addingTimeInterval(-10 * 86400)
            $0.lastUsageAt = Date().addingTimeInterval(-4 * 86400)
        }
        XCTAssertEqual(timeStore.growthMode, .time)
        XCTAssertTrue(hintStore.showsIdleTokenHint)

        try await capture(DifficultySettingsSection(companion: timeStore).padding(12), height: 330,
                          to: directory.appendingPathComponent("time-mode-settings.png"))
        try await capture(ShopView(store: timeStore, nav: PopoverNavigation()).environment(timeStore), height: 1300,
                          to: directory.appendingPathComponent("time-mode-wallet.png"))
        try await captureHome(timeStore, defaults: timeDefaults,
                              to: directory.appendingPathComponent("time-mode-home.png"))
        try await captureHome(hintStore, defaults: hintDefaults,
                              to: directory.appendingPathComponent("time-mode-hint.png"))
    }

    private func capture<V: View>(_ view: V, height: CGFloat, to file: URL) async throws {
        let size = NSSize(width: PopoverMetrics.contentWidth, height: height)
        try await OffscreenRender.capture(view.frame(width: size.width, height: size.height)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .environment(\.locale, AppLanguage.ko.displayLocale),
            size: size, appearance: .aqua, scale: 2, settle: .seconds(2), to: file)
    }

    private func captureHome(_ companion: CompanionStore, defaults: UserDefaults, to file: URL) async throws {
        let usage = UsageStore(providers: [], discoverClaudeConfigDirs: { [] }, readDefaultIdentity: { nil },
                               claudeUsageEntries: { _ in [] }, autoRefresh: false, defaults: defaults)
        let height = 604.0
        let size = CGSize(width: PopoverMetrics.width, height: height)
        try await OffscreenRender.capture(PopoverView()
            .environment(usage).environment(companion).environment(UpdateChecker(defaults: defaults))
            .environment(PopoverNavigation()).environment(\.colorScheme, .light)
            .environment(\.controlActiveState, .active)
            .environment(\.locale, AppLanguage.ko.displayLocale)
            .frame(width: size.width, height: size.height)
            .background(Color.white),
            size: size, appearance: .aqua, scale: 2, settle: .seconds(2), to: file)
    }
}
