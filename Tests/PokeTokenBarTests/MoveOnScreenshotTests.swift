import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct MoveOnShotProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 446, tree: EvoNode(speciesID: 446, children: [EvoNode(speciesID: 143, children: [])]),
                rarity: .common, names: [446: try SpeciesFacts.names(446), 143: try SpeciesFacts.names(143)])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

private final class MoveOnShotClock: @unchecked Sendable {
    var now = Calendar.current.date(bySettingHour: 12, minute: 1, second: 0, of: Date())!
}

/// Opt-in captures for the PR from sample data (a Munchlax at full XP that waits for pets): the Home countdown line,
/// the Settings toggle, and an illustration of the notice it posts.
///
///     PTB_MOVEON_SHOT_DIR=/tmp/shots swift test --filter MoveOnScreenshotTests
@MainActor
final class MoveOnScreenshotTests: XCTestCase {
    func testCaptureHomeLineSettingsToggleAndNotice() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_MOVEON_SHOT_DIR"] else {
            throw XCTSkip("Set PTB_MOVEON_SHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("moveon-shot-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let suite = "moveon-shot-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let usage = UsageStore(providers: [], autoRefresh: false, defaults: defaults)
        let sprites = SpriteStore(directory: scratch.appendingPathComponent("sprites"))
        for id in [446, 143] {
            for shiny in [false, true] {
                for female in [false, true] {
                    _ = await SpriteLoader.image(speciesID: id, shiny: shiny, store: sprites, female: female)
                    _ = await SpriteLoader.animationFrames(speciesID: id, shiny: shiny, store: sprites, female: female)
                }
            }
        }

        for language in [AppLanguage.ko, .en] {
            let clock = MoveOnShotClock()
            let store = try await stuckStore(language: language, clock: clock, scratch: scratch, defaults: defaults)
            store.checkEvolutionGate()
            clock.now.addTimeInterval(10 * 60)
            XCTAssertEqual(store.moveOnStatus?.minutes, 20)
            let lang = language.rawValue
            let headerSize = NSSize(width: PopoverMetrics.contentWidth + 28, height: 200)
            for (autoMoveOn, name) in [(false, "move-on-home-before"), (true, "move-on-home")] {
                store.autoMoveOn = autoMoveOn
                try await OffscreenRender.capture(
                    CompanionHeader(store: store, spriteStore: sprites).padding(14)
                        .environment(store).environment(usage)
                        .frame(width: headerSize.width, height: headerSize.height, alignment: .top)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .environment(\.colorScheme, .light)
                        .environment(\.locale, language.displayLocale),
                    size: headerSize, appearance: .aqua, scale: 2,
                    to: directory.appendingPathComponent("\(name)-\(lang).png"))
            }

            let uploader = PartyUploader(
                tokenStore: PartyTokenStore(fileURL: scratch.appendingPathComponent("token-\(lang)")), defaults: defaults,
                appVersion: "shot", exchange: { _ in (Data(), 200) }, fetch: { _ in (Data(), 404) },
                partySource: { [] })
            let settingsSize = NSSize(width: PopoverMetrics.width, height: 560)
            try await OffscreenRender.capture(
                SettingsView(onClose: {}, onChooseRepresentative: {}, tab: .constant(.general))
                    .environment(usage).environment(store).environment(UpdateChecker()).environment(uploader)
                    .frame(width: settingsSize.width, height: settingsSize.height)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, .light)
                    .environment(\.locale, language.displayLocale),
                size: settingsSize, appearance: .aqua, scale: 2,
                to: directory.appendingPathComponent("move-on-settings-\(lang).png"))

            let status = try XCTUnwrap(store.moveOnStatus)
            let noticeSize = NSSize(width: 380, height: 110)
            try await OffscreenRender.capture(
                NoticeIllustration(title: store.l.moveOnTitle,
                                   message: store.l.moveOnBody(store.displayName, status.needs, .egg, toGraduates: false))
                    .padding(12)
                    .frame(width: noticeSize.width, height: noticeSize.height, alignment: .top)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, .light),
                size: noticeSize, appearance: .aqua, scale: 2,
                to: directory.appendingPathComponent("move-on-notice-\(lang).png"))
        }
    }

    private func stuckStore(language: AppLanguage, clock: MoveOnShotClock, scratch: URL,
                            defaults: UserDefaults) async throws -> CompanionStore {
        var state = CompanionState()
        state.language = language
        state.installBaselineSet = true
        var profile = PokemonProfile.generate(seed: 8, instanceID: "munchlax")
        profile.level = 22
        var mon = MonState(baseID: 446, pathIDs: [446], plannedPathIDs: [446, 143], stageIndex: 0, usedAtStage: 0,
                           rarity: .common, totalForms: 2, profile: profile)
        mon.usedAtStage = PokemonBalance.scaled(mon.phaseThreshold, by: 1.0)
        mon.evolution.pets = 12
        state.active = mon
        let file = scratch.appendingPathComponent("state-\(language.rawValue).json")
        try JSONEncoder().encode(state).write(to: file)
        defaults.set(1.0, forKey: "growthDifficulty")
        defaults.set(true, forKey: PokemonBalance.difficultyMigratedKey)
        let store = CompanionStore(provider: MoveOnShotProvider(), clock: { clock.now }, fileURL: file,
                                   rng: SeededRNG(seed: 3), dittoDisguiseRollingEnabled: false, defaults: defaults)
        store.update(todayTokensByProvider: ["shot": 0], todayDate: "d1", monthTotal: 0, burnTier: .idle,
                     limitWarning: false, hasUsageData: true)
        try await waitUntil("the raised line to load") { store.currentLine != nil }
        return store
    }
}

/// A macOS-style banner drawn for the PR; the real notice is the system notification.
@MainActor
private struct NoticeIllustration: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "app.badge").font(.title2).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("PokeTokenBar").font(.caption).foregroundStyle(.secondary)
                Text(title).font(.callout).bold()
                Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.25)))
    }
}
