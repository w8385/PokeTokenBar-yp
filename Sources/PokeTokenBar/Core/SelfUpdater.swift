import CryptoKit
import Foundation

/// Installs a fork release over the running app: download, checksum, unzip, check the bundle,
/// then a detached script swaps the bundle once this process has quit.
enum SelfUpdater {
    static let assetName = "PokeTokenBar-yp-arm64.zip"
    static let checksumName = "PokeTokenBar-yp-arm64.zip.sha256"
    /// GitHub redirects release downloads to one of its asset CDNs.
    static let downloadHosts: Set<String> = [
        "github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com",
    ]

    enum Failure: Error, Equatable {
        case missingAsset, untrustedURL, download, checksumMissing, checksumMismatch, unzip
        case bundleMismatch, versionMismatch
    }

    /// Fetches a URL into a local file. Returns the file and the URL it finally came from.
    typealias Download = @Sendable (URL, URL) async throws -> URL?

    static func isTrustedAssetURL(_ string: String, repo: String = UpdateChecker.releaseRepo) -> Bool {
        guard let url = URL(string: string), url.scheme == "https", url.host == "github.com",
              url.user == nil, url.password == nil, url.port == nil else { return false }
        let parts = url.pathComponents
        let prefix = ["/"] + repo.split(separator: "/").map(String.init) + ["releases"]
        return parts.count > prefix.count && Array(parts.prefix(prefix.count)) == prefix
            && !parts.contains("..") && !parts.contains(".")
    }

    static func isTrustedDownloadURL(_ url: URL) -> Bool {
        url.scheme == "https" && downloadHosts.contains(url.host ?? "")
    }

    /// The hex digest at the start of a `shasum -a 256` line.
    static func parseChecksum(_ text: String) -> String? {
        guard let token = text.split(whereSeparator: \.isWhitespace).first?.lowercased(),
              token.count == 64, token.allSatisfy(\.isHexDigit) else { return nil }
        return token
    }

    static func sha256Hex(of file: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined()
    }

    /// Downloads and checks the release, and returns the unzipped app ready to swap in.
    static func stage(assets: [String: String], version: String, bundleID: String, workDir: URL,
                      download: Download = liveDownload) async throws -> URL {
        guard let zipString = assets[assetName] else { throw Failure.missingAsset }
        guard let sumString = assets[checksumName] else { throw Failure.checksumMissing }
        guard isTrustedAssetURL(zipString), isTrustedAssetURL(sumString),
              let zipURL = URL(string: zipString), let sumURL = URL(string: sumString) else { throw Failure.untrustedURL }
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        let sumFile = workDir.appendingPathComponent(checksumName)
        guard let sumFinal = try? await download(sumURL, sumFile) else { throw Failure.checksumMissing }
        guard isTrustedDownloadURL(sumFinal) else { throw Failure.untrustedURL }
        guard let expected = (try? String(contentsOf: sumFile, encoding: .utf8)).flatMap(parseChecksum) else {
            throw Failure.checksumMissing
        }

        let zipFile = workDir.appendingPathComponent(assetName)
        guard let zipFinal = try? await download(zipURL, zipFile) else { throw Failure.download }
        guard isTrustedDownloadURL(zipFinal) else { throw Failure.untrustedURL }
        guard try sha256Hex(of: zipFile) == expected else { throw Failure.checksumMismatch }

        let unzipped = workDir.appendingPathComponent("unzipped")
        guard run("/usr/bin/ditto", ["-x", "-k", zipFile.path, unzipped.path]),
              let entries = try? FileManager.default.contentsOfDirectory(
                  at: unzipped, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey]),
              entries.count == 1, let app = entries.first, app.pathExtension == "app",
              let kind = try? app.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey]),
              kind.isSymbolicLink == false, kind.isDirectory == true
        else { throw Failure.unzip }
        try validateBundle(at: app, bundleID: bundleID, version: version)
        _ = run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])
        return app
    }

    static func validateBundle(at app: URL, bundleID: String, version: String) throws {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { throw Failure.bundleMismatch }
        guard info["CFBundleIdentifier"] as? String == bundleID else { throw Failure.bundleMismatch }
        guard info["PTBForkVersion"] as? String == version else { throw Failure.versionMismatch }
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config)
    }()

    static let liveDownload: Download = { url, destination in
        let (temp, response) = try await session.download(from: url)
        defer { try? FileManager.default.removeItem(at: temp) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)
        return response.url
    }

    /// Waits for `$3` to quit, keeps the old bundle as `.bak` until the new one opens, and puts it
    /// back if the swap or `open` fails. Positional arguments only, so paths never reach the shell parser.
    /// `open` right after the old process exits can fail with LaunchServices -600, hence the retries.
    /// `$5` is the number of half-second waits for the old process (40 when omitted).
    static let replaceScript = """
    reopen() { for i in 1 2 3; do open "$1" && return 0; sleep 1; done; return 1; }
    for i in $(seq 1 "${5:-40}"); do kill -0 "$3" 2>/dev/null || break; sleep 0.5; done
    if kill -0 "$3" 2>/dev/null; then rm -rf "$4"; exit 1; fi
    rm -rf "$2.bak"
    if ! mv "$2" "$2.bak"; then reopen "$2"; rm -rf "$4"; exit 1; fi
    if ditto "$1" "$2" && reopen "$2"; then
      rm -rf "$2.bak"
    else
      rm -rf "$2"; mv "$2.bak" "$2"; reopen "$2"
    fi
    rm -rf "$4"
    """

    static func launchReplace(staged app: URL, workDir: URL,
                              pid: pid_t = ProcessInfo.processInfo.processIdentifier,
                              bundlePath: String = Bundle.main.bundlePath) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", replaceScript, "sh", app.path, bundlePath, String(pid), workDir.path]
        return (try? task.run()) != nil
    }

    private static func run(_ binary: String, _ args: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
