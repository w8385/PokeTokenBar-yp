import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// Opt-in README capture of the growth source picker set to time mode. Sample data.
///
///     PTB_GROWTH_MODE_SHOT_DIR=/tmp/shots swift test --filter GrowthModeScreenshotTests
@MainActor
final class GrowthModeScreenshotTests: XCTestCase {
    func testCaptureGrowthModeSection() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_GROWTH_MODE_SHOT_DIR"] else {
            throw XCTSkip("Set PTB_GROWTH_MODE_SHOT_DIR to draw the README image")
        }
        let dir = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("growth-mode-shot-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        for (language, suffix) in [(AppLanguage.en, ""), (.ko, "-ko"), (.ja, "-ja")] {
            var state = CompanionState()
            state.language = language
            state.installBaselineSet = true
            state.growthMode = .time
            let file = scratch.appendingPathComponent("\(language.rawValue).json")
            try JSONEncoder().encode(state).write(to: file)
            let suite = "growth-mode-shot-\(UUID())"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = CompanionStore(fileURL: file, defaults: defaults)
            let view = GrowthModeSection(companion: store)
                .padding(PopoverMetrics.padding)
                .frame(width: PopoverMetrics.width, alignment: .topLeading)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, .light)
                .environment(\.locale, language.displayLocale)
            let height = OffscreenRender.controller(view)
                .sizeThatFits(in: CGSize(width: PopoverMetrics.width, height: 1000)).height.rounded(.up)
            try await OffscreenRender.capture(view.frame(height: height, alignment: .top),
                                              size: CGSize(width: PopoverMetrics.width, height: height),
                                              appearance: .aqua, scale: 2,
                                              to: dir.appendingPathComponent("screenshot-growth-mode\(suffix).png"))
        }
    }
}
