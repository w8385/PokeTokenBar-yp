import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// Opt-in offscreen capture of the gym-only slot tag in Korean.
///
///     PTB_GYMTAG_SHOT=/tmp/gymtag-after.png swift test --filter GymSlotTagScreenshotTests
@MainActor
final class GymSlotTagScreenshotTests: XCTestCase {
    func testCaptureGymOnlyTag() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_GYMTAG_SHOT"] else {
            throw XCTSkip("Set PTB_GYMTAG_SHOT to write the PR screenshot")
        }
        let label = ProcessInfo.processInfo.environment["PTB_GYMTAG_TEXT"] ?? L(.ko).battleSlotGymOnly
        let size = NSSize(width: 300, height: 40)
        try await OffscreenRender.capture(
            HStack(spacing: 4) {
                Text("4 · \(L(.ko).battleEntryLabel)")
                Text(label).foregroundStyle(Color.orange)
            }
            .font(.caption2).foregroundStyle(.secondary)
            .padding(10).frame(width: size.width, height: size.height, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor)),
            size: size, appearance: .aqua, scale: 2, to: URL(fileURLWithPath: output))
    }
}
