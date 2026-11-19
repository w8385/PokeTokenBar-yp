import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct PrayerRenderProvider: PokeProviding, PokemonDetailProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        try SpeciesFacts.details(speciesID)
    }
}

/// Writes PNGs of the prayer UI when `PTB_PRAYER_RENDER_DIR` names an existing folder; skipped otherwise.
/// Sample data only: sprites come from an empty directory, so no network is used.
@MainActor
final class EggPrayerRenderTests: XCTestCase {
    private func store(language: AppLanguage, prayers: PrayerRecord?, egg: Bool) async throws -> CompanionStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("prayer-render-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let suite = "PrayerRender-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        var state = CompanionState()
        state.language = language
        if egg {
            state.eggUsage = 1_000_000
            state.eggPrayers = prayers
        } else {
            state.dex = [DexEntry(id: "fixture", baseID: 46, finalID: 47, chainOrder: [46, 47], rarity: .common,
                                  caughtAt: Date(timeIntervalSince1970: 1_700_000_000),
                                  profile: PokemonProfile.generate(seed: 1, instanceID: "fixture"),
                                  names: [47: ["en": "Parasect", "ko": "파라섹트"]], prayers: prayers)]
        }
        let file = directory.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: PrayerRenderProvider(), fileURL: file, defaults: defaults)
        if !egg { await store.loadPokemonDetails(speciesID: 47) }
        return store
    }

    private func writePNG<V: View>(_ view: V, height: CGFloat, to url: URL, dark: Bool = false) async throws {
        let png = try await OffscreenRender.capture(view.frame(width: PopoverMetrics.contentWidth, height: height)
            .background(dark ? Color(white: 0.16) : Color.white)
            .environment(\.colorScheme, dark ? .dark : .light),
            size: CGSize(width: PopoverMetrics.contentWidth, height: height),
            appearance: dark ? .darkAqua : .aqua, scale: 2, to: url)
        XCTAssertGreaterThan(png.count, 1000)
    }

    func testWritePrayerScreens() async throws {
        guard let directory = ProcessInfo.processInfo.environment["PTB_PRAYER_RENDER_DIR"] else {
            throw XCTSkip("PTB_PRAYER_RENDER_DIR not set")
        }
        let output = URL(fileURLWithPath: directory)
        let prayed = PrayerRecord(count: 37)
        for (language, tag) in [(AppLanguage.ko, "ko"), (.en, "en")] {
            for (record, name) in [(nil, "detail-no-prayers"), (prayed, "detail-37-prayers")] as [(PrayerRecord?, String)] {
                let store = try await store(language: language, prayers: record, egg: false)
                let species = try XCTUnwrap(store.dexSpecies.first { $0.id == 47 })
                let spriteDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("prayer-sprites-\(UUID())")
                try FileManager.default.createDirectory(at: spriteDirectory, withIntermediateDirectories: true)
                addTeardownBlock { try? FileManager.default.removeItem(at: spriteDirectory) }
                let view = PokemonDetailView(store: store, species: species, onBack: {},
                                             spriteStore: SpriteStore(directory: spriteDirectory))
                try await writePNG(view, height: 520, to: output.appendingPathComponent("\(name)-\(tag).png"))
            }
        }
    }

    /// The floating egg right after a prayer: its one 🙏 emote.
    func testWriteFloatingEggWithPrayer() async throws {
        guard let directory = ProcessInfo.processInfo.environment["PTB_PRAYER_RENDER_DIR"] else {
            throw XCTSkip("PTB_PRAYER_RENDER_DIR not set")
        }
        let petSize: CGFloat = 128
        let crowd = PetCrowd(settle: .seconds(120))
        crowd.configure(order: [0], motionAllowed: false, active: true)
        crowd.touched(slot: 0, with: .prayer)
        let egg = SpriteView(speciesID: nil, size: petSize, animated: false, shiny: false, reportsVisibleTop: true)
            .crowdMember(crowd, slot: 0, size: petSize)
            .frame(width: petSize, height: petSize)
        for (dark, tag) in [(false, "light"), (true, "dark")] {
            try await writePNG(egg, height: 200,
                               to: URL(fileURLWithPath: directory).appendingPathComponent("floating-egg-prayer-\(tag).png"),
                               dark: dark)
        }
    }
}
