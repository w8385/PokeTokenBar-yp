import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// Opt-in offscreen capture of the popover tab bar with the Friends tab selected, in every language.
///
///     PTB_TABBAR_SHOT_DIR=/tmp/shots swift test --filter TabBarScreenshotTests
@MainActor
final class TabBarScreenshotTests: XCTestCase {
    func testCaptureFriendsTabSelected() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_TABBAR_SHOT_DIR"] else {
            throw XCTSkip("Set PTB_TABBAR_SHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for language in AppLanguage.allCases {
            var selection = PopoverTab.coworkers
            let size = NSSize(width: PopoverMetrics.contentWidth + 28, height: 44)
            try await OffscreenRender.capture(
                PopoverTabPicker(selection: Binding(get: { selection }, set: { selection = $0 }), l: L(language))
                    .padding(14).frame(width: size.width, height: size.height)
                    .background(Color(nsColor: .windowBackgroundColor)),
                size: size, appearance: .aqua, scale: 2,
                to: directory.appendingPathComponent("tabbar-friends-\(language.rawValue).png"))
        }
    }
}
