import SwiftUI
import XCTest
@testable import PokeTokenBar

/// Opt-in PR captures of an Urshifu's Box detail from the synthetic `BoxDexFixture` save, once as the old saves left
/// it (no form, so Single Strike) and once as Rapid Strike.
///
///     PTB_URSHIFU_SHOTS=/tmp/shots swift test --filter UrshifuFormScreenshotTests
@MainActor
final class UrshifuFormScreenshotTests: XCTestCase {
    private static let id = "box-urshifu"

    func testCaptureUrshifuDetailWithoutAndWithRapidStrike() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_URSHIFU_SHOTS"] else {
            throw XCTSkip("Set PTB_URSHIFU_SHOTS for the Urshifu form captures")
        }
        let dir = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let suite = "urshifu-shots-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let usage = UsageStore.offline(providers: [], defaults: defaults)
        let updater = UpdateChecker(currentVersion: "3.0.0", defaults: defaults, fetchLatest: { nil })
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("urshifu-shots-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let uploader = await BoxDexFixture.makeUploader(defaults: defaults, scratch: scratch, connected: false)
        let battle = BattleEntryStore(defaults: defaults)
        _ = await SpriteLoader.image(speciesID: 892)
        _ = await SpriteLoader.image(speciesID: 892, form: PokemonForm("rapid-strike"))

        let names = [891: try SpeciesFacts.names(891), 892: try SpeciesFacts.names(892)]
        for (form, name) in [(nil, "before-single-strike"), (PokemonForm("rapid-strike"), "after-rapid-strike")] {
            let (store, cleanup) = try BoxDexFixture.makeStore(language: .ko, mutate: {
                var profile = PokemonProfile.generate(seed: 71, instanceID: Self.id)
                profile.level = 70
                $0.dex.append(DexEntry(id: Self.id, baseID: 891, finalID: 892, chainOrder: [891, 892], rarity: .rare,
                                       caughtAt: Date(timeIntervalSince1970: 1_700_000_900), profile: profile,
                                       names: names, form: form))
            }, defaults: defaults)
            defer { cleanup() }
            await store.loadPokemonDetails(speciesID: 892)
            let nav = PopoverNavigation()
            nav.openBoxDetail(id: Self.id)
            let view = PopoverView(screenHeight: 5000)
                .environment(usage).environment(store).environment(updater).environment(nav)
                .environment(uploader).environment(battle)
                .environment(\.colorScheme, .light)
                .environment(\.controlActiveState, .active)
            let width = PopoverMetrics.width, height: CGFloat = 560
            let host = OffscreenRender.host(
                view.frame(width: width, height: height, alignment: .top)
                    .background(Color(nsColor: .windowBackgroundColor)),
                size: CGSize(width: width, height: height), appearance: .aqua)
            try await OffscreenRender.settle(host)
            try OffscreenRender.writePNG(of: host, to: dir.appendingPathComponent("\(name).png"), scale: 2)
        }
    }
}
