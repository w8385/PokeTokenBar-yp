import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct ShotProvider: PokeProviding, PokemonDetailProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { try await BoxDexProvider().line(baseSpeciesID: baseSpeciesID) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        try SpeciesFacts.details(speciesID, abilities: TrainingAbilities.byID[speciesID]
            ?? [.init(name: "blaze", slot: 1, isHidden: false), .init(name: "solar-power", slot: 3, isHidden: true)])
    }
}

/// PokéAPI names of the abilities and forms on these pages, so the shots do not wait on the network.
private struct ShotNames: PokemonNameProviding {
    static let table: [String: [String: String]] = [
        "rock-head": ["ko": "돌머리", "en": "Rock Head"], "sturdy": ["ko": "옹골참", "en": "Sturdy"],
        "weak-armor": ["ko": "깨어진갑옷", "en": "Weak Armor"], "sand-force": ["ko": "모래의힘", "en": "Sand Force"],
        "sheer-force": ["ko": "우격다짐", "en": "Sheer Force"], "intimidate": ["ko": "위협", "en": "Intimidate"],
        "645": ["ko": "화신폼", "en": "Incarnate Forme"], "10081": ["ko": "영물폼", "en": "Therian Forme"],
    ]
    func names(for resource: PokemonNameResource) async throws -> [String: String] {
        try XCTUnwrap(Self.table[resource.name])
    }
}

/// The Shop, Bag, Box page and Home with the training items, for the PR. Writes only when
/// `PTB_PARITY_SHOT_DIR` is set.
@MainActor
final class PlayerToolShotTests: XCTestCase {
    static let landorusID = "landorus"

    func testCapturePlayerTools() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_PARITY_SHOT_DIR"] else {
            throw XCTSkip("Set PTB_PARITY_SHOT_DIR")
        }
        let dir = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let sprites = ProcessInfo.processInfo.environment["PTB_PARITY_SPRITE_DIR"] {
            for file in try FileManager.default.contentsOfDirectory(atPath: sprites) where file.hasSuffix(".png") {
                let image = try XCTUnwrap(NSImage(contentsOfFile: sprites + "/" + file))
                pinSprite(image, at: SpriteLoader.cacheDir.appendingPathComponent(file).path as NSString)
            }
        }
        for name in ShotNames.table.keys {
            let kind: PokemonNameResource.Kind = Int(name) == nil ? .ability : .pokemonForm
            _ = await PokemonNameDisplayStore.shared.load(.init(kind: kind, name: name), provider: ShotNames())
        }
        for language in [AppLanguage.ko, .en] {
            let suffix = language == .ko ? "-ko" : "-en"
            let store = try await makeStore(language: language)
            let onix = try XCTUnwrap(store.boxIndividual(id: BoxDexFixture.onixID))
            let landorus = try XCTUnwrap(store.boxIndividual(id: Self.landorusID))

            try await capture(ShopView(store: store, nav: PopoverNavigation(), initialCategory: .growth).environment(store),
                              height: 520, to: dir.appendingPathComponent("shop-growth\(suffix).png"))
            let cards = VStack(spacing: 10) {
                ForEach([ItemKind.mint, .abilityCapsule, .abilityPatch, .bottleCap, .goldBottleCap,
                         .revealGlass, .dnaSplicers, .reinsOfUnity], id: \.self) { ShopItemCard(store: store, kind: $0) }
            }
            try await capture(cards.environment(store), height: 1100,
                              to: dir.appendingPathComponent("shop-training-cards\(suffix).png"))
            try await capture(BagView(store: store, nav: PopoverNavigation(), initialCategory: .growth).environment(store),
                              height: 520, to: dir.appendingPathComponent("bag-growth\(suffix).png"))
            try await capture(BoxDetailView(store: store, individual: onix, navigation: PopoverNavigation(), onBack: {})
                .environment(store), height: 1150, to: dir.appendingPathComponent("box-detail\(suffix).png"))
            let pickerNav = PopoverNavigation()
            pickerNav.openBoxDetail(id: BoxDexFixture.onixID, naturePicker: true)
            try await capture(BoxDetailView(store: store, individual: onix, navigation: pickerNav, onBack: {})
                .environment(store), height: 1400, to: dir.appendingPathComponent("box-detail-mint-picker\(suffix).png"))
            try await capture(BoxDetailView(store: store, individual: landorus, navigation: PopoverNavigation(), onBack: {})
                .environment(store), height: 1150, to: dir.appendingPathComponent("box-detail-form\(suffix).png"))
            try await capture(CompanionHeader(store: store, onChangeNature: { _ in }).padding(PopoverMetrics.padding),
                              height: 260, to: dir.appendingPathComponent("home-header\(suffix).png"))
        }
    }

    private func makeStore(language: AppLanguage) async throws -> CompanionStore {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("player-tools-\(UUID()).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        var state = BoxDexFixture.state(language: language)
        state.active?.nature = .adamant
        state.inventory["mint"] = 2
        for kind in [ItemKind.abilityCapsule, .abilityPatch, .bottleCap, .goldBottleCap, .revealGlass] {
            state.inventory[kind.rawValue] = 1
        }
        if let onix = state.dex.firstIndex(where: { $0.id == BoxDexFixture.onixID }) {
            state.dex[onix].nature = .lonely
        }
        var profile = PokemonProfile.generate(seed: 645, instanceID: Self.landorusID)
        profile.level = 70
        state.dex.append(DexEntry(id: Self.landorusID, baseID: 645, finalID: 645, chainOrder: [645], rarity: .legendary,
                                  caughtAt: Date(timeIntervalSince1970: 1_700_000_500), nature: .jolly,
                                  profile: profile, names: [645: ["ko": "랜드로스", "en": "Landorus"]],
                                  form: PokemonForm("therian")))
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: ShotProvider(), fileURL: file)
        for id in [95, 645, 4, 5] { await store.loadPokemonDetails(speciesID: id) }
        await store.loadFormNames(PokemonForm.nameResources(speciesID: 645))
        store.update(todayTokensByProvider: ["test": 0], todayDate: "d1", monthTotal: 0, burnTier: .idle,
                     limitWarning: false, hasUsageData: true)
        try await waitUntil("the raised line to load") { store.currentLine != nil }
        return store
    }

    private func capture<V: View>(_ view: V, height: CGFloat, to file: URL) async throws {
        let size = NSSize(width: PopoverMetrics.contentWidth, height: height)
        try await OffscreenRender.capture(view.frame(width: size.width, height: size.height, alignment: .top)
            .background(Color.white)
            .environment(\.colorScheme, .light),
            size: size, appearance: .aqua, scale: 2, to: file)
    }
}
