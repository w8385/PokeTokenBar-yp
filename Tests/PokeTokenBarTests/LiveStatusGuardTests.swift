import XCTest

/// `UsageStore`'s default status provider fetches the live status pages, so a test store that keeps it renders
/// whatever incident is open that day.
final class LiveStatusGuardTests: XCTestCase {
    func testEveryTestUsageStorePassesAStatusProvider() throws {
        let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: tests, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            offenders += Self.liveStatusCallLines(in: source).map { "\(url.lastPathComponent):\($0)" }
        }
        XCTAssertTrue(offenders.isEmpty, """
            Pass statusProvider: NoProviderStatus() (or a fake), or build the store with UsageStore.offline. \
            The default reads status.claude.com and status.openai.com: \(offenders.joined(separator: ", "))
            """)
    }

    func testTheScanFlagsOnlyStoresWithoutAStatusProvider() {
        let source = #"""
            let a = UsageStore(providers: [], autoRefresh: false,
                               defaults: d)
            let b = UsageStore(providers: [p(1)], statusProvider: NoProviderStatus(), autoRefresh: false)
            // UsageStore(autoRefresh: false)
            /* UsageStore(autoRefresh: false) */
            let c = UsageStore.offline(providers: [], defaults: d)
            let e = UsageStore(label: "UsageStore( \(name("x")) )", statusProvider: s)
            let f = FakeUsageStore(autoRefresh: false)
            let g = UsageStore(label: """
                (
                """, autoRefresh: false)
            """#
        XCTAssertEqual(Self.liveStatusCallLines(in: source), [1, 9])
    }

    /// One-based line numbers of `UsageStore(` calls whose arguments have no `statusProvider:`.
    static func liveStatusCallLines(in source: String) -> [Int] {
        let code = codeOnly(source)
        let name = Array("UsageStore(")
        var lines: [Int] = []
        var line = 1
        for start in code.indices {
            if code[start] == "\n" { line += 1 }
            guard code[start] == "U", code[start...].starts(with: name),
                  start == 0 || !(code[start - 1].isLetter || code[start - 1].isNumber || code[start - 1] == "_")
            else { continue }
            var depth = 1
            var end = start + name.count
            while depth > 0, end < code.count {
                if code[end] == "(" { depth += 1 } else if code[end] == ")" { depth -= 1 }
                end += 1
            }
            if !String(code[start..<end]).contains("statusProvider:") { lines.append(line) }
        }
        return lines
    }

    /// The source with comments and string literals blanked out; newlines stay, so line numbers still match.
    private static func codeOnly(_ source: String) -> [Character] {
        enum Context { case code(parens: Int), string(multiline: Bool, raw: Bool) }
        let s = Array(source)
        var out = s
        var stack: [Context] = [.code(parens: 0)]
        var i = 0
        func blank(_ count: Int) {
            for k in i..<min(i + count, s.count) where out[k] != "\n" { out[k] = " " }
            i += count
        }
        func at(_ text: String) -> Bool {
            var k = i
            for c in text {
                guard k < s.count, s[k] == c else { return false }
                k += 1
            }
            return true
        }

        while i < s.count {
            switch stack[stack.count - 1] {
            case .code(let parens):
                if at("//") {
                    while i < s.count, s[i] != "\n" { blank(1) }
                } else if at("/*") {
                    while i < s.count, !at("*/") { blank(1) }
                    blank(2)
                } else if at("#\"\"\"") || at("\"\"\"") || at("#\"") || at("\"") {
                    let raw = s[i] == "#"
                    let multiline = at(raw ? "#\"\"\"" : "\"\"\"")
                    blank((raw ? 1 : 0) + (multiline ? 3 : 1))
                    stack.append(.string(multiline: multiline, raw: raw))
                } else if stack.count > 1, s[i] == ")", parens == 0 {
                    blank(1)
                    stack.removeLast()
                } else {
                    if stack.count > 1, s[i] == "(" { stack[stack.count - 1] = .code(parens: parens + 1) }
                    if stack.count > 1, s[i] == ")" { stack[stack.count - 1] = .code(parens: parens - 1) }
                    i += 1
                }
            case .string(let multiline, let raw):
                let close = (multiline ? "\"\"\"" : "\"") + (raw ? "#" : "")
                if !raw, at("\\(") {
                    blank(2)
                    stack.append(.code(parens: 0))
                } else if !raw, s[i] == "\\" {
                    blank(2)
                } else if at(close) {
                    blank(close.count)
                    stack.removeLast()
                } else {
                    blank(1)
                }
            }
        }
        return out
    }
}
