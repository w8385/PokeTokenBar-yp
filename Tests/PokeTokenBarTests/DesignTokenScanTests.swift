import XCTest
@testable import PokeTokenBar

/// UI code takes colors, type sizes and corner radii from `UI/Design`. A raw `Color(red:`, a numeric
/// `.font(.system(size:` or a numeric `cornerRadius:` anywhere else in Sources fails this test.
/// Computed values (`size * 0.8`, `Radius.card * scale`) are fine: the rules only match a digit.
final class DesignTokenScanTests: XCTestCase {
    private static let rules: [(name: String, pattern: String, token: String)] = [
        ("raw color", #"Color\((\.[A-Za-z]+,\s*)?red:\s*[0-9]"#, "Palette"),
        ("numeric font size", #"\.system\(size:\s*[0-9]"#, "FontSize and Font.ptb"),
        ("numeric corner radius", #"(cornerRadius:|\.cornerRadius\()\s*[0-9]"#, "Radius"),
    ]

    /// File name -> rules it may break. The token definitions themselves.
    private static let allowed: [String: Set<String>] = [
        "Palette.swift": ["raw color"],
    ]

    func testUIHoldsNoRawColorFontSizeOrCornerRadius() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeTokenBar")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for hit in Self.violations(in: text) where !(Self.allowed[url.lastPathComponent]?.contains(hit.rule) ?? false) {
                offenders.append("\(url.lastPathComponent):\(hit.line) \(hit.rule)")
            }
        }
        XCTAssertTrue(offenders.isEmpty, """
            Use the design tokens in UI/Design (see docs/reference/design-system.md):
            \(offenders.joined(separator: "\n"))
            """)
    }

    func testScannerFlagsEachRuleAndSkipsComputedValuesAndComments() {
        let source = """
            .foregroundStyle(Color(red: 0.2, green: 0.3, blue: 0.4))
            .font(.system(size: 11, weight: .bold))
            RoundedRectangle(cornerRadius: 8)
            .font(.system(size: size * 0.8))
            RoundedRectangle(cornerRadius: Radius.card)
            Color(red: sky.red, green: sky.green, blue: sky.blue)
            // Color(red: 1, green: 0, blue: 0)
            Color(.sRGB, red: 0.1, green: 0.2, blue: 0.3)
            .cornerRadius(6)
            """
        XCTAssertEqual(Self.violations(in: source).map { "\($0.line) \($0.rule)" },
                       ["1 raw color", "2 numeric font size", "3 numeric corner radius", "8 raw color",
                        "9 numeric corner radius"])
    }

    func testAllowlistNamesFilesThatStillExist() throws {
        let design = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeTokenBar/UI/Design")
        for name in Self.allowed.keys {
            XCTAssertTrue(FileManager.default.fileExists(atPath: design.appendingPathComponent(name).path),
                          "\(name) is allowlisted but is not in UI/Design")
        }
    }

    private static func violations(in text: String) -> [(line: Int, rule: String)] {
        var hits: [(line: Int, rule: String)] = []
        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
            for rule in rules where line.range(of: rule.pattern, options: .regularExpression) != nil {
                hits.append((index + 1, rule.name))
            }
        }
        return hits
    }
}
