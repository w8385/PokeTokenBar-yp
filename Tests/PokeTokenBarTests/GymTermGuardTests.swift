import Foundation
import XCTest

/// The gym feature is 체육관 and its trainer is 관장 in Korean; the word 도장 must not reach a UI string.
final class GymTermGuardTests: XCTestCase {
    func testNoKoreanUIStringSaysDojang() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()    // PokeTokenBarTests
            .deletingLastPathComponent()    // Tests
            .deletingLastPathComponent()    // repo root
            .appendingPathComponent("Sources")
        // Built from pieces so this file does not match its own scan.
        let banned = "도" + "장"
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
            for (index, line) in lines.enumerated() where line.contains(banned) {
                offenders.append("\(url.lastPathComponent):\(index + 1)")
            }
        }
        XCTAssertTrue(offenders.isEmpty, "Use 체육관/관장, not the banned word: \(offenders.joined(separator: ", "))")
    }
}
