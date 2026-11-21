import XCTest

/// `CompanionState.spentTokens` is written only by `CompanionStore.spend` and `refund`, so every purchase checks the
/// balance in one place.
final class WalletLedgerScanTests: XCTestCase {
    private static let allowed: [String: [String]] = [
        "CompanionStore+Wallet.swift": ["state.spentTokens += cost", "state.spentTokens = max(0, state.spentTokens - cost)"],
        "CompanionModel.swift": ["spentTokens        = c.lenient(Int.self, forKey: .spentTokens, default: 0)"],
        "SaveTransfer.swift": ["s.spentTokens = clampToken(s.spentTokens)"],
        "CompanionStore+Evolution.swift": ["context.spentTokens = state.spentTokens"],
        "CompanionStore+ExpShare.swift": ["context.spentTokens = stored.spentAtStore"],
    ]

    func testSpentTokensIsWrittenOnlyBySpendAndRefund() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/PokeTokenBar")
        let write = try NSRegularExpression(
            pattern: #"(?<!\bvar |\blet )\bspentTokens\s*[-+*/]?=(?!=)|&[\w.!?]*\bspentTokens\b"#)
        var found: [String: [String]] = [:]
        let files = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        for case let url as URL in files where url.pathExtension == "swift" {
            for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") {
                let text = String(line)
                guard write.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil else { continue }
                found[url.lastPathComponent, default: []].append(text.trimmingCharacters(in: .whitespaces))
            }
        }
        XCTAssertEqual(found, Self.allowed)
    }
}
