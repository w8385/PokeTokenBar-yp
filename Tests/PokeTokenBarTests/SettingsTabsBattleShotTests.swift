import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// Opt-in capture of the unlinked Battle tab for the PR; the suffix names the before/after run.
///
///     PTB_SETTINGSTABS_SCREENSHOT_DIR=/tmp/shots PTB_SETTINGSTABS_SUFFIX=after swift test --filter SettingsTabsBattleShotTests
@MainActor
final class SettingsTabsBattleShotTests: XCTestCase {
    func testCaptureUnlinkedBattleTab() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_SETTINGSTABS_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_SETTINGSTABS_SCREENSHOT_DIR to write the PR screenshots")
        }
        let suffix = ProcessInfo.processInfo.environment["PTB_SETTINGSTABS_SUFFIX"] ?? "after"
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
        let uploader = PartyUploader(
            tokenStore: PartyTokenStore(fileURL: scratch.appendingPathComponent("token")), defaults: defaults,
            appVersion: "shot", exchange: { _ in (Data(), 200) }, fetch: { _ in (Data(), 404) },
            partySource: { [] })
        let size = NSSize(width: PopoverMetrics.contentWidth, height: 520)
        try await OffscreenRender.capture(
            BattleView(store: store, navigation: PopoverNavigation(defaults: defaults))
                .environment(uploader).environment(BattleEntryStore(defaults: defaults)).environment(store)
                .frame(width: size.width, height: size.height, alignment: .top)
                .background(Color.white)
                .environment(\.colorScheme, .light)
                .environment(\.locale, AppLanguage.ko.displayLocale),
            size: size, appearance: .aqua, scale: 2,
            to: directory.appendingPathComponent("settings-tabs-battle-unlinked-\(suffix).png"))
    }
}
