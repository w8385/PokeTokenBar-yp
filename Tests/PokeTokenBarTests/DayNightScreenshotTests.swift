import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct DayNightShotProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 433, tree: EvoNode(speciesID: 433, children: []), rarity: .common, names: [:])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// Opt-in captures for the PR: the evolution card of a night-only step, synthetic data.
///
///     PTB_DAYNIGHT_SHOT_DIR=/tmp/shots swift test --filter DayNightScreenshotTests
@MainActor
final class DayNightScreenshotTests: XCTestCase {
    func testCaptureNightConditionByDayAndAtNight() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_DAYNIGHT_SHOT_DIR"] else {
            throw XCTSkip("Set PTB_DAYNIGHT_SHOT_DIR to write the PR screenshots")
        }
        let suffix = ProcessInfo.processInfo.environment["PTB_DAYNIGHT_SHOT_SUFFIX"] ?? "after"
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("daynight-shot-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        var state = CompanionState()
        state.language = .ko
        let file = scratch.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)

        let rule = try XCTUnwrap(EvolutionRules.rule(for: 358))
        for (name, minute, period) in [("day", 3, DayPeriod.day), ("night", 12, DayPeriod.night)] {
            let now = Calendar.current.date(bySettingHour: 12, minute: minute, second: 0, of: Date())!
            let store = CompanionStore(provider: DayNightShotProvider(), clock: { now }, fileURL: file)
            var context = EvolutionContext()
            context.period = period
            context.progress.pets = 40
            let card = CompanionStore.EvolutionCard(rule: rule, context: context, isNextStep: true)
            let size = NSSize(width: PopoverMetrics.contentWidth, height: 190)
            try await OffscreenRender.capture(
                EvolutionCardView(store: store, card: card).padding(12)
                    .frame(width: size.width, height: size.height, alignment: .top)
                    .background(Color.white)
                    .environment(\.colorScheme, .light)
                    .environment(\.locale, AppLanguage.ko.displayLocale),
                size: size, appearance: .aqua, settle: .seconds(1),
                to: directory.appendingPathComponent("day-night-\(name)-\(suffix).png"))
        }
    }
}
