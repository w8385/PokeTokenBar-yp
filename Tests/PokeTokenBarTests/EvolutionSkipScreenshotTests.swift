import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct SkipShotProvider: PokeProviding, SpeciesIndexProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 172, tree: EvoNode(speciesID: 172, children: [EvoNode(speciesID: 25, children: [])]),
                rarity: .common, names: [172: try SpeciesFacts.names(172), 25: try SpeciesFacts.names(25)])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func speciesIndex() async throws -> SpeciesIndex {
        SpeciesIndex(entries: [try SpeciesFacts.indexEntry(172), try SpeciesFacts.indexEntry(25)])
    }
}

private final class ShotClock: @unchecked Sendable {
    var now = Calendar.current.date(bySettingHour: 12, minute: 1, second: 0, of: Date())!
}

/// Opt-in captures for the PR: the skip control, its confirmation, and a raised graduate's evolution card.
/// Sample data (a Pichu that waits for pets).
///
///     PTB_EVOSKIP_SHOT_DIR=/tmp/shots swift test --filter EvolutionSkipScreenshotTests
@MainActor
final class EvolutionSkipScreenshotTests: XCTestCase {
    func testCaptureSkipControlConfirmAndGraduateCard() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_EVOSKIP_SHOT_DIR"] else {
            throw XCTSkip("Set PTB_EVOSKIP_SHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for language in [AppLanguage.ko, .en] {
            let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("evoskip-shot-\(UUID())")
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: scratch) }
            var state = CompanionState()
            state.language = language
            state.installBaselineSet = true
            let file = scratch.appendingPathComponent("state.json")
            try JSONEncoder().encode(state).write(to: file)
            let clock = ShotClock()
            let suite = "evoskip-shot-\(UUID())"
            defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
            let store = CompanionStore(provider: SkipShotProvider(), clock: { clock.now }, fileURL: file,
                                       rng: SeededRNG(seed: 1), dittoDisguiseRollingEnabled: false,
                                       defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
            await store.loadSpeciesIndexIfNeeded()
            await store.hatch(baseID: 172)
            for _ in 0..<12 { clock.now.addTimeInterval(11); store.recordPet() }
            store.applyUsage(store.tokensToNext)
            let active = try XCTUnwrap(store.boxIndividuals.first { $0.role == .raising })
            let skipCard = try XCTUnwrap(store.evolutionCards(for: 172, individual: active.entry).first { $0.offersSkip })
            let lang = language.rawValue
            try await capture(EvolutionCardView(store: store, card: skipCard), language: language,
                              to: directory.appendingPathComponent("evolution-skip-control-\(lang).png"))
            try await capture(EvolutionCardView(store: store, card: skipCard, confirmingSkip: true), language: language,
                              to: directory.appendingPathComponent("evolution-skip-confirm-\(lang).png"))

            XCTAssertTrue(store.skipEvolutionAndGraduate())
            XCTAssertTrue(store.raise(entryID: active.id))
            await store.checkRaisedGraduateEvolution()
            for _ in 0..<6 { clock.now.addTimeInterval(11); store.recordPet() }
            let graduate = try XCTUnwrap(store.boxIndividuals.first { $0.role == .raising })
            let graduateCard = try XCTUnwrap(store.evolutionCards(for: 172, individual: graduate.entry)
                .first { $0.isNextStep && $0.context != nil })
            try await capture(EvolutionCardView(store: store, card: graduateCard), language: language,
                              to: directory.appendingPathComponent("evolution-skip-graduate-card-\(lang).png"))
        }
    }

    private func capture(_ view: EvolutionCardView, language: AppLanguage, to file: URL) async throws {
        let size = NSSize(width: PopoverMetrics.contentWidth, height: 260)
        try await OffscreenRender.capture(
            view.padding(12)
                .frame(width: size.width, height: size.height, alignment: .top)
                .background(Color.white)
                .environment(\.colorScheme, .light)
                .environment(\.locale, language.displayLocale),
            size: size, appearance: .aqua, to: file)
    }
}
