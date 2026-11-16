import XCTest

/// Vision confuses i/l/1/|, o/0 and 이/미 on the CI runner. Compare OCR text through `folded`,
/// and ask for layout (same observation, bounding boxes) instead of an exact string.
enum OCRText {
    static func folded(_ text: String) -> String {
        String(text.lowercased().compactMap { character -> Character? in
            switch character {
            case " ": return nil
            case "i", "l", "1", "|", "!", "ı": return "i"
            case "o", "0": return "o"
            case "미": return "이"
            default: return character
            }
        })
    }

    static func contains(_ text: String, _ wanted: String) -> Bool {
        folded(text).contains(folded(wanted))
    }
}

extension String {
    func ocrContains(_ wanted: String) -> Bool { OCRText.contains(self, wanted) }
}

final class OCRTextTests: XCTestCase {
    func testFoldTreatsLookalikeGlyphsAsEqual() {
        XCTAssertEqual(OCRText.folded("Dleser Monat"), OCRText.folded("Dieser Monat"))
        XCTAssertEqual(OCRText.folded("미번 주"), OCRText.folded("이번 주"))
        XCTAssertNotEqual(OCRText.folded("Diese Woche"), OCRText.folded("Dieser Monat"))
    }

    func testContainsIgnoresCaseAndSpaces() {
        XCTAssertTrue(OCRText.contains("Elgyem  SHINY", "elgyem shiny"))
        XCTAssertFalse(OCRText.contains("Elgyem", "Shiny"))
    }
}
