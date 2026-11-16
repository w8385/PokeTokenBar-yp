import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct HeaderShotProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 4, tree: EvoNode(speciesID: 4, children: [
            EvoNode(speciesID: 5, children: [EvoNode(speciesID: 6, children: [])])]),
                rarity: .common,
                names: [4: ["en": "Charmander", "ko": "파이리", "ja": "ヒトカゲ", "de": "Glumanda"],
                        5: ["en": "Charmeleon", "ko": "리자드", "ja": "リザード", "de": "Glutexo"],
                        6: ["en": "Charizard", "ko": "리자몽", "ja": "リザードン", "de": "Glurak"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// Opt-in offscreen captures of the Home header across languages, schemes, friend counts and day/night.
///
///     PTB_HEADER_SHOT_DIR=/tmp/shots PTB_HEADER_SHOT_PREFIX=home-header-v2-after swift test --filter HomeHeaderScreenshotTests
@MainActor
final class HomeHeaderScreenshotTests: XCTestCase {
    private func entry(_ species: Int, id: String, en: String) -> DexEntry {
        var entry = DexEntry(baseID: species, finalID: species, chainOrder: [species], rarity: .common,
                             caughtAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(species)),
                             isShiny: false, names: [species: ["en": en]])
        entry.id = id
        return entry
    }

    private func makeStore(language: AppLanguage, minute: Int, friends: Int, scratch: URL,
                           defaults: UserDefaults) async throws -> CompanionStore {
        var state = CompanionState()
        state.language = language
        state.installBaselineSet = true
        var raised = PokemonProfile.generate(seed: 5, instanceID: "raised")
        raised.level = 24
        state.active = MonState(baseID: 4, pathIDs: [4, 5, 6], plannedPathIDs: [4, 5, 6], stageIndex: 1,
                                usedAtStage: 20_000_000, rarity: .common, totalForms: 3, profile: raised)
        state.active?.nature = PokemonNature.allCases[3]
        state.active?.hasGrowthBoost = true
        state.dex = [entry(25, id: "pikachu", en: "Pikachu"), entry(6, id: "charizard", en: "Charizard"),
                     entry(94, id: "gengar", en: "Gengar")]
        let file = scratch.appendingPathComponent("state-\(UUID()).json")
        try JSONEncoder().encode(state).write(to: file)
        let now = Calendar.current.date(bySettingHour: 12, minute: minute, second: 0, of: Date())!
        let store = CompanionStore(provider: HeaderShotProvider(), clock: { now }, fileURL: file,
                                   rng: SeededRNG(seed: 3), defaults: defaults)
        if friends >= 1 { XCTAssertTrue(store.addFriend(entryID: "pikachu")) }
        if friends >= 2 { XCTAssertTrue(store.addFriend(entryID: "charizard")) }
        store.update(todayTokensByProvider: ["shot": 0], todayDate: "d1", monthTotal: 0, burnTier: .idle,
                     limitWarning: false, hasUsageData: true)
        for _ in 0..<200 where store.currentLine == nil { await Task.yield() }
        return store
    }

    func testCaptureHomeHeader() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_HEADER_SHOT_DIR"] else {
            throw XCTSkip("Set PTB_HEADER_SHOT_DIR to write the PR screenshots")
        }
        let prefix = ProcessInfo.processInfo.environment["PTB_HEADER_SHOT_PREFIX"] ?? "home-header-v2-after"
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("header-shot-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let suite = "header-shot-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let usage = UsageStore(providers: [], autoRefresh: false, defaults: defaults)
        let sprites = SpriteStore(directory: scratch.appendingPathComponent("sprites"))

        for language in AppLanguage.allCases {
            let store = try await makeStore(language: language, minute: 3, friends: 2, scratch: scratch, defaults: defaults)
            try await capture(store, usage: usage, sprites: sprites, dark: false,
                              to: directory.appendingPathComponent("\(prefix)-lang-\(language.rawValue).png"))
        }
        for friends in 0...2 {
            for (period, minute) in [("day", 3), ("night", 12)] {
                let store = try await makeStore(language: .en, minute: minute, friends: friends, scratch: scratch,
                                          defaults: defaults)
                for dark in [false, true] {
                    try await capture(store, usage: usage, sprites: sprites, dark: dark,
                                      to: directory.appendingPathComponent(
                                        "\(prefix)-friends\(friends)-\(dark ? "dark" : "light")-\(period).png"))
                }
            }
        }
    }

    private func capture(_ store: CompanionStore, usage: UsageStore, sprites: SpriteStore, dark: Bool,
                         to file: URL) async throws {
        let size = NSSize(width: PopoverMetrics.contentWidth + 28, height: 170)
        try await OffscreenRender.capture(
            CompanionHeader(store: store, spriteStore: sprites).padding(14)
                .environment(store).environment(usage)
                .frame(width: size.width, height: size.height, alignment: .top)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, dark ? .dark : .light)
                .environment(\.locale, store.language.displayLocale),
            size: size, appearance: dark ? .darkAqua : .aqua, scale: 2, settle: .seconds(3), to: file)
    }
}
