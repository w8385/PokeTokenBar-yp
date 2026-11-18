import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct OfflineProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class BattleSubTabsTests: XCTestCase {
    private func defaults() throws -> UserDefaults {
        let suite = "BattleSubTabs-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    private struct Rig {
        let store: CompanionStore
        let entry: BattleEntryStore
        let uploader: PartyUploader
        let nav: PopoverNavigation
        let defaults: UserDefaults
    }

    private func rig(linked: Bool, uploadStatus: Int = 503) throws -> Rig {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("battle-subtabs-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: scratch) }
        var state = CompanionState()
        state.language = .en
        state.installBaselineSet = true
        var profile = PokemonProfile.generate(seed: 25, instanceID: "pikachu")
        profile.level = 30
        var pikachu = DexEntry(baseID: 25, finalID: 25, chainOrder: [25], rarity: .rare,
                               caughtAt: Date(timeIntervalSince1970: 1_700_000_000), isShiny: false, profile: profile,
                               names: [25: ["en": "Pikachu"]])
        pikachu.id = "pikachu"
        state.dex = [pikachu]
        let file = scratch.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: OfflineProvider(), fileURL: file)
        let defaults = try defaults()
        let entry = BattleEntryStore(defaults: defaults)
        entry.add("pikachu")
        let server = "http://bot-subtabs-\(UUID().uuidString.prefix(8).lowercased()):8790"
        let uploader = PartyUploader(
            tokenStore: PartyTokenStore(fileURL: scratch.appendingPathComponent("token")), defaults: defaults,
            appVersion: "test", exchange: { _ in (Data(), uploadStatus) }, fetch: { _ in (Data(), 404) },
            partySource: { [PartyMember(pokemonID: 25, level: 30, shiny: false, ivs: nil)] })
        if linked { uploader.saveToken("synthetic-token") }
        uploader.serverURL = server
        GymSession.shared.setCatalog(GymFixtures.catalog(), for: server)
        addTeardownBlock { @MainActor in GymSession.shared.setCatalog(nil, for: server) }
        return Rig(store: store, entry: entry, uploader: uploader, nav: PopoverNavigation(defaults: defaults),
                   defaults: defaults)
    }

    /// The native controls of the rendered tab: the sub-tab control and the gyms' region menu.
    @MainActor
    private struct Screen {
        let selectedSubTab: BattleSubTab?
        let showsGyms: Bool
    }

    private func screen(_ rig: Rig, nav: PopoverNavigation? = nil) async throws -> Screen {
        let nav = nav ?? rig.nav
        let snapshot = try await NativeControls.snapshot(
            of: BattleView(store: rig.store, navigation: nav)
                .environment(rig.uploader).environment(rig.entry).environment(rig.store).environment(nav),
            height: 520)
        let segments = NativeControls.descendants(snapshot.host).compactMap { $0 as? NSSegmentedControl }
        let selected = segments.count == 1 && segments[0].selectedSegment >= 0
            ? BattleSubTab.allCases[segments[0].selectedSegment] : nil
        let region = rig.store.l.gymRegionName(GymFixtures.catalog().regions[0])
        return Screen(selectedSubTab: selected,
                      showsGyms: snapshot.buttons.contains { $0 is NSPopUpButton && $0.title == region })
    }

    // MARK: What each sub-tab holds

    func testEachSubTabHoldsOnlyItsSectionWhenLinked() throws {
        let uploader = try rig(linked: true).uploader
        XCTAssertEqual(BattleView.layout(.entry, uploader: uploader, hasEntry: true), .init(sections: [.entry], bottomLinkLine: false))
        XCTAssertEqual(BattleView.layout(.battle, uploader: uploader, hasEntry: true), .init(sections: [.gyms], bottomLinkLine: false))
        XCTAssertEqual(BattleView.layout(.history, uploader: uploader, hasEntry: true), .init(sections: [.recent], bottomLinkLine: false))
    }

    func testUnlinkedEntryAndHistoryShowTheLinkLineOnceAndBattleKeepsTheGyms() throws {
        let uploader = try rig(linked: false).uploader
        for tab in BattleSubTab.allCases {
            let layout = BattleView.layout(tab, uploader: uploader, hasEntry: true)
            let lines = layout.sections.filter { $0 == .linkLine }.count + (layout.bottomLinkLine ? 1 : 0)
            XCTAssertEqual(lines, 1, "\(tab) shows the link line exactly once")
        }
        XCTAssertEqual(BattleView.layout(.entry, uploader: uploader, hasEntry: true), .init(sections: [.linkLine], bottomLinkLine: false))
        XCTAssertEqual(BattleView.layout(.battle, uploader: uploader, hasEntry: true), .init(sections: [.gyms], bottomLinkLine: true))
        XCTAssertEqual(BattleView.layout(.history, uploader: uploader, hasEntry: true), .init(sections: [.linkLine], bottomLinkLine: false))
    }

    func testOneGymServiceServesEveryVisitToTheBattleSubTab() {
        let holder = GymServiceHolder()
        var made = 0
        let make = {
            made += 1
            return GymService(link: { nil }, badges: { GymBadges() }, ownedTMs: { [] }, applyReward: { _, _, _ in })
        }
        let first = holder.resolve(make)
        let second = holder.resolve(make)
        XCTAssertTrue(first === second, "a sub-tab switch must not drop the gym result on screen")
        XCTAssertEqual(made, 1)
    }

    func testRejectedTokenKeepsTheContentAndTheBottomLinkLine() async throws {
        let uploader = try rig(linked: true, uploadStatus: 401).uploader
        await uploader.tick()
        XCTAssertTrue(uploader.tokenRejected)
        for tab in BattleSubTab.allCases {
            let layout = BattleView.layout(tab, uploader: uploader, hasEntry: true)
            XCTAssertFalse(layout.sections.contains(.linkLine), "\(tab)")
            XCTAssertTrue(layout.bottomLinkLine, "\(tab)")
        }
    }

    func testRenderedGymsAppearOnlyOnTheBattleSubTab() async throws {
        let rig = try rig(linked: true)
        for tab in BattleSubTab.allCases {
            rig.nav.battleSubTab = tab
            let screen = try await screen(rig)
            XCTAssertEqual(screen.selectedSubTab, tab)
            XCTAssertEqual(screen.showsGyms, tab == .battle, "\(tab)")
        }
    }

    func testRenderedUnlinkedBattleSubTabStillShowsTheGyms() async throws {
        let rig = try rig(linked: false)
        rig.nav.battleSubTab = .battle
        XCTAssertEqual(BattleView.layout(.battle, uploader: rig.uploader, hasEntry: true).sections, [.gyms])
        let screen = try await screen(rig)
        XCTAssertEqual(screen.selectedSubTab, .battle, "the sub-tab control shows while unlinked")
    }

    // MARK: Persistence

    func testChosenSubTabPersistsAcrossOpenings() throws {
        let defaults = try defaults()
        let first = PopoverNavigation(defaults: defaults)
        XCTAssertEqual(first.battleSubTab, .entry, "first open lands on Entry")
        first.battleSubTab = .history
        first.reset()
        XCTAssertEqual(first.battleSubTab, .history)
        XCTAssertEqual(PopoverNavigation(defaults: defaults).battleSubTab, .history)
    }

    func testRebuiltViewOpensOnTheStoredSubTab() async throws {
        let rig = try rig(linked: true)
        rig.nav.battleSubTab = .battle
        let screen = try await screen(rig, nav: PopoverNavigation(defaults: rig.defaults))
        XCTAssertEqual(screen.selectedSubTab, .battle)
        XCTAssertTrue(screen.showsGyms)
    }

    func testUnknownStoredSubTabFallsBackToEntry() throws {
        let defaults = try defaults()
        defaults.set("removed-tab", forKey: BattleSubTab.defaultsKey)
        XCTAssertEqual(PopoverNavigation(defaults: defaults).battleSubTab, .entry)
    }

    // MARK: Picker and entry points

    func testClosingTheFighterPickerReturnsToEntry() throws {
        let nav = PopoverNavigation(defaults: try defaults())
        nav.tab = .battle
        nav.battleSubTab = .history
        nav.battlePicker = .add
        nav.closeBattlePicker()
        XCTAssertNil(nav.battlePicker)
        XCTAssertEqual(nav.battleSubTab, .entry)
    }

    func testLeavingTheTabWithThePickerOpenKeepsTheRememberedSubTab() throws {
        let nav = PopoverNavigation(defaults: try defaults())
        nav.tab = .battle
        nav.battleSubTab = .history
        nav.battlePicker = .add
        nav.tab = .home
        XCTAssertNil(nav.battlePicker)
        XCTAssertEqual(nav.battleSubTab, .history)
    }

    func testStatusMenuBattleOpensTheRememberedSubTab() throws {
        let nav = PopoverNavigation(defaults: try defaults())
        nav.battleSubTab = .battle
        nav.reset()
        nav.openBattle()
        XCTAssertEqual(nav.tab, .battle)
        XCTAssertEqual(nav.battleSubTab, .battle)
    }

    // MARK: Layout

    func testSubTabControlFitsThePopoverWidthInEveryLanguage() {
        for language in AppLanguage.allCases {
            let l = L(language)
            let picker = NSHostingView(rootView: Picker("", selection: .constant(BattleSubTab.entry)) {
                ForEach(BattleSubTab.allCases, id: \.self) { Text(l.title(of: $0)).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize())
            XCTAssertLessThanOrEqual(picker.fittingSize.width, PopoverMetrics.contentWidth,
                                     "\(language): the battle sub-tabs need more than the popover width")
        }
    }
}
