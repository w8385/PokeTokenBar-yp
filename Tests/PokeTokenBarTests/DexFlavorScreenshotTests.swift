import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct SyntheticFlavorProvider: SpeciesFlavorProviding {
    func flavor(speciesID: Int) async -> SpeciesFlavor? {
        switch speciesID {
        case 1:
            SpeciesFlavor(genera: [GenusDTO(genus: "씨앗포켓몬", language: NamedRef(name: "ko", url: nil))],
                          flavorEntries: [FlavorEntryDTO(
                            flavor_text: "태어나서 얼마 동안\n등의 씨앗에 담긴\n영양을 섭취하며 자란다.",
                            language: NamedRef(name: "ko", url: nil))])
        case 2:
            SpeciesFlavor(genera: [GenusDTO(genus: "씨앗포켓몬", language: NamedRef(name: "ko", url: nil))],
                          flavorEntries: [FlavorEntryDTO(
                            flavor_text: "꽃봉오리가 등에 달려 있다.\n영양분을 흡수하면\n꽃이 피어난다.",
                            language: NamedRef(name: "ko", url: nil))])
        default: nil
        }
    }
}

private struct SyntheticDexProvider: PokeProviding, SpeciesIndexProviding, PokemonDetailProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func speciesIndex() async throws -> SpeciesIndex {
        SpeciesIndex(entries: try [1, 2].map { try SpeciesFacts.indexEntry($0) })
    }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        try SpeciesFacts.details(speciesID, abilities: [PokemonAbilityOption(name: "overgrow", slot: 1, isHidden: false)])
    }
}

/// Opt-in captures for the PR: synthetic save, index and flavor text, real views.
///
///     PTB_FLAVOR_SCREENSHOT_DIR=/tmp/shots swift test --filter DexFlavorScreenshotTests
@MainActor
final class DexFlavorScreenshotTests: XCTestCase {
    func testCaptureOwnedAndUnownedDetail() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_FLAVOR_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_FLAVOR_SCREENSHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("flavor-shot-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        var state = CompanionState()
        state.language = .ko
        state.dex = [DexEntry(baseID: 1, finalID: 1, chainOrder: [1], rarity: .common,
                              caughtAt: Date(timeIntervalSince1970: 1_700_000_000),
                              names: [1: ["ko": "이상해씨"]])]
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: SyntheticDexProvider(), fileURL: file)
        await store.loadSpeciesIndexIfNeeded()
        await store.loadPokemonDetails(speciesID: 1)

        let owned = try XCTUnwrap(store.dexSpecies.first { $0.id == 1 })
        try await capture(PokemonDetailView(store: store, species: owned, onBack: {},
                                            flavorProvider: SyntheticFlavorProvider()),
                          to: directory.appendingPathComponent("dexflavor-owned.png"))
        let unowned = try XCTUnwrap(store.unownedDexSpecies.first { $0.id == 2 })
        try await capture(UnownedSpeciesDetailView(store: store, species: unowned, onOpen: { _ in }, onBack: {},
                                                   flavorProvider: SyntheticFlavorProvider()),
                          to: directory.appendingPathComponent("dexflavor-unowned.png"))
    }

    func testCaptureUnownedRouteNode() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_FLAVOR_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_FLAVOR_SCREENSHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("route-shot-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        var state = CompanionState()
        state.language = .ko
        state.dex = [DexEntry(baseID: 1, finalID: 1, chainOrder: [1], rarity: .common,
                              caughtAt: Date(timeIntervalSince1970: 1_700_000_000),
                              names: [1: ["ko": "이상해씨"]])]
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: SyntheticDexProvider(), fileURL: file)
        XCTAssertEqual(store.dexLinkTargets(including: [1, 2])[2], nil, "index not loaded yet")
        await store.loadSpeciesIndexIfNeeded()
        XCTAssertEqual(store.dexLinkTargets(including: [1, 2]), [1: "1", 2: "2"])
        XCTAssertEqual(store.dexLinkTargets(including: [1, 2, 99999])[99999], nil)

        let route = EvoLineView(nodes: [EvoLineItem(.species(1), .current), EvoLineItem(.species(2), .future),
                                        EvoLineItem(.mystery, .future)],
                                mysteryLabel: "?", language: .ko, thumb: 56,
                                names: [1: "이상해씨", 2: "이상해풀"],
                                dexLinks: store.dexLinkTargets(including: [1, 2]), onOpenDexEntry: { _ in })
        let size = NSSize(width: PopoverMetrics.contentWidth, height: 110)
        try await OffscreenRender.capture(route.padding(8).frame(width: size.width, height: size.height)
            .background(Color.white).environment(\.colorScheme, .light),
            size: size, appearance: .aqua,
            to: directory.appendingPathComponent("evo-unowned-route.png"))
        let unowned = try XCTUnwrap(store.unownedDexSpecies.first { $0.id == 2 })
        try await capture(UnownedSpeciesDetailView(store: store, species: unowned, onOpen: { _ in }, onBack: {},
                                                   flavorProvider: SyntheticFlavorProvider()),
                          to: directory.appendingPathComponent("evo-unowned-page.png"))
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
