import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct TeraShotProvider: PokeProviding, PokemonDetailProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        try SpeciesFacts.details(speciesID)
    }
}

/// Opt-in captures of the real views over a synthetic save.
///
///     PTB_TERA_SHOT_DIR=/tmp/shots swift test --filter TeraItemsScreenshotTests
@MainActor
final class TeraItemsScreenshotTests: XCTestCase {
    func testCaptureShopAndBoxDetail() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_TERA_SHOT_DIR"] else {
            throw XCTSkip("Set PTB_TERA_SHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("tera-shot-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        var state = CompanionState()
        state.language = .ko
        state.installBaselineSet = true
        state.usedSinceInstall = 80_000_000_000
        let entries = try [("ogerpon", 1017), ("terapagos", 1024), ("pikachu", 25)].map { id, species in
            var profile = PokemonProfile.generate(seed: UInt64(species), instanceID: id)
            profile.level = 60
            var entry = DexEntry(baseID: species, finalID: species, chainOrder: [species], rarity: .rare,
                                 caughtAt: Date(timeIntervalSince1970: 1_700_000_000), profile: profile,
                                 names: [species: try SpeciesFacts.names(species)])
            entry.id = id
            return entry
        }
        state.dex = entries
        state.heldItems = [
            "ogerpon": ItemKind.wellspringMask.rawValue,
            "terapagos": ItemKind.stellarCrystal.rawValue,
            "pikachu": ItemKind.tealMask.rawValue,
        ]
        let file = scratch.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: TeraShotProvider(), fileURL: file)
        for species in [1017, 1024, 25] { await store.loadPokemonDetails(speciesID: species) }

        let defaults = UserDefaults(suiteName: "tera-shot-\(UUID())")!
        let uploader = PartyUploader(
            tokenStore: PartyTokenStore(fileURL: scratch.appendingPathComponent("token")), defaults: defaults,
            appVersion: "shot", send: { _ in 200 }, fetch: { _ in (Data(), 404) }, partySource: { [] })
        let battle = BattleEntryStore(defaults: defaults)
        let nav = PopoverNavigation()

        try await captureEntryRow(entries: entries, state: state, directory: directory, scratch: scratch)

        var shopState = state
        shopState.heldItems = [:]
        let shopFile = scratch.appendingPathComponent("shop.json")
        try JSONEncoder().encode(shopState).write(to: shopFile)
        let shopStore = CompanionStore(provider: TeraShotProvider(), fileURL: shopFile)
        let shopKinds: [ItemKind] = [.tealMask, .wellspringMask, .hearthflameMask, .cornerstoneMask, .stellarCrystal]
        try await capture(VStack(alignment: .leading, spacing: 10) {
            ForEach(shopKinds, id: \.self) { ShopItemCard(store: shopStore, kind: $0) }
        }.padding(10).environment(shopStore),
                          to: directory.appendingPathComponent("tera-shop-cards.png"), height: 700)
        try await capture(ShopView(store: shopStore, nav: nav, initialCategory: ItemCategory.megaStone).environment(shopStore),
                          to: directory.appendingPathComponent("tera-shop-mega-tab.png"), height: 560)
        for (id, name) in [("ogerpon", "ogerpon-wellspring"), ("terapagos", "terapagos-stellar"), ("pikachu", "wrong-holder")] {
            let entry = try XCTUnwrap(entries.first { $0.id == id })
            let individual = BoxIndividual(id: id, entry: entry, role: .graduated)
            try await capture(BoxDetailView(store: store, individual: individual, navigation: nav, onBack: {})
                .environment(uploader).environment(battle).environment(store),
                              to: directory.appendingPathComponent("tera-box-\(name).png"), height: 700)
        }
    }

    /// A Mega holder ahead of the crystal holder: the Mega takes the once-per-battle slot, so the crystal row says it waits.
    private func captureEntryRow(entries: [DexEntry], state: CompanionState, directory: URL, scratch: URL) async throws {
        var lineupState = state
        var zardProfile = PokemonProfile.generate(seed: 6, instanceID: "zard")
        zardProfile.level = 50
        var zard = DexEntry(baseID: 6, finalID: 6, chainOrder: [6], rarity: .rare,
                            caughtAt: Date(timeIntervalSince1970: 1_700_000_000), profile: zardProfile,
                            names: [6: try SpeciesFacts.names(6)])
        zard.id = "zard"
        lineupState.dex = entries + [zard]
        lineupState.heldItems = [
            "zard": try XCTUnwrap(MegaStone.stone(slug: "charizardite-x")).inventoryKey,
            "terapagos": ItemKind.stellarCrystal.rawValue,
            "ogerpon": ItemKind.hearthflameMask.rawValue,
        ]
        let file = scratch.appendingPathComponent("entry.json")
        try JSONEncoder().encode(lineupState).write(to: file)
        let store = CompanionStore(provider: TeraShotProvider(), fileURL: file)
        for species in [1017, 1024, 6] { await store.loadPokemonDetails(speciesID: species) }
        let defaults = UserDefaults(suiteName: "tera-entry-shot-\(UUID())")!
        let battle = BattleEntryStore(defaults: defaults)
        ["zard", "terapagos", "ogerpon"].forEach { battle.add($0) }
        let uploader = PartyUploader(
            tokenStore: PartyTokenStore(fileURL: scratch.appendingPathComponent("entry-token")), defaults: defaults,
            appVersion: "shot", send: { _ in 200 }, fetch: { _ in (Data(), 404) }, partySource: { [] })
        uploader.saveToken("synthetic-token")
        uploader.serverURL = "http://bot-host:8790"
        try await capture(VStack(spacing: 0) {
            BattleEntrySection(entry: battle, uploader: uploader, openPicker: { _ in })
        }.environment(uploader).environment(battle).environment(store).environment(PopoverNavigation()),
                          to: directory.appendingPathComponent("tera-entry-row.png"), height: 620)
    }

    private func capture<V: View>(_ view: V, to file: URL, height: CGFloat) async throws {
        let size = NSSize(width: PopoverMetrics.contentWidth, height: height)
        try await OffscreenRender.capture(view.frame(width: size.width, height: size.height)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .environment(\.locale, AppLanguage.ko.displayLocale),
            size: size, appearance: .aqua, to: file)
    }
}
