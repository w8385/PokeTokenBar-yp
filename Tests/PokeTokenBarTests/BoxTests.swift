import AppKit
import SwiftUI
import Vision
import XCTest
@testable import PokeTokenBar

@MainActor
final class BoxTests: XCTestCase {
    private func store(language: AppLanguage = .en, mutate: (inout CompanionState) -> Void = { _ in }) throws -> CompanionStore {
        let (store, cleanup) = try BoxDexFixture.makeStore(language: language, mutate: mutate)
        addTeardownBlock { cleanup() }
        return store
    }

    private func sourceFile(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    // MARK: Tabs

    func testTabsAreHomeShopBagDexBoxBattleFriendsInThatOrder() {
        XCTAssertEqual(PopoverTab.allCases, [.home, .shop, .bag, .dex, .box, .battle, .coworkers])
    }

    // MARK: Friends tab (the linked coworkers)

    private struct Link {
        let store: CompanionStore
        let uploader: PartyUploader
        let battle: BattleEntryStore
    }

    private func link(connected: Bool = true) async throws -> Link {
        let store = try store()
        let suite = "box-tests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("box-tests-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: scratch) }
        let uploader = await BoxDexFixture.makeUploader(defaults: defaults, scratch: scratch, connected: connected)
        let battle = BattleEntryStore(defaults: defaults)
        _ = battle.add(BoxDexFixture.pikachuID)
        return Link(store: store, uploader: uploader, battle: battle)
    }

    func testBattleTabKeepsConnectionAndRecentBattlesButNoTradeOrCoworkers() async throws {
        let link = try await link()
        let l = link.store.l
        let text = try await renderedText(
            of: BattleView(store: link.store, navigation: PopoverNavigation())
                .environment(link.uploader).environment(link.battle).environment(link.store),
            containing: l.battleRecentTitle, height: 1400)
        XCTAssertTrue(text.localizedCaseInsensitiveContains(l.partyUploadTokenLabel), text)
        XCTAssertTrue(text.localizedCaseInsensitiveContains(l.battleRecentTitle), text)
        XCTAssertFalse(text.localizedCaseInsensitiveContains(l.tradeOfferButton), "trade moved to Coworkers: \(text)")
        XCTAssertFalse(text.localizedCaseInsensitiveContains(l.friendsTitle), "coworkers moved: \(text)")
        XCTAssertFalse(text.contains("Jordan"), text)
    }

    func testCoworkersTabListsCoworkersAndOffersATradeWhenConnected() async throws {
        let link = try await link()
        let l = link.store.l
        let text = try await renderedText(
            of: CoworkersView(store: link.store, navigation: PopoverNavigation())
                .environment(link.uploader).environment(link.battle).environment(link.store),
            containing: "Jordan", height: 700)
        XCTAssertTrue(text.contains("Jordan"), text)
        XCTAssertTrue(text.localizedCaseInsensitiveContains(l.tradeOfferButton), text)
        XCTAssertFalse(text.localizedCaseInsensitiveContains(l.partyUploadTokenLabel), "no token UI here: \(text)")
    }

    func testDisconnectedCoworkersTabPointsAtTheBattleConnectionInsteadOfDuplicatingIt() async throws {
        let link = try await link(connected: false)
        let l = link.store.l
        let text = try await renderedText(
            of: CoworkersView(store: link.store, navigation: PopoverNavigation())
                .environment(link.uploader).environment(link.battle).environment(link.store),
            containing: l.coworkersOpenConnection, height: 520)
        XCTAssertTrue(text.localizedCaseInsensitiveContains(l.coworkersOpenConnection), text)
        XCTAssertTrue(text.contains("YPoke"), text)
        XCTAssertFalse(text.localizedCaseInsensitiveContains(l.tradeOfferButton), text)
        XCTAssertFalse(text.localizedCaseInsensitiveContains(l.partyUploadTokenLabel), text)
    }

    func testTradeFromTheBoxDetailOpensTheOfferOnCoworkersWithTheGivePreselected() async throws {
        let link = try await link()
        let nav = PopoverNavigation()
        nav.openBoxDetail(id: BoxDexFixture.eeveeID)
        nav.openTradeOffer(giving: BoxDexFixture.eeveeID)
        XCTAssertEqual(nav.tab, .coworkers)
        XCTAssertTrue(nav.showingTradeOffer)
        XCTAssertEqual(nav.tradeGiveID, BoxDexFixture.eeveeID)
        XCTAssertNil(nav.boxDetailID)
        let l = link.store.l
        let text = try await renderedText(
            of: CoworkersView(store: link.store, navigation: nav)
                .environment(link.uploader).environment(link.battle).environment(link.store),
            containing: "to send", height: 520)
        XCTAssertTrue(text.localizedCaseInsensitiveContains("to send"), "the offer screen replaces the section list: \(text)")
        XCTAssertFalse(text.contains("Jordan"), "coworkers list is behind the offer screen: \(text)")
    }

    func testDexTabIsNamedPokedexInEveryLanguageAndBoxHasItsOwnLabel() {
        for language in AppLanguage.allCases {
            let l = L(language)
            XCTAssertEqual(l.title(of: .dex), l.dexTitle, "\(language)")
            XCTAssertEqual(l.title(of: .box), l.boxTab, "\(language)")
            XCTAssertEqual(Set(PopoverTab.allCases.map(l.title(of:))).count, PopoverTab.allCases.count,
                           "\(language): every tab needs its own label")
        }
        XCTAssertEqual(L(.ko).title(of: .dex), "도감")
        XCTAssertEqual(L(.ko).title(of: .box), "박스")
    }

    func testTheCoworkersTabIsNamedFriendsInEveryLanguage() {
        let names: [AppLanguage: String] = [.ko: "친구", .en: "Friends", .ja: "フレンド", .es: "Amigos",
                                            .fr: "Amis", .pt: "Amigos", .de: "Freunde", .ru: "Друзья"]
        XCTAssertEqual(Set(names.keys), Set(AppLanguage.allCases))
        for (language, name) in names {
            XCTAssertEqual(L(language).title(of: .coworkers), name, "\(language)")
            XCTAssertEqual(L(language).friendsTitle, name, "\(language)")
        }
    }

    func testTabBarFitsThePopoverWidthForEveryLanguageAndSelectedTab() {
        for language in AppLanguage.allCases {
            for selected in PopoverTab.allCases {
                var selection = selected
                let picker = NSHostingView(rootView: PopoverTabPicker(
                    selection: Binding(get: { selection }, set: { selection = $0 }), l: L(language)))
                XCTAssertLessThanOrEqual(picker.fittingSize.width, PopoverMetrics.contentWidth,
                                         "\(language) / \(selected): the tab bar needs more than the popover width")
            }
        }
    }

    func testTheSelectedTabIsTheOnlyOneThatSpellsItsNameAndEveryTabHasATooltipSource() async throws {
        let l = L(.en)
        var selection = PopoverTab.battle
        let scale: CGFloat = 3
        let text = try await renderedText(
            of: PopoverTabPicker(selection: Binding(get: { selection }, set: { selection = $0 }), l: l)
                .frame(width: PopoverMetrics.contentWidth)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: PopoverMetrics.contentWidth * scale, height: 90, alignment: .topLeading),
            containing: l.title(of: .battle), width: PopoverMetrics.contentWidth * scale, height: 90)
        XCTAssertTrue(text.localizedCaseInsensitiveContains(l.title(of: .battle)), text)
        for other in PopoverTab.allCases where other != .battle {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(l.title(of: other)), "\(other) should be icon-only: \(text)")
            XCTAssertFalse(other.symbol.isEmpty)
        }
    }

    // MARK: Membership

    func testBoxListsRaisedFriendAndGraduatedWithTheirRoles() throws {
        let store = try store()
        let roles = Dictionary(uniqueKeysWithValues: store.boxIndividuals.map { ($0.id, $0.role) })
        XCTAssertEqual(roles[BoxDexFixture.raisedID], .raising)
        XCTAssertEqual(roles[BoxDexFixture.charizardID], .friend)
        XCTAssertEqual(roles[BoxDexFixture.pikachuID], .graduated)
        XCTAssertEqual(roles[BoxDexFixture.onixID], .graduated)
        XCTAssertEqual(roles.count, 5)
    }

    func testBoxCarriesTheHeldItemBadgeOfEachIndividual() throws {
        let store = try store()
        XCTAssertEqual(store.heldItemRef(of: BoxDexFixture.raisedID), .item(.focusSash))
        XCTAssertEqual(store.heldItemRef(of: BoxDexFixture.pikachuID), .item(.choiceScarf))
        guard case .stone(let stone)? = store.heldItemRef(of: BoxDexFixture.charizardID) else {
            return XCTFail("the friend holds a Mega Stone")
        }
        XCTAssertEqual(stone.variantSuffix?.lowercased(), "x")
        XCTAssertNil(store.heldItemRef(of: BoxDexFixture.eeveeID))
        XCTAssertEqual(store.currentHeldItemRef, .item(.focusSash))
    }

    func testReleasedRecordsAreNotInTheBox() throws {
        let store = try store { state in
            state.dex[3].releasedAt = Date(timeIntervalSince1970: 1_700_001_000)
        }
        XCTAssertNil(store.boxIndividual(id: BoxDexFixture.eeveeID))
        XCTAssertEqual(store.boxIndividuals.count, 4)
    }

    func testMegaHolderShowsItsMegaFormInTheBox() throws {
        let store = try store()
        let zard = try XCTUnwrap(store.boxIndividual(id: BoxDexFixture.charizardID))
        XCTAssertNotNil(store.boxMegaSpriteID(zard), "a friend holding its stone shows the Mega form")
        let pikachu = try XCTUnwrap(store.boxIndividual(id: BoxDexFixture.pikachuID))
        XCTAssertNil(store.boxMegaSpriteID(pikachu))
        store.unequip(from: BoxDexFixture.charizardID)
        XCTAssertNil(store.boxMegaSpriteID(zard))
    }

    func testBoxIDOfTheRaisedEntryIsItsInstanceNotTheSynthesizedEntryID() throws {
        let store = try store()
        let raisedEntry = try XCTUnwrap(store.dexEntries.first(where: store.isActiveDexEntry))
        XCTAssertTrue(raisedEntry.id.hasPrefix("active-"))
        XCTAssertEqual(store.boxID(of: raisedEntry), BoxDexFixture.raisedID)
    }

    func testFiltersAndSorts() throws {
        let store = try store()
        XCTAssertEqual(Set(store.filteredBoxIndividuals(hasItemOnly: true).map(\.id)),
                       [BoxDexFixture.raisedID, BoxDexFixture.pikachuID, BoxDexFixture.charizardID])
        XCTAssertEqual(store.filteredBoxIndividuals(shinyOnly: true).map(\.id), [BoxDexFixture.pikachuID])
        XCTAssertEqual(store.filteredBoxIndividuals(speciesID: 133).map(\.id), [BoxDexFixture.eeveeID])
        XCTAssertEqual(store.filteredBoxIndividuals(sort: .level).first?.id, BoxDexFixture.charizardID)
        XCTAssertEqual(store.filteredBoxIndividuals(sort: .recent).first?.id, BoxDexFixture.raisedID,
                       "the raised Pokémon always leads the recent sort")
        XCTAssertEqual(store.boxCount(speciesID: 25), 1)
        XCTAssertEqual(store.boxCount(speciesID: 999), 0)
    }

    // MARK: Equip lives in the Box detail only

    func testEquipAndUnequipFromTheBoxContractWorkAndTheTradeLockStillBlocksThem() throws {
        let store = try store()
        XCTAssertTrue(store.equip(.item(.leftovers), to: BoxDexFixture.eeveeID))
        XCTAssertEqual(store.heldItemRef(of: BoxDexFixture.eeveeID), .item(.leftovers))
        XCTAssertTrue(store.unequip(from: BoxDexFixture.eeveeID))
        XCTAssertNil(store.heldItemRef(of: BoxDexFixture.eeveeID))
    }

    func testAMegaStoneEquipsThroughTheBoxContractAndSwapsBackIntoTheBag() throws {
        let store = try store()
        let venusaurite = try XCTUnwrap(MegaStone.stone(slug: "venusaurite"))
        XCTAssertTrue(store.equip(.stone(venusaurite), to: BoxDexFixture.eeveeID))
        XCTAssertEqual(store.heldItemRef(of: BoxDexFixture.eeveeID), .stone(venusaurite))
        XCTAssertEqual(store.bagCount(of: .stone(venusaurite)), 0)
        XCTAssertTrue(store.equip(.item(.leftovers), to: BoxDexFixture.eeveeID))
        XCTAssertEqual(store.bagCount(of: .stone(venusaurite)), 1, "the replaced stone goes back to the bag")
    }

    func testEqualLevelsAndNumbersFallBackToNewestFirstThenId() throws {
        let store = try store { state in
            for index in state.dex.indices where state.dex[index].id != BoxDexFixture.onixID {
                state.dex[index].profile?.level = 30
            }
            state.dex[state.dex.firstIndex { $0.id == BoxDexFixture.eeveeID }!].caughtAt = nil
        }
        let byLevel = store.filteredBoxIndividuals(sort: .level).map(\.id)
        XCTAssertEqual(byLevel.first, BoxDexFixture.onixID, "41 is the highest level")
        let thirties = byLevel.filter { $0 != BoxDexFixture.onixID && $0 != BoxDexFixture.raisedID }
        XCTAssertEqual(thirties, [BoxDexFixture.pikachuID, BoxDexFixture.charizardID, BoxDexFixture.eeveeID],
                       "equal levels keep the newest capture first and a missing date last")
    }

    func testBoxIDOfAReleasedEntryIsNil() throws {
        let store = try store { state in
            state.dex[state.dex.firstIndex { $0.id == BoxDexFixture.onixID }!].releasedAt = Date(timeIntervalSince1970: 1)
        }
        let released = try XCTUnwrap(store.state.dex.first { $0.id == BoxDexFixture.onixID })
        XCTAssertNil(store.boxID(of: released))
        XCTAssertEqual(store.boxID(of: try XCTUnwrap(store.state.dex.first { $0.id == BoxDexFixture.eeveeID })),
                       BoxDexFixture.eeveeID)
        XCTAssertEqual(store.boxID(of: try XCTUnwrap(store.raisedDexEntry)), BoxDexFixture.raisedID)
    }

    func testListedForTradeBlocksEquipAndUnequipAndTheSlotDropsItsControls() async throws {
        let store = try store()
        let slot = HeldItemSlot(store: store, individualID: BoxDexFixture.pikachuID, speciesID: 25,
                                speciesName: "Pikachu") {}
        let free = try await renderedText(of: slot, containing: store.l.heldItemRemove)
        XCTAssertTrue(free.contains(store.l.heldItemRemove), "unlocked slot offers Remove: \(free)")

        store.setTradeLocked([BoxDexFixture.pikachuID])
        XCTAssertFalse(store.unequip(from: BoxDexFixture.pikachuID))
        XCTAssertFalse(store.equip(.item(.leftovers), to: BoxDexFixture.pikachuID))
        XCTAssertEqual(store.heldItemRef(of: BoxDexFixture.pikachuID), .item(.choiceScarf))
        let locked = try await renderedText(of: slot, containing: store.l.heldItemLabel)
        XCTAssertTrue(locked.contains(store.l.heldItemLabel), "the slot still names the item: \(locked)")
        XCTAssertFalse(locked.contains(store.l.heldItemRemove), "no Remove while listed: \(locked)")
        XCTAssertFalse(locked.contains(store.l.heldItemSwap), "no Swap while listed: \(locked)")
    }

    private func renderedText<V: View>(of view: V, containing expected: String, width: CGFloat = PopoverMetrics.contentWidth,
                                       height: CGFloat = 140) async throws -> String {
        try await renderedWords(of: view, containing: expected, width: width, height: height)
            .compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }

    func testTheFirstBoxCellSitsInTheFirstColumn() async throws {
        let store = try store()
        store.update(todayTokensByProvider: ["test": 0], todayDate: "d1", monthTotal: 0, burnTier: .idle,
                     limitWarning: false, hasUsageData: true)
        for _ in 0..<100 where store.currentLine == nil { await Task.yield() }
        let words = try await renderedWords(
            of: BoxView(store: store, navigation: PopoverNavigation()), containing: "Onix", height: 520)
        let levels = words.filter { ($0.topCandidates(1).first?.string ?? "").lowercased().hasPrefix("lv") }
        let top = try XCTUnwrap(levels.map(\.boundingBox.midY).max())
        XCTAssertEqual(levels.filter { abs($0.boundingBox.midY - top) < 0.03 }.count, 4,
                       "five individuals fill a row of four first; an empty cell before the first one shifts the grid")
    }

    private func renderedWords<V: View>(of view: V, containing expected: String, width: CGFloat = PopoverMetrics.contentWidth,
                                        height: CGFloat) async throws -> [VNRecognizedTextObservation] {
        let host = OffscreenRender.host(
            view.frame(width: width).background(Color.white).environment(\.colorScheme, .light),
            size: CGSize(width: width, height: height), appearance: .aqua)
        var words: [VNRecognizedTextObservation] = []
        for _ in 0..<30 {
            try await OffscreenRender.settle(host, for: .milliseconds(100))
            let bitmap = try OffscreenRender.bitmap(of: host)
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
            words = request.results ?? []
            let text = words.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            if text.localizedCaseInsensitiveContains(expected) { break }
        }
        return words
    }

    func testOnlyTheBoxDetailSlotChangesHeldItemsFromTheUI() throws {
        let ui = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeTokenBar/UI")
        let files = try FileManager.default.contentsOfDirectory(at: ui, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        var offenders: [String] = []
        for file in files where file.lastPathComponent != "BoxDetailView.swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            if source.contains(".equip(") || source.contains(".unequip(") { offenders.append(file.lastPathComponent) }
        }
        XCTAssertEqual(offenders, [], "held items are equipped in the Box detail only")
    }

    // MARK: Dex detail is species-only

    func testDexDetailOffersTheBoxCountAndNoIndividualControls() async throws {
        let store = try store()
        let species = try XCTUnwrap(store.dexSpecies.first { $0.id == 25 })
        let nav = PopoverNavigation()
        func render(_ store: CompanionStore, _ species: CompanionStore.DexSpecies) async throws -> String {
            try await renderedText(of: PokemonDetailView(store: store, species: species, onBack: {})
                .environment(nav).frame(height: 700), containing: store.l.boxCount(1), height: 700)
        }
        let text = try await render(store, species)
        XCTAssertTrue(text.contains(store.l.boxCount(1)), "Seen: \(text)")
        for forbidden in [store.l.heldItemLabel, store.l.heldItemEquip, store.l.heldItemRemove,
                          store.l.friendLabel, store.l.dexRaising] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(forbidden), "\(forbidden) belongs to the Box: \(text)")
        }

        let sparse = try self.store { $0.dex.removeAll { $0.finalID == 6 } }
        let none = try XCTUnwrap(store.dexSpecies.first { $0.id == 6 })
        let empty = try await render(sparse, none)
        XCTAssertFalse(empty.contains("in your Box"), "no Box button for a species with none in the Box: \(empty)")
    }

    // MARK: The catch log is gone

    func testNoCatchLogViewOrNavigationRemains() throws {
        let nav = try sourceFile("Sources/PokeTokenBar/UI/PopoverView.swift")
        let view = try sourceFile("Sources/PokeTokenBar/UI/CompanionView.swift")
        let store = try sourceFile("Sources/PokeTokenBar/Core/CompanionStore.swift")
        for (name, source) in [("PopoverView", nav), ("CompanionView", view), ("CompanionStore", store)] {
            for forbidden in ["showingCollectionLog", "CatchLog", "DexEntryRow", "filteredDexEntries"] {
                XCTAssertFalse(source.contains(forbidden), "\(name) still mentions \(forbidden)")
            }
        }
    }

    func testNoCatchLogStringRemainsInAnyLanguage() throws {
        let mirror = try sourceFile("Sources/PokeTokenBar/Core/Localization.swift")
        for forbidden in ["var catchLogTitle", "var dexReleased", "var sortDateDesc", "var sortDateAsc"] {
            XCTAssertFalse(mirror.contains(forbidden), forbidden)
        }
        for language in AppLanguage.allCases {
            XCTAssertFalse(L(language).dexTitle.isEmpty)
        }
    }

    // MARK: Old saves

    func testASaveWithoutAnyBoxFieldLoadsAndListsItsEntries() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("old-save-\(UUID()).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        let old = """
        {"dex":[{"id":"old-1","baseID":25,"finalID":25,"chainOrder":[25],"rarity":"common","caughtAt":1700000000,
        "isShiny":false,"names":{}}],"inventory":{},"language":"en"}
        """
        try Data(old.utf8).write(to: file)
        let store = CompanionStore(provider: BoxDexProvider(), fileURL: file)
        XCTAssertEqual(store.boxIndividual(id: "old-1")?.speciesID, 25)
        XCTAssertNil(store.heldItemRef(of: "old-1"))
    }
}
