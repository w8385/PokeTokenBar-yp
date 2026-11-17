import XCTest
@testable import PokeTokenBar

final class ReleaseScriptTests: XCTestCase {
    private func script(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scripts/\(name)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testBundleVersionAndForkVersionComeFromOneSemverString() throws {
        let build = try script("build-app.sh")
        XCTAssertTrue(build.contains("<key>CFBundleShortVersionString</key><string>$VERSION</string>"))
        XCTAssertTrue(build.contains("<key>PTBForkVersion</key><string>$VERSION</string>"))
        XCTAssertNotNil(build.range(of: #"(?m)^VERSION="\d+\.\d+\.\d+"$"#, options: .regularExpression))
        XCTAssertFalse(build.contains("-yp"), "the -ypN suffix is retired")
    }

    func testForkReleaseUploadsTheAssetsTheUpdaterDownloads() throws {
        let release = try script("fork-release.sh")
        XCTAssertTrue(release.contains("ASSET=\"\(SelfUpdater.assetName)\""))
        XCTAssertEqual(SelfUpdater.checksumName, SelfUpdater.assetName + ".sha256")
        XCTAssertTrue(release.contains("\"build/$ASSET.sha256\""))
        XCTAssertTrue(release.contains("./scripts/xcode-pin.sh check"))
    }
}
