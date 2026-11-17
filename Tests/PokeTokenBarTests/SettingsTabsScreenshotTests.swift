import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// Opt-in captures of every Settings tab for the PR, from synthetic state.
///
///     PTB_SETTINGSTABS_SCREENSHOT_DIR=/tmp/shots swift test --filter SettingsTabsScreenshotTests
@MainActor
final class SettingsTabsScreenshotTests: XCTestCase {
    func testCaptureEverySettingsTab() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_SETTINGSTABS_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_SETTINGSTABS_SCREENSHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("settingstabs-shot-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let defaults = UserDefaults(suiteName: "settingstabs-shot-\(UUID())")!
        var state = CompanionState()
        state.language = .ko
        let file = scratch.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(fileURL: file, defaults: defaults)
        let usage = UsageStore(providers: [], autoRefresh: false, defaults: defaults)
        let uploader = PartyUploader(
            tokenStore: PartyTokenStore(fileURL: scratch.appendingPathComponent("token")), defaults: defaults,
            appVersion: "shot", exchange: { _ in (Data(), 200) }, fetch: { _ in (Data(), 404) },
            partySource: { [] })
        let size = NSSize(width: PopoverMetrics.width, height: 460)
        for tab in SettingsTab.allCases {
            try await OffscreenRender.capture(
                SettingsView(onClose: {}, onChooseRepresentative: {}, tab: .constant(tab))
                    .environment(usage).environment(store).environment(UpdateChecker()).environment(uploader)
                    .frame(width: size.width, height: size.height)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, .light)
                    .environment(\.locale, AppLanguage.ko.displayLocale),
                size: size, appearance: .aqua, scale: 2,
                to: directory.appendingPathComponent("settings-tabs-\(tab.rawValue).png"))
        }
    }
}
