import XCTest

/// Vision's text recognition reads differently on macOS 15 and 26 (이번→미번, Dieser→Dleser), so a test
/// that asserts on OCR output flakes on CI. Layout comes from `LayoutMeasure`, strings from the
/// store, and sprite or color checks from sampled pixels.
final class NoOCRInTestsGuardTests: XCTestCase {
    func testNoTestReadsRenderedTextWithOCR() throws {
        let tests = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()    // PokeTokenBarTests
            .deletingLastPathComponent()    // Tests
        // Built from pieces so this file does not match its own scan.
        let needles = ["import " + "Vision", "VNRecognize" + "TextRequest", "OCR" + "Text"]
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: tests, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            for needle in needles where source.contains(needle) {
                offenders.append("\(url.lastPathComponent): \(needle)")
            }
        }
        XCTAssertTrue(offenders.isEmpty, """
            Tests must not read rendered text with OCR. Measure layout with LayoutMeasure, assert on the \
            localized string source, or sample pixels instead: \(offenders.joined(separator: ", "))
            """)
    }
}
