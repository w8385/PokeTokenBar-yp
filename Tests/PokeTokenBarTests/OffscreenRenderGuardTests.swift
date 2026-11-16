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
