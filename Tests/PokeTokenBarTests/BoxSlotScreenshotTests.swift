import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct ShotProvider: PokeProviding, PokemonDetailProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        try SpeciesFacts.details(speciesID)
    }
}

/// Opt-in captures for the PR: a synthetic save, the real views.
///
///     PTB_BOXSLOT_SCREENSHOT_DIR=/tmp/shots swift test --filter BoxSlotScreenshotTests
@MainActor
final class BoxSlotScreenshotTests: XCTestCase {
    private func entry(_ species: Int, id: String, ko: String, level: Int) -> DexEntry {
        var profile = PokemonProfile.generate(seed: UInt64(species), instanceID: id)
        profile.level = level
        var entry = DexEntry(baseID: species, finalID: species, chainOrder: [species], rarity: .common,
                             caughtAt: Date(timeIntervalSince1970: 1_700_000_000), isShiny: false, profile: profile,
                             names: [species: ["ko": ko, "en": ko]])
        entry.id = id
        return entry
    }

    func testCaptureBoxDetailSlotControlAndBattleTab() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_BOXSLOT_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_BOXSLOT_SCREENSHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("boxslot-shot-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        var state = CompanionState()
        state.language = .ko
        var raised = PokemonProfile.generate(seed: 5, instanceID: "raised")
        raised.level = 24
        state.active = MonState(baseID: 4, pathIDs: [4, 5, 6], stageIndex: 1, usedAtStage: 0,
                                rarity: .common, totalForms: 3, profile: raised)
        state.dex = [entry(25, id: "pikachu", ko: "피카츄", level: 62), entry(94, id: "gengar", ko: "팬텀", level: 38),
                     entry(143, id: "snorlax", ko: "잠만보", level: 47)]
        let file = scratch.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: ShotProvider(), fileURL: file)

        let defaults = UserDefaults(suiteName: "boxslot-shot-\(UUID())")!
        let battle = BattleEntryStore(defaults: defaults)
        let uploader = PartyUploader(
            tokenStore: PartyTokenStore(fileURL: scratch.appendingPathComponent("token")), defaults: defaults,
            appVersion: "shot", send: { _ in 200 }, fetch: { _ in (Data(), 404) }, partySource: { [] })
        uploader.saveToken("synthetic-token")
        uploader.serverURL = "http://bot-host:8790"

        let pikachu = try XCTUnwrap(store.state.dex.first { $0.id == "pikachu" })
        let individual = BoxIndividual(id: "pikachu", entry: pikachu, role: .graduated)
        func detail() -> some View {
            BoxDetailView(store: store, individual: individual, navigation: PopoverNavigation(), onBack: {})
                .environment(uploader).environment(battle).environment(store)
        }
        try await capture(detail(), to: directory.appendingPathComponent("box-slot-empty.png"))
        battle.add("raised")
        battle.add("snorlax")
        try await capture(detail(), to: directory.appendingPathComponent("box-slot-partly-filled.png"))
        XCTAssertTrue(battle.place(pikachu, at: 1, in: store))
        battle.add("gengar")
        try await capture(detail(), to: directory.appendingPathComponent("box-slot-in-slot-2.png"))
        XCTAssertTrue(battle.place(pikachu, at: 0, in: store))
        try await capture(BattleView(store: store, navigation: PopoverNavigation())
            .environment(uploader).environment(battle).environment(store),
                          to: directory.appendingPathComponent("box-slot-battle-tab-after-swap.png"))
    }

    private func capture<V: View>(_ view: V, to file: URL) async throws {
        let size = NSSize(width: PopoverMetrics.contentWidth, height: 520)
        try await OffscreenRender.capture(view.frame(width: size.width, height: size.height)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .environment(\.locale, AppLanguage.ko.displayLocale),
            size: size, appearance: .aqua, to: file)
    }
}
