import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct SpeciesClauseShotProvider: PokeProviding, PokemonDetailProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        try SpeciesFacts.details(speciesID)
    }
}

/// Opt-in captures for the PR: a synthetic pre-rule save with three Eternatus, the real views.
///
///     PTB_SPECIES_CLAUSE_SCREENSHOT_DIR=/tmp/shots swift test --filter SpeciesClauseScreenshotTests
@MainActor
final class SpeciesClauseScreenshotTests: XCTestCase {
    private func entry(_ species: Int, id: String, ko: String, level: Int, shiny: Bool = false,
                       form: String? = nil) -> DexEntry {
        var profile = PokemonProfile.generate(seed: UInt64(species), instanceID: id)
        profile.level = level
        var entry = DexEntry(baseID: species, finalID: species, chainOrder: [species], rarity: .legendary,
                             caughtAt: Date(timeIntervalSince1970: 1_700_000_000), isShiny: shiny, profile: profile,
                             names: [species: ["ko": ko, "en": ko]])
        entry.id = id
        entry.form = form.map { PokemonForm($0) }
        return entry
    }

    func testCaptureEntryWithRepeatedSpeciesAndThePicker() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_SPECIES_CLAUSE_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_SPECIES_CLAUSE_SCREENSHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("species-shot-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        var state = CompanionState()
        state.language = .ko
        state.installBaselineSet = true
        state.dex = [entry(890, id: "e1", ko: "무한다이노", level: 60, shiny: true),
                     entry(890, id: "e2", ko: "무한다이노", level: 60),
                     entry(25, id: "pikachu", ko: "피카츄", level: 62),
                     entry(890, id: "e3", ko: "무한다이노", level: 60),
                     entry(479, id: "rotom", ko: "로토무", level: 40),
                     entry(479, id: "wash", ko: "워시로토무", level: 40, form: "wash")]
        state.heldItems = ["e1": ItemKind.blackSludge.rawValue]
        let file = scratch.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: SpeciesClauseShotProvider(), fileURL: file)

        let defaults = UserDefaults(suiteName: "species-shot-\(UUID())")!
        let battle = BattleEntryStore(defaults: defaults)
        ["e1", "e2", "pikachu", "e3", "rotom"].forEach { battle.add($0) }
        let uploader = PartyUploader(
            tokenStore: PartyTokenStore(fileURL: scratch.appendingPathComponent("token")), defaults: defaults,
            appVersion: "shot", send: { _ in 200 }, fetch: { _ in (Data(), 404) }, partySource: { [] })
        uploader.saveToken("synthetic-token")
        uploader.serverURL = "http://bot-host:8790"

        try await capture(VStack(spacing: 0) {
            BattleEntrySection(entry: battle, uploader: uploader, openPicker: { _ in })
        }.environment(uploader).environment(battle).environment(store).environment(PopoverNavigation()),
                          height: 1000, to: directory.appendingPathComponent("entry-species-clause.png"))
        let lineup = BattleEntry.lineup(state: store.state, slots: battle.slots)
        try await capture(BattleFighterPicker(
            store: store, current: nil, excluding: Set(lineup.map(\.id)),
            blocked: BattleEntry.itemBlockedCandidates(state: store.state, slots: battle.slots, replacing: nil),
            sameSpecies: BattleEntry.speciesBlockedCandidates(state: store.state, slots: battle.slots, replacing: nil),
            onPick: { _ in }, onBack: {})
            .environment(store),
                          height: 360, to: directory.appendingPathComponent("picker-species-clause.png"))
    }

    private func capture<V: View>(_ view: V, height: CGFloat, to file: URL) async throws {
        let size = NSSize(width: PopoverMetrics.contentWidth, height: height)
        try await OffscreenRender.capture(view.frame(width: size.width, height: size.height)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .environment(\.locale, AppLanguage.ko.displayLocale),
            size: size, appearance: .aqua, to: file)
    }
}
