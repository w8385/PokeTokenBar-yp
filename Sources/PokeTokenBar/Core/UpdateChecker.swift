import AppKit
import Observation

/// Checks the fork's latest GitHub release and installs it in place (`SelfUpdater`).
/// If the install can't run or a check fails, the update button opens the release page instead.
@MainActor
@Observable
final class UpdateChecker {
    struct Available: Equatable {
        let version: String
        let url: String
        /// Asset name → download URL.
        var assets: [String: String] = [:]
    }

    /// What Settings should say after a check. A skipped release is not "up to date".
    enum SettingsNotice: Equatable {
        case offer(String)
        case skipped(String)
        case current
    }

    /// Tag + release-page URL from the GitHub latest endpoint (or a test double).
    struct LatestRelease: Equatable, Sendable {
        let tag: String
        let url: String
        var assets: [String: String] = [:]
    }

    /// Downloads, checks and swaps in a release, asking `readyToQuit` once it is staged. False when it
    /// did not quit, so the caller can fall back.
    typealias Install = @MainActor (Available, _ readyToQuit: @MainActor () -> Bool) async -> Bool

    private(set) var available: Available?
    /// Newer release the user chose to skip. Hidden from the banner, still shown in Settings.
    private(set) var skipped: Available?
    private(set) var isUpdating = false
    var autoUpdateEnabled: Bool {
        didSet { defaults.set(autoUpdateEnabled, forKey: Self.autoUpdateKey) }
    }

    let currentVersion: String
    private let clock: () -> Date
    private let defaults: UserDefaults
    /// Injected so tests can fail or succeed without hitting the network.
    private let fetchLatest: () async -> LatestRelease?
    private let install: Install
    private var lastChecked: Date?
    /// Overlapping popover opens must not stack concurrent GitHub calls once the early
    /// cooldown stamp is gone (a failed check no longer blocks the next attempt).
    private var checkInFlight = false
    /// An automatic install that failed is not retried for the same version; the banner stays.
    private var failedAutoVersion: String?

    static let skippedVersionKey = "skippedUpdateVersion"
    static let autoUpdateKey = "autoUpdateEnabled"
    static let autoAttemptKey = "autoUpdateAttemptedVersion"
    /// Releases come from the fork. Upstream releases would drop the YPoke features.
    nonisolated static let releaseRepo = "w8385/PokeTokenBar-yp"

    init(currentVersion: String? = nil, clock: @escaping () -> Date = Date.init, defaults: UserDefaults = .standard,
         fetchLatest: (() async -> LatestRelease?)? = nil, install: Install? = nil) {
        self.currentVersion = currentVersion
            ?? (Bundle.main.object(forInfoDictionaryKey: "PTBForkVersion") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
        self.clock = clock
        self.defaults = defaults
        self.autoUpdateEnabled = defaults.object(forKey: Self.autoUpdateKey) as? Bool ?? true
        self.fetchLatest = fetchLatest ?? { await Self.liveLatestRelease(repo: Self.releaseRepo) }
        self.install = install ?? Self.liveInstall
    }

    var settingsNotice: SettingsNotice {
        if let available { return .offer(available.version) }
        if let skipped { return .skipped(skipped.version) }
        return .current
    }

    /// Release Settings can install. A skip hides the banner; it does not throw the URL away.
    var updateTarget: Available? { available ?? skipped }

    /// 최신 릴리스 조회. 스킵한 버전은 배너(`available`)에 안 올리고 Settings(`skipped`)에만 남긴다.
    /// minInterval 은 **성공한** 조회 사이에만 적용한다(레이트리밋 보호). 실패 — 네트워크·비정상 응답·
    /// 불안전 URL·지원하지 않는 태그 — 는 쿨다운을 시작하지 않아, 팝오버를 다시 열면 곧장 재시도한다.
    func check(minInterval: TimeInterval = 1800) async {
        if checkInFlight { return }
        if let last = lastChecked, clock().timeIntervalSince(last) < minInterval { return }
        checkInFlight = true
        defer { checkInFlight = false }

        guard let release = await fetchLatest(),
              Self.isTrustedReleaseURL(release.url),
              let version = Self.normalizedReleaseVersion(release.tag) else { return }
        lastChecked = clock()
        consider(latest: version, url: release.url, assets: release.assets)
    }

    /// NSWorkspace.open 으로 가는 릴리스 URL — https + github.com 만 허용(스킴 하이재킹 방지).
    nonisolated static func isTrustedReleaseURL(_ string: String) -> Bool {
        guard let url = URL(string: string), url.scheme == "https", url.host == "github.com" else { return false }
        return true
    }

    /// Release tag → comparable version, or nil when the tag is not `MAJOR.MINOR.PATCH` with an
    /// optional fork suffix `-ypN` (optionally `v`-prefixed). `isNewer` reads non-numeric parts as 0,
    /// so a prerelease such as `v2.6.0-beta.1` would compare equal to `2.6.0` and garbage would
    /// compare as `0.0.0`; neither may be applied or counted as a successful check.
    nonisolated static func normalizedReleaseVersion(_ tag: String) -> String? {
        var version = Substring(tag.trimmingCharacters(in: .whitespacesAndNewlines))
        if version.first == "v" || version.first == "V" { version = version.dropFirst() }
        let halves = version.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        var fork: Int?
        if halves.count == 2 {
            guard halves[1].hasPrefix("yp"), let number = plainNumber(halves[1].dropFirst(2)) else { return nil }
            fork = number
        }
        let fields = halves[0].split(separator: ".", omittingEmptySubsequences: false)
        let parts = fields.compactMap(plainNumber)
        guard fields.count == 3, parts.count == 3 else { return nil }
        let base = parts.map(String.init).joined(separator: ".")
        return fork.map { "\(base)-yp\($0)" } ?? base
    }

    private nonisolated static func plainNumber(_ part: Substring) -> Int? {
        guard !part.isEmpty, part.count <= 9, part.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(part)
    }

    /// Live GitHub latest-release fetch. nil on any transport or payload failure.
    private nonisolated static func liveLatestRelease(repo: String) async -> LatestRelease? {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let html = json["html_url"] as? String else { return nil }
        var assets: [String: String] = [:]
        for asset in json["assets"] as? [[String: Any]] ?? [] {
            if let name = asset["name"] as? String, let link = asset["browser_download_url"] as? String {
                assets[name] = link
            }
        }
        return LatestRelease(tag: tag, url: html, assets: assets)
    }

    /// Apply one fetched release. `latest` may be a tag (`v2.5.4`) or a bare version.
    func consider(latest tag: String, url: String, assets: [String: String] = [:]) {
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let skippedVersion = defaults.string(forKey: Self.skippedVersionKey)
        guard Self.isNewer(latest, than: currentVersion) else {
            available = nil
            skipped = nil
            return
        }
        let release = Available(version: latest, url: url, assets: assets)
        if latest == skippedVersion {
            available = nil
            skipped = release
        } else {
            available = release
            skipped = nil
        }
    }

    /// Hide the banner for this version. Settings can still see it and install it.
    func skipCurrent() {
        guard let release = available else { return }
        defaults.set(release.version, forKey: Self.skippedVersionKey)
        skipped = release
        available = nil
    }

    /// Undo a skip so the banner can show the same release again.
    func showSkippedAgain() {
        defaults.removeObject(forKey: Self.skippedVersionKey)
        if let release = skipped {
            available = release
            skipped = nil
        }
    }

    /// The update button: install in place, or open the release page when that is not possible.
    func applyUpdate() {
        guard let update = updateTarget, !isUpdating else { return }
        isUpdating = true
        Task { @MainActor in
            if await install(update, { true }) { return }
            isUpdating = false
            if Self.isTrustedReleaseURL(update.url), let page = URL(string: update.url) {
                NSWorkspace.shared.open(page)
            }
        }
    }

    /// Installs the bannered release without asking. A skipped version is left alone, and each
    /// version gets one automatic attempt, kept across relaunches so a swap that keeps failing
    /// can't turn into a quit-and-reopen loop.
    func autoInstall(canInstall: @escaping @MainActor () -> Bool) async {
        guard autoUpdateEnabled, canInstall(), !isUpdating, let update = available,
              update.version != failedAutoVersion,
              defaults.string(forKey: Self.autoAttemptKey) != update.version else { return }
        isUpdating = true
        var deferred = false
        let quitting = await install(update) {
            guard canInstall() else { deferred = true; return false }
            self.defaults.set(update.version, forKey: Self.autoAttemptKey)
            return true
        }
        if quitting { return }
        isUpdating = false
        if !deferred { failedAutoVersion = update.version }
    }

    private static func liveInstall(_ release: Available, readyToQuit: @MainActor () -> Bool) async -> Bool {
        guard AppEnv.isBundledApp, let bundleID = Bundle.main.bundleIdentifier else { return false }
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PokeTokenBar-update-\(UUID().uuidString)")
        do {
            let app = try await SelfUpdater.stage(assets: release.assets, version: release.version,
                                                  bundleID: bundleID, workDir: workDir)
            if readyToQuit(), SelfUpdater.launchReplace(staged: app, workDir: workDir) {
                NSApp.terminate(nil)
                return true
            }
        } catch {
            AppLog.write("update: self-install of \(release.version) failed: \(error)")
        }
        try? FileManager.default.removeItem(at: workDir)
        return false
    }

    // MARK: 버전 비교

    /// a 가 b 보다 높은 semver 인가. ("2.0.10" > "2.0.9" 등 숫자 비교)
    /// Same base: the higher `-ypN` wins, and no suffix counts as yp0.
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let (pa, forkA) = versionParts(a)
        let (pb, forkB) = versionParts(b)
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return forkA > forkB
    }

    private nonisolated static func versionParts(_ version: String) -> ([Int], Int) {
        let halves = version.components(separatedBy: "-yp")
        let numbers = halves[0].split(separator: ".").map { Int($0) ?? 0 }
        return (numbers, halves.count > 1 ? Int(halves[1]) ?? 0 : 0)
    }
}
