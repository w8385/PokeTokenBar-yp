import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct SurfaceProvider: PokeProviding, PokemonDetailProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        if baseSpeciesID == 447 {
            return EvoLine(baseID: 447,
                           tree: EvoNode(speciesID: 447, children: [EvoNode(speciesID: 448, children: [])]),
                           rarity: .common,
                           names: [447: ["ko": "리오르", "en": "Riolu"], 448: ["ko": "루카리오", "en": "Lucario"]])
        }
        return EvoLine(baseID: 4,
                       tree: EvoNode(speciesID: 4, children: [EvoNode(speciesID: 5, children: [EvoNode(speciesID: 6, children: [])])]),
                       rarity: .common,
                       names: [4: ["ko": "파이리", "en": "Charmander"], 5: ["ko": "리자드", "en": "Charmeleon"],
                               6: ["ko": "리자몽", "en": "Charizard"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        let lucario = speciesID == 447 || speciesID == 448
        return PokemonDetails(speciesID: speciesID, name: "synthetic", height: 12, weight: 540,
            baseExperience: 184, genderRate: 1, types: lucario ? ["fighting", "steel"] : ["fire", "flying"],
            baseStats: ["hp": 70, "attack": 110, "defense": 70, "special-attack": 115, "special-defense": 70, "speed": 90],
            abilities: [], moves: [])
    }
}

/// A synthetic save for the Mega Stone surfaces: a graduated Lucario (`lucario`) plus a raised Pokémon
/// (`raised`) that is either another Charmander line or a Riolu line.
@MainActor
enum MegaSurfaceFixture {
    static let lucarioZ = MegaStone.stone(slug: "lucarionite-z")!
    static let charizardX = MegaStone.stone(slug: "charizardite-x")!

    static func makeStore(activeIsLucario: Bool, scratch: URL) async throws -> CompanionStore {
        var state = CompanionState()
        state.language = .ko
        state.installBaselineSet = true
        state.usedSinceInstall = 9_000_000_000
        let profile = PokemonProfile.generate(seed: 5, instanceID: "raised")
        if activeIsLucario {
            state.active = MonState(baseID: 447, pathIDs: [447, 448], stageIndex: 1, usedAtStage: 0, rarity: .common,
                                    totalForms: 2, profile: profile)
        } else {
            state.active = MonState(baseID: 4, pathIDs: [4, 5, 6], stageIndex: 2, usedAtStage: 0, rarity: .common,
                                    totalForms: 3, profile: profile)
        }
        var graduate = PokemonProfile.generate(seed: 6, instanceID: "lucario")
        graduate.level = 60
        var lucario = DexEntry(baseID: 447, finalID: 448, chainOrder: [447, 448], rarity: .common,
                               caughtAt: Date(timeIntervalSince1970: 1_700_000_000), profile: graduate,
                               names: [448: ["ko": "루카리오", "en": "Lucario"]])
        lucario.id = "lucario"
        state.dex = [lucario]
        state.inventory = [lucarioZ.inventoryKey: 1, charizardX.inventoryKey: 1]
        let file = scratch.appendingPathComponent("state-\(UUID()).json")
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: SurfaceProvider(), fileURL: file)
        store.update(todayTokensByProvider: ["test": 0], todayDate: "d", monthTotal: 0,
                     burnTier: .idle, limitWarning: false, hasUsageData: true)
        try await Task.sleep(for: .seconds(1))
        await store.loadPokemonDetails(speciesID: 448)
        await store.loadPokemonDetails(speciesID: 6)
        return store
    }
}

/// Opt-in captures for the PR, from the real views over a synthetic Lucario + Lucarionite Z:
///
///     PTB_MEGA_SPRITE_SHOT_DIR=/tmp/shots PTB_MEGA_SPRITE_SHOT_PREFIX=after swift test --filter MegaSpriteScreenshotTests
@MainActor
final class MegaSpriteScreenshotTests: XCTestCase {
    private typealias Opened = (host: NSHostingView<AnyView>, window: NSWindow)

    func testCaptureLucarioZSurfaces() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_MEGA_SPRITE_SHOT_DIR"] else {
            throw XCTSkip("Set PTB_MEGA_SPRITE_SHOT_DIR to write the PR screenshots")
        }
        let lucarioZ = MegaSurfaceFixture.lucarioZ
        let prefix = ProcessInfo.processInfo.environment["PTB_MEGA_SPRITE_SHOT_PREFIX"] ?? "mega-sprite"
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("mega-surface-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        func file(_ name: String) -> URL { directory.appendingPathComponent("\(prefix)-\(name).png") }

        // The reported flow: the Battle tab is open, the raised Pokémon is not the holder, the stone goes on live.
        let store = try await MegaSurfaceFixture.makeStore(activeIsLucario: false, scratch: scratch)
        try await capture(ShopView(store: store, nav: PopoverNavigation(), initialCategory: ItemCategory.megaStone)
            .environment(store), to: file("shop-stone-hint"), height: 420)
        let defaults = UserDefaults(suiteName: "mega-surface-\(UUID())")!
        let battle = BattleEntryStore(defaults: defaults)
        _ = battle.add("raised")
        _ = battle.add("lucario")
        let uploader = PartyUploader(
            tokenStore: PartyTokenStore(fileURL: scratch.appendingPathComponent("token")), defaults: defaults,
            appVersion: "shot", send: { _ in 200 }, fetch: { _ in (Data("{\"moves\":[],\"default\":[]}".utf8), 200) },
            partySource: { [] })
        uploader.saveToken("synthetic-token")
        uploader.serverURL = "http://bot-host:8790"
        let battleHost = open(BattleView(store: store, navigation: PopoverNavigation(), initialPickerQuery: "")
            .environment(uploader).environment(battle).environment(store), height: 520)
        defer { battleHost.window.close() }
        try await Task.sleep(for: .seconds(5))
        XCTAssertTrue(store.equip(lucarioZ, to: "lucario"))
        try await Task.sleep(for: .seconds(6))
        try snapshot(battleHost, to: file("battle-tab"))

        // Holder is not the raised Pokémon: Home keeps showing the raised one, until the holder is a friend.
        try await capture(CompanionHeader(store: store), to: file("home-holder-not-raised"), height: 230)
        XCTAssertTrue(store.addFriend(entryID: "lucario"))
        try await capture(CompanionHeader(store: store), to: file("home-holder-as-friend"), height: 230)

        // The holder is the raised Pokémon: Home, floating pet and menu bar all draw `representativeSubject`.
        let raised = try await MegaSurfaceFixture.makeStore(activeIsLucario: true, scratch: scratch)
        let homeHost = open(CompanionHeader(store: raised), height: 230)
        defer { homeHost.window.close() }
        let petHost = open(PetShot(store: raised), height: 180)
        defer { petHost.window.close() }
        try await Task.sleep(for: .seconds(5))
        XCTAssertTrue(raised.equip(lucarioZ, to: "raised"))
        try await Task.sleep(for: .seconds(6))
        try snapshot(homeHost, to: file("home-holder-raised"))
        try snapshot(petHost, to: file("floating-pet"))
    }

    private struct PetShot: View {
        let store: CompanionStore
        var body: some View {
            let subject = store.representativeSubject
            SpriteView(speciesID: subject.spriteSpeciesID, size: 128, animated: true, shiny: subject.isShiny,
                       form: subject.spriteForm, back: false, female: subject.spriteIsFemale).padding(20)
        }
    }

    private func capture<V: View>(_ view: V, to file: URL, height: CGFloat) async throws {
        let opened = open(view, height: height)
        defer { opened.window.close() }
        try await Task.sleep(for: .seconds(6))
        try snapshot(opened, to: file)
    }

    private func open<V: View>(_ view: V, height: CGFloat) -> Opened {
        let size = NSSize(width: PopoverMetrics.contentWidth, height: height)
        let host = NSHostingView(rootView: AnyView(view.frame(width: size.width, height: size.height)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .environment(\.locale, AppLanguage.ko.displayLocale)))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.orderFront(nil)
        return (host, window)
    }

    private func snapshot(_ opened: Opened, to file: URL) throws {
        let host = opened.host
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: file)
    }
}
