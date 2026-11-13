import XCTest
@testable import PokeTokenBar

final class SelfUpdaterTests: XCTestCase {
    private let bundleID = "io.github.chattymin.poketokenbar"
    private let base = "https://github.com/w8385/PokeTokenBar-yp/releases/download/v2.5.7-yp8/"
    private let cdn = URL(string: "https://release-assets.githubusercontent.com/github-production-release-asset/1")!

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("selfupdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func makeApp(in dir: URL, bundleID: String, version: String, marker: String = "new") throws -> URL {
        let app = dir.appendingPathComponent("PokeTokenBar.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": bundleID, "PTBForkVersion": version]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        try Data(marker.utf8).write(to: contents.appendingPathComponent("marker"))
        return app
    }

    /// A release zip built the way the release command builds it, plus its `.sha256` line.
    private func release(bundleID: String? = nil, version: String = "2.5.7-yp8",
                         checksum: String? = nil) throws -> (zip: URL, sum: URL) {
        let dir = try tempDir()
        let app = try makeApp(in: dir.appendingPathComponent("src"), bundleID: bundleID ?? self.bundleID, version: version)
        let zip = dir.appendingPathComponent(SelfUpdater.assetName)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--keepParent", app.path, zip.path]
        try ditto.run()
        ditto.waitUntilExit()
        let sum = dir.appendingPathComponent(SelfUpdater.checksumName)
        let digest = try checksum ?? SelfUpdater.sha256Hex(of: zip)
        try Data("\(digest)  \(SelfUpdater.assetName)\n".utf8).write(to: sum)
        return (zip, sum)
    }

    private var assets: [String: String] {
        [SelfUpdater.assetName: base + SelfUpdater.assetName, SelfUpdater.checksumName: base + SelfUpdater.checksumName]
    }

    private func download(_ files: (zip: URL, sum: URL), finalURL: URL? = nil) -> SelfUpdater.Download {
        let cdn = finalURL ?? self.cdn
        return { url, destination in
            let source = url.lastPathComponent == SelfUpdater.checksumName ? files.sum : files.zip
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: source, to: destination)
            return cdn
        }
    }

    private func stageError(assets: [String: String]? = nil, version: String = "2.5.7-yp8",
                            download: @escaping SelfUpdater.Download) async throws -> SelfUpdater.Failure? {
        do {
            _ = try await SelfUpdater.stage(assets: assets ?? self.assets, version: version, bundleID: bundleID,
                                            workDir: try tempDir(), download: download)
            return nil
        } catch let failure as SelfUpdater.Failure {
            return failure
        }
    }

    func testTrustsOnlyThisForksReleaseAssets() {
        XCTAssertTrue(SelfUpdater.isTrustedAssetURL(base + SelfUpdater.assetName))
        for bad in [
            "http://github.com/w8385/PokeTokenBar-yp/releases/download/v1/a.zip",
            "https://github.com.evil.example/w8385/PokeTokenBar-yp/releases/download/v1/a.zip",
            "https://github.com/someone/PokeTokenBar-yp/releases/download/v1/a.zip",
            "https://github.com/chattymin/PokeTokenBar/releases/download/v1/a.zip",
            "https://github.com/w8385/PokeTokenBar-yp/archive/refs/tags/v1.zip",
            "https://github.com/w8385/PokeTokenBar-yp/releases/../../other/x.zip",
            "https://user@github.com/w8385/PokeTokenBar-yp/releases/download/v1/a.zip",
            "https://github.com:8443/w8385/PokeTokenBar-yp/releases/download/v1/a.zip",
            "https://github.com/w8385/PokeTokenBar-yp/releases",
        ] {
            XCTAssertFalse(SelfUpdater.isTrustedAssetURL(bad), bad)
        }
        XCTAssertTrue(SelfUpdater.isTrustedDownloadURL(cdn))
        XCTAssertTrue(SelfUpdater.isTrustedDownloadURL(URL(string: "https://objects.githubusercontent.com/x")!))
        XCTAssertFalse(SelfUpdater.isTrustedDownloadURL(URL(string: "https://evil.example/x")!))
        XCTAssertFalse(SelfUpdater.isTrustedDownloadURL(URL(string: "http://objects.githubusercontent.com/x")!))
    }

    func testParsesTheShasumLine() {
        let digest = String(repeating: "aB", count: 32)
        XCTAssertEqual(SelfUpdater.parseChecksum("\(digest)  PokeTokenBar-yp-arm64.zip\n"), digest.lowercased())
        XCTAssertNil(SelfUpdater.parseChecksum(""))
        XCTAssertNil(SelfUpdater.parseChecksum("not-a-digest file"))
        XCTAssertNil(SelfUpdater.parseChecksum(String(repeating: "a", count: 63)))
    }

    func testStagesAVerifiedReleaseApp() async throws {
        let files = try release()
        let app = try await SelfUpdater.stage(assets: assets, version: "2.5.7-yp8", bundleID: bundleID,
                                              workDir: try tempDir(), download: download(files))
        XCTAssertEqual(app.lastPathComponent, "PokeTokenBar.app")
        XCTAssertEqual(try String(contentsOf: app.appendingPathComponent("Contents/marker"), encoding: .utf8), "new")
    }

    func testChecksumMismatchIsRejected() async throws {
        let files = try release(checksum: String(repeating: "0", count: 64))
        let failure = try await stageError(download: download(files))
        XCTAssertEqual(failure, .checksumMismatch)
    }

    func testReleaseWithoutAChecksumIsRejected() async throws {
        let files = try release()
        let failure = try await stageError(assets: [SelfUpdater.assetName: base + SelfUpdater.assetName],
                                           download: download(files))
        XCTAssertEqual(failure, .checksumMissing)
    }

    func testOtherBundleIdentifierIsRejected() async throws {
        let files = try release(bundleID: "com.example.other")
        let failure = try await stageError(download: download(files))
        XCTAssertEqual(failure, .bundleMismatch)
    }

    func testAppVersionMustMatchTheReleaseTag() async throws {
        let files = try release(version: "2.5.7-yp7")
        let failure = try await stageError(download: download(files))
        XCTAssertEqual(failure, .versionMismatch)
    }

    func testRedirectOffGitHubIsRejected() async throws {
        let files = try release()
        let failure = try await stageError(download: download(files, finalURL: URL(string: "https://evil.example/a")!))
        XCTAssertEqual(failure, .untrustedURL)
    }

    func testUntrustedAssetURLIsRejectedBeforeDownloading() async throws {
        for assets in [
            [SelfUpdater.assetName: "https://evil.example/a.zip", SelfUpdater.checksumName: base + "x"],
            [SelfUpdater.assetName: base + "a.zip", SelfUpdater.checksumName: "https://evil.example/a.sha256"],
        ] {
            let failure = try await stageError(assets: assets,
                                               download: { _, _ in XCTFail("must not download"); return nil })
            XCTAssertEqual(failure, .untrustedURL)
        }
    }

    func testZipWithMoreThanTheAppIsRejected() async throws {
        let dir = try tempDir()
        let contents = dir.appendingPathComponent("contents")
        _ = try makeApp(in: contents, bundleID: bundleID, version: "2.5.7-yp8")
        try Data("extra".utf8).write(to: contents.appendingPathComponent("payload"))
        let zip = dir.appendingPathComponent(SelfUpdater.assetName)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", contents.path, zip.path]
        try ditto.run()
        ditto.waitUntilExit()
        let sum = dir.appendingPathComponent(SelfUpdater.checksumName)
        try Data("\(try SelfUpdater.sha256Hex(of: zip))  x\n".utf8).write(to: sum)
        let failure = try await stageError(download: download((zip, sum)))
        XCTAssertEqual(failure, .unzip)
    }

    // MARK: - Replace script

    /// Runs the script with `open` stubbed: it records each path and succeeds only for `openSucceedsFor`.
    private func runReplace(openSucceedsFor marker: String, waitingOn pid: Int32 = .max,
                            waits: String = "40") throws -> (bundle: URL, opened: [String]) {
        let dir = try tempDir()
        let installed = try makeApp(in: dir.appendingPathComponent("Applications dir"), bundleID: bundleID,
                                    version: "2.5.7-yp7", marker: "old")
        let staged = try makeApp(in: dir.appendingPathComponent("work/unzipped"), bundleID: bundleID,
                                 version: "2.5.7-yp8", marker: "new")
        let log = dir.appendingPathComponent("open.log")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            """
            open() { echo "$1" >> "$OPEN_LOG"; grep -q "$OPEN_OK" "$1/Contents/marker"; }
            \(SelfUpdater.replaceScript)
            """,
            "sh", staged.path, installed.path, String(pid), dir.appendingPathComponent("work").path, waits,
        ]
        process.environment = ["OPEN_LOG": log.path, "OPEN_OK": marker, "PATH": "/usr/bin:/bin"]
        try process.run()
        process.waitUntilExit()
        let opened = (try? String(contentsOf: log, encoding: .utf8))?.split(separator: "\n").map(String.init) ?? []
        XCTAssertFalse(FileManager.default.fileExists(atPath: installed.path + ".bak"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("work").path))
        return (installed, opened)
    }

    func testReplaceSwapsTheBundleAndReopensIt() throws {
        let result = try runReplace(openSucceedsFor: "new")
        XCTAssertEqual(try String(contentsOf: result.bundle.appendingPathComponent("Contents/marker"), encoding: .utf8), "new")
        XCTAssertEqual(result.opened, [result.bundle.path])
    }

    func testReplaceLeavesTheBundleAloneWhenTheOldAppNeverQuits() throws {
        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleeper.arguments = ["30"]
        try sleeper.run()
        defer { sleeper.terminate() }
        let result = try runReplace(openSucceedsFor: "new", waitingOn: sleeper.processIdentifier, waits: "1")
        XCTAssertEqual(try String(contentsOf: result.bundle.appendingPathComponent("Contents/marker"), encoding: .utf8), "old")
        XCTAssertEqual(result.opened, [])
    }

    func testReplaceRestoresTheOldAppWhenTheNewOneFailsToOpen() throws {
        let result = try runReplace(openSucceedsFor: "old")
        XCTAssertEqual(try String(contentsOf: result.bundle.appendingPathComponent("Contents/marker"), encoding: .utf8), "old")
        XCTAssertEqual(result.opened, Array(repeating: result.bundle.path, count: 4), "3 tries for the new app, then the old")
    }
}
