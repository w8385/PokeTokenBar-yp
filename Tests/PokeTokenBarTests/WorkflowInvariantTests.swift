import Foundation
import XCTest

final class WorkflowInvariantTests: XCTestCase {
    private static let selfHostedGuard =
        "${{ (github.event_name == 'push' || (github.event_name == 'pull_request' && "
        + "github.event.pull_request.head.repo.full_name == github.repository)) && "
        + "fromJSON('[\"self-hosted\",\"macOS\",\"ptb\"]') || 'xcode-%@' }}"

    private func repositoryFile(_ relative: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relative)
    }

    private func workflowFiles() throws -> [URL] {
        let dir = repositoryFile(".github/workflows")
        return try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { ["yml", "yaml"].contains($0.pathExtension) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func pinnedXcodeMajor() throws -> String {
        let raw = try String(contentsOf: repositoryFile(".xcode-version"), encoding: .utf8)
        return raw.trimmingCharacters(in: .newlines)
    }

    func testXcodeVersionPinsOneMajor() throws {
        let raw = try String(contentsOf: repositoryFile(".xcode-version"), encoding: .utf8)
        XCTAssertNotNil(raw.range(of: #"^[0-9]+\n?$"#, options: .regularExpression),
                        ".xcode-version must hold one Xcode major such as 27, got \(raw.debugDescription)")
    }

    func testOnlyPushesAndSameRepositoryPRsReachTheSelfHostedRunner() throws {
        let guardLine = "runs-on: " + String(format: Self.selfHostedGuard, try pinnedXcodeMajor())
        var guarded = 0
        for file in try workflowFiles() {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let place = "\(file.lastPathComponent):\(index + 1)"
                if trimmed == guardLine {
                    guarded += 1
                    continue
                }
                XCTAssertNil(trimmed.range(of: #"^-\s*["']?self-hosted["']?$"#,
                                           options: [.regularExpression, .caseInsensitive]),
                               "\(place) lists a self-hosted label outside the guarded runs-on")
                if trimmed.hasPrefix("runs-on:") {
                    XCTAssertTrue(["runs-on: ubuntu-latest"].contains(trimmed),
                                  "\(place): runs-on must be ubuntu-latest or the guarded expression")
                }
            }
        }
        XCTAssertGreaterThan(guarded, 0, "no job uses the guarded self-hosted runs-on")
    }

    func testAggregateChecksPassOnlyWhenEveryNeededJobSucceededOrWasSkipped() throws {
        let passing = ["success", "skipped", "success skipped success"]
        let failing = ["failure", "cancelled", "abandoned", "success failure", "skipped cancelled",
                       "success unknown"]
        for (file, job) in [("ci.yml", "ci-ok"), ("bot.yml", "bot-ok")] {
            let script = try runBlock(job: job, in: repositoryFile(".github/workflows/\(file)"))
            for results in passing {
                XCTAssertEqual(try exitCode(script, results: results), 0, "\(job) failed for '\(results)'")
            }
            for results in failing {
                XCTAssertNotEqual(try exitCode(script, results: results), 0, "\(job) passed for '\(results)'")
            }
        }
    }

    private func runBlock(job: String, in file: URL) throws -> String {
        let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
        guard let start = lines.firstIndex(of: "  \(job):") else {
            XCTFail("no job \(job) in \(file.lastPathComponent)")
            return "exit 1"
        }
        let indentOf = { (line: String) in line.prefix { $0 == " " }.count }
        var index = start + 1
        while index < lines.count, lines[index].isEmpty || indentOf(lines[index]) > 2 {
            if lines[index].trimmingCharacters(in: .whitespaces) == "run: |" {
                let indent = indentOf(lines[index])
                let body = lines[(index + 1)...].prefix { $0.isEmpty || indentOf($0) > indent }
                return body.map { String($0.dropFirst(min(indent + 2, $0.count))) }.joined(separator: "\n")
            }
            index += 1
        }
        XCTFail("\(job) in \(file.lastPathComponent) has no `run: |` block")
        return "exit 1"
    }

    private func exitCode(_ script: String, results: String) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-e", "-c", script]
        process.environment = ["RESULTS": results, "PATH": "/usr/bin:/bin"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
