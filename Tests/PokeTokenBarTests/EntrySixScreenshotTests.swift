import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct EntrySixShotProvider: PokeProviding, PokemonDetailProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        try SpeciesFacts.details(speciesID)
    }
}

/// Opt-in captures for the PR: a synthetic save, the real views.
///
///     PTB_ENTRY6_SCREENSHOT_DIR=/tmp/shots swift test --filter EntrySixScreenshotTests
@MainActor
final class EntrySixScreenshotTests: XCTestCase {
    private func entry(_ species: Int, id: String, ko: String, level: Int) -> DexEntry {
        var profile = PokemonProfile.generate(seed: UInt64(species), instanceID: id)
        profile.level = level
        var entry = DexEntry(baseID: species, finalID: species, chainOrder: [species], rarity: .common,
                             caughtAt: Date(timeIntervalSince1970: 1_700_000_000), isShiny: false, profile: profile,
                             names: [species: ["ko": ko, "en": ko]])
        entry.id = id
        return entry
    }

    func testCaptureSixSlotBattleTabAndBoxControl() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_ENTRY6_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_ENTRY6_SCREENSHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("entry6-shot-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        var state = CompanionState()
        state.language = .ko
        state.installBaselineSet = true
        var raised = PokemonProfile.generate(seed: 5, instanceID: "raised")
        raised.level = 24
        state.active = MonState(baseID: 4, pathIDs: [4, 5, 6], stageIndex: 1, usedAtStage: 0,
                                rarity: .common, totalForms: 3, profile: raised)
        state.dex = [entry(25, id: "pikachu", ko: "피카츄", level: 62), entry(94, id: "gengar", ko: "팬텀", level: 38),
                     entry(6, id: "zard", ko: "리자몽", level: 50), entry(130, id: "gyarados", ko: "갸라도스", level: 44),
                     entry(149, id: "dragonite", ko: "망나뇽", level: 55),
                     entry(5, id: "charmeleon", ko: "리자드", level: 24)]
        let file = scratch.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: EntrySixShotProvider(), fileURL: file)
        try await Task.sleep(for: .seconds(1))

        let defaults = UserDefaults(suiteName: "entry6-shot-\(UUID())")!
        let battle = BattleEntryStore(defaults: defaults)
        ["charmeleon", "pikachu", "gengar", "zard", "gyarados", "dragonite"].forEach { battle.add($0) }
        let uploader = PartyUploader(
            tokenStore: PartyTokenStore(fileURL: scratch.appendingPathComponent("token")), defaults: defaults,
            appVersion: "shot", send: { _ in 200 }, fetch: { _ in (Data(), 404) }, partySource: { [] })
        uploader.saveToken("synthetic-token")
        uploader.serverURL = "http://bot-host:8790"

        try await capture(VStack(spacing: 0) {
            BattleEntrySection(entry: battle, uploader: uploader, openPicker: { _ in })
        }.environment(uploader).environment(battle).environment(store).environment(PopoverNavigation()),
                          height: 1000, to: directory.appendingPathComponent("entry6-battle-tab.png"))
        let zard = try XCTUnwrap(store.state.dex.first { $0.id == "zard" })
        let individual = BoxIndividual(id: "zard", entry: zard, role: .graduated)
        try await capture(BoxDetailView(store: store, individual: individual, navigation: PopoverNavigation(), onBack: {})
            .environment(uploader).environment(battle).environment(store),
                          height: 520, to: directory.appendingPathComponent("entry6-box-slot-control.png"))
    }

    private func capture<V: View>(_ view: V, height: CGFloat, to file: URL) async throws {
        let size = NSSize(width: PopoverMetrics.contentWidth, height: height)
        try await OffscreenRender.capture(view.frame(width: size.width, height: size.height)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .environment(\.locale, AppLanguage.ko.displayLocale),
            size: size, appearance: .aqua, settle: .seconds(3), to: file)
    }
}
