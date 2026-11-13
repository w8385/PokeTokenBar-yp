import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct GenderShotProvider: PokeProviding, PokemonDetailProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        PokemonDetails(speciesID: speciesID, name: "synthetic", height: 12, weight: 330,
                       baseExperience: 67, genderRate: 4, types: ["water", "ghost"],
                       baseStats: ["hp": 55, "attack": 40, "defense": 50,
                                   "special-attack": 65, "special-defense": 85, "speed": 40],
                       abilities: [], moves: [])
    }
}

/// Opt-in capture for the PR, synthetic save:
///
///     PTB_GENDER_SCREENSHOT_DIR=/tmp/shots swift test --filter GenderScreenshotTests
@MainActor
final class GenderScreenshotTests: XCTestCase {
    private func entry(id: String, seed: UInt64, gender: PokemonGender) -> DexEntry {
        var profile = PokemonProfile.generate(seed: seed, instanceID: id)
        profile.level = 41
        profile.gender = gender
        var entry = DexEntry(baseID: 592, finalID: 592, chainOrder: [592], rarity: .uncommon,
                             caughtAt: Date(timeIntervalSince1970: 1_700_000_000), nature: .modest, profile: profile,
                             names: [592: ["en": "Frillish"]])
        entry.id = id
        return entry
    }

    func testCaptureFemaleDetailAndCatchLog() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_GENDER_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_GENDER_SCREENSHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("gender-shot-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }

        var state = CompanionState()
        state.language = .en
        state.dex = [entry(id: "frillish-f", seed: 11, gender: .female),
                     entry(id: "frillish-m", seed: 12, gender: .male)]
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: GenderShotProvider(), fileURL: file)
        await store.loadPokemonDetails(speciesID: 592)

        let species = try XCTUnwrap(store.dexSpecies.first { $0.id == 592 })
        try await capture(PokemonDetailView(store: store, species: species, onBack: {}).environment(store),
                          to: directory.appendingPathComponent("gender-detail-female.png"))

        var unsexed = entry(id: "frillish-old", seed: 11, gender: .female)
        unsexed.profile?.gender = nil
        state.dex = [unsexed]
        try JSONEncoder().encode(state).write(to: file)
        let oldStore = CompanionStore(provider: GenderShotProvider(), fileURL: file)
        await oldStore.loadPokemonDetails(speciesID: 592)
        let oldSpecies = try XCTUnwrap(oldStore.dexSpecies.first { $0.id == 592 })
        try await capture(PokemonDetailView(store: oldStore, species: oldSpecies, onBack: {}).environment(oldStore),
                          to: directory.appendingPathComponent("gender-detail-before.png"))
    }

    private func capture<V: View>(_ view: V, to file: URL) async throws {
        let size = NSSize(width: PopoverMetrics.contentWidth, height: 520)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .environment(\.locale, AppLanguage.en.displayLocale))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .seconds(5))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: file)
    }
}
