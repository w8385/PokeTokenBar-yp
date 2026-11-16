import SwiftUI
import XCTest

/// A test run must never show a window or activate the app: the user is working in another app while
/// leaves run `swift test`. Every render goes through `OffscreenRender`, the only file allowed to build a window.
final class OffscreenRenderGuardTests: XCTestCase {
    private static let allowedFiles: Set<String> = ["OffscreenRender.swift", "OffscreenRenderGuardTests.swift"]

    private static let forbidden: [(name: String, pattern: String)] = [
        ("orderFront / orderBack / orderWindow", #"\border(Front|FrontRegardless|Back|Window)\b"#),
        ("makeKey / makeKeyAndOrderFront / makeMain", #"\bmake(Key|Main)(AndOrderFront)?\b"#),
        ("activate(", #"\bactivate\("#),
        ("NSWindow( / NSPanel(", #"\bNS(Window|Panel)\("#),
        ("NSWorkspace", #"\bNSWorkspace\b"#),
        ("launching /usr/bin/open", #"/usr/bin/open\b"#),
    ]

    func testNoTestShowsAWindowOrActivatesTheApp() throws {
        let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: tests, includingPropertiesForKeys: nil))
        var offenders: [String] = []

        for case let url as URL in enumerator
        where url.pathExtension == "swift" && !Self.allowedFiles.contains(url.lastPathComponent) {
            let source = try String(contentsOf: url, encoding: .utf8)
                .replacingOccurrences(of: #"/\*[\s\S]*?\*/"#, with: "", options: .regularExpression)
            for (index, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let code = line.replacingOccurrences(of: #"//.*$"#, with: "", options: .regularExpression)
                for rule in Self.forbidden where code.range(of: rule.pattern, options: .regularExpression) != nil {
                    offenders.append("\(url.lastPathComponent):\(index + 1) \(rule.name)")
                }
            }
        }

        XCTAssertTrue(offenders.isEmpty, """
            Tests must render offscreen through OffscreenRender (windowless host, or OffscreenRender.windowHosting \
            when events are needed). Showing a window or activating the app steals the user's focus: \
            \(offenders.joined(separator: ", "))
            """)
    }

    private static let hostScaleDependent: [(name: String, pattern: String)] = [
        ("bitmapImageRepForCachingDisplay", #"\bbitmapImageRepForCachingDisplay\b"#),
        ("NSScreen", #"\bNSScreen\b"#),
    ]

    func testNoTestRendersAtTheHostScreensScale() throws {
        let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: tests, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        for case let url as URL in enumerator
        where url.pathExtension == "swift" && !Self.allowedFiles.contains(url.lastPathComponent) {
            let source = try String(contentsOf: url, encoding: .utf8)
                .replacingOccurrences(of: #"/\*[\s\S]*?\*/"#, with: "", options: .regularExpression)
            for (index, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let code = line.replacingOccurrences(of: #"//.*$"#, with: "", options: .regularExpression)
                for rule in Self.hostScaleDependent where code.range(of: rule.pattern, options: .regularExpression) != nil {
                    offenders.append("\(url.lastPathComponent):\(index + 1) \(rule.name)")
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty, """
            Pixel tests must render through OffscreenRender.bitmap(of:scale:), which allocates the bitmap at a \
            fixed scale. The main screen's scale makes the same test see 1x on a 1080p display and 2x on a \
            Retina one: \(offenders.joined(separator: ", "))
            """)
    }

    func testTheScaleGuardRejectsTheHostFollowingCalls() {
        for sample in ["host.bitmapImageRepForCachingDisplay(in: host.bounds)", "NSScreen.main?.backingScaleFactor"] {
            XCTAssertTrue(Self.hostScaleDependent.contains { sample.range(of: $0.pattern, options: .regularExpression) != nil },
                          "\(sample) must be rejected")
        }
        XCTAssertFalse(Self.hostScaleDependent.contains {
            "OffscreenRender.bitmap(of: host)".range(of: $0.pattern, options: .regularExpression) != nil
        })
    }

    @MainActor
    func testTheBitmapIsAtTheRequestedScaleWhateverTheDisplayIs() throws {
        let host = OffscreenRender.host(Color.red, size: CGSize(width: 40, height: 10))
        for scale in [CGFloat(1), 2, 3] {
            let bitmap = try OffscreenRender.bitmap(of: host, scale: scale)
            XCTAssertEqual(bitmap.pixelsWide, Int(40 * scale))
            XCTAssertEqual(bitmap.pixelsHigh, Int(10 * scale))
        }
        let defaulted = try OffscreenRender.bitmap(of: host)
        XCTAssertEqual(defaulted.pixelsWide, 80, "the default is 2x on every machine")
    }

    func testTheGuardRejectsEveryForbiddenCall() {
        let samples = ["window.orderFront(nil)", "window.makeKeyAndOrderFront(nil)", "window.makeKey()",
                       "NSApp.activate(ignoringOtherApps: true)", "NSWindow(contentRect: .zero)",
                       "NSWorkspace.shared.open(url)", "window.orderFrontRegardless()", "window.orderBack(nil)"]
        for sample in samples {
            XCTAssertTrue(Self.forbidden.contains { sample.range(of: $0.pattern, options: .regularExpression) != nil },
                          "\(sample) must be rejected")
        }
        XCTAssertFalse(Self.forbidden.contains {
            "OffscreenRender.windowHosting(host)".range(of: $0.pattern, options: .regularExpression) != nil
        })
    }
}
