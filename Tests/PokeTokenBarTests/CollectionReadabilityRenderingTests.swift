import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct ReadabilityProvider: PokeProviding, PokemonDetailProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        try SpeciesFacts.details(speciesID)
    }
}

/// Opt-in native captures use temporary saves and existing sprite cache, never the user's collection.
@MainActor
final class CollectionReadabilityRenderingTests: XCTestCase {
    func testGenerateCollectionReadabilityEvidence() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_COLLECTION_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_COLLECTION_SCREENSHOT_DIR for native collection layout evidence")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ids = [13, 14, 114, 129, 130, 131, 140, 141, 165, 166, 169, 177, 178, 265, 266, 267, 287, 15]
        let korean = [13: "뿔충이", 14: "딱충이", 15: "독침붕", 114: "덩쿠리", 129: "잉어킹", 130: "갸라도스", 131: "라프라스", 140: "투구", 141: "투구푸스", 165: "레디바", 166: "레디안", 169: "크로뱃", 177: "네이티", 178: "네이티오", 265: "개무소", 266: "실쿤", 267: "뷰티플라이", 287: "게을로"]
        // Long translated names intentionally stress the labels; Korean captures use real names.
        let names = Dictionary(uniqueKeysWithValues: ids.map { id in
            (id, ["en": "Crabominable", "ko": korean[id]!, "ja": "ケケンカニ", "ja-hrkt": "ケケンカニ", "es": "Crabominable", "fr": "Crabominable", "pt": "Crabominable", "pt-br": "Crabominable", "de": "Krawell"])
        })
        let requestedLanguage = ProcessInfo.processInfo.environment["PTB_COLLECTION_SCREENSHOT_LANGUAGE"]
        for language in AppLanguage.allCases where requestedLanguage == nil || language.rawValue == requestedLanguage {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("collection-readability-\(UUID()).json")
            defer { try? FileManager.default.removeItem(at: file) }
            var state = CompanionState()
            state.language = language
            state.dex = ids.enumerated().map { offset, id in
                DexEntry(baseID: id == 15 ? 13 : id, finalID: id, chainOrder: id == 15 ? [13, 14, 15] : [id], rarity: [.common, .uncommon, .rare, .legendary][offset % 4],
                         caughtAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(offset)),
                         nature: .adamant, names: names)
            }
            try JSONEncoder().encode(state).write(to: file)
            let store = CompanionStore(provider: ReadabilityProvider(), fileURL: file)
            let navigation = PopoverNavigation()
            try await capture(CollectionView(store: store, navigation: navigation), language: language,
                              expectedTexts: [.common, .uncommon, .rare, .legendary].map(store.l.rarityLabel),
                              to: directory.appendingPathComponent("\(language.rawValue)-grid.png"))
            try await capture(BoxView(store: store, navigation: navigation), language: language,
                              expectedTexts: [store.l.boxTab],
                              to: directory.appendingPathComponent("\(language.rawValue)-box.png"))
            let species = try XCTUnwrap(store.dexSpecies.first)
            await store.loadPokemonDetails(speciesID: species.id)
            try await capture(PokemonDetailView(store: store, species: species, onBack: {}), language: language,
                              expectedTexts: [store.l.baseStats],
                              to: directory.appendingPathComponent("\(language.rawValue)-detail.png"))
        }
    }

    private func capture<V: View>(_ view: V, language: AppLanguage, expectedTexts: [String], to file: URL) async throws {
        // The screen draws these strings from the store, so a blank one means a missing translation.
        XCTAssertFalse(expectedTexts.contains(where: \.isEmpty), "empty label in \(file.lastPathComponent)")
        let host = OffscreenRender.host(view
            .frame(width: PopoverMetrics.contentWidth, height: 520)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .environment(\.locale, language.displayLocale), size: CGSize(width: PopoverMetrics.contentWidth, height: 520))
        let window = OffscreenRender.windowHosting(host, appearance: .aqua)
        defer { window.close() }
        XCTAssertEqual(host.bounds.width, 332, accuracy: 0.5)
        XCTAssertEqual(host.bounds.height, 520, accuracy: 0.5)
        let first = try await settledBitmap(host)
        try XCTUnwrap(first.representation(using: .png, properties: [:])).write(to: file)
        if file.lastPathComponent == "en-grid.png" {
            try await verifyPagination(host: host, window: window, first: first,
                                       directory: file.deletingLastPathComponent())
        }
    }

    /// Once the tree has settled, renders until two consecutive frames are identical.
    private func settledBitmap(_ host: NSView) async throws -> NSBitmapImageRep {
        try await OffscreenRender.settle(host)
        return try await OffscreenRender.stableBitmap(of: host)
    }

    /// The pager is the only thing these clicks can change: Next shows a different page, Back the first again.
    private func verifyPagination(host: NSView, window: NSWindow, first: NSBitmapImageRep,
                                  directory: URL) async throws {
        var shown = [try XCTUnwrap(first.representation(using: .png, properties: [:]))]
        for (x, name) in [(326.0, "next"), (273.0, "back")] {
            try OffscreenRender.click(at: NSPoint(x: x, y: 9), in: window)
            try await OffscreenRender.waitUntil("pagination \(name) to change the page", in: host) {
                let now = try OffscreenRender.bitmap(of: host).representation(using: .png, properties: [:])
                return name == "back" ? now == shown[0] : now != shown.last
            }
            let bitmap = try await settledBitmap(host)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            XCTAssertNotEqual(png, shown.last, "Pagination \(name) must change the page")
            if name == "back" { XCTAssertEqual(png, shown[0], "Back must return to the first page") }
            shown.append(png)
            try png.write(to: directory.appendingPathComponent("en-grid-\(name).png"))
        }
    }
}
