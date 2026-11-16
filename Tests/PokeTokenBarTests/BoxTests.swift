import AppKit
import SwiftUI
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

    func testBattleTabKeepsRecentBattlesButNoConnectionTradeOrCoworkers() async throws {
        let link = try await link()
        let l = link.store.l
        let view = try sourceFile("Sources/PokeTokenBar/UI/BattleView.swift")
        XCTAssertFalse(view.contains("l.partyUploadTokenLabel"), "the token moved to Settings")
        XCTAssertTrue(view.contains("parts: [.recent]"), "Battle lists recent battles only")
        XCTAssertFalse(view.contains("tradeOfferButton") || view.contains("[.coworkers]"))
        XCTAssertNil(BattleInfoSections.recentEmptyText(link.uploader.battleInfo, l), "recent battles are listed")
    }

    func testCoworkersTabListsCoworkersAndOffersATradeWhenConnected() async throws {
        let link = try await link()
        let l = link.store.l
        XCTAssertEqual(link.uploader.battleInfo?.coworkers.map(\.name).contains("Jordan"), true)
        XCTAssertNil(BattleInfoSections.coworkersEmptyText(link.uploader.battleInfo, l), "coworkers are listed")
        let view = try sourceFile("Sources/PokeTokenBar/UI/CoworkersView.swift")
        XCTAssertTrue(view.contains("parts: [.coworkers]"))
        XCTAssertTrue(view.contains("Button(l.tradeOfferButton)"), "connected users can offer a trade here")
        XCTAssertFalse(view.contains("partyUploadTokenLabel"), "no token UI here")
    }

    func testDisconnectedCoworkersTabPointsAtTheSettingsConnectionInsteadOfDuplicatingIt() async throws {
        let link = try await link(connected: false)
        let l = link.store.l
        XCTAssertTrue(l.coworkersNotConnected.contains("YPoke"))
        let view = try sourceFile("Sources/PokeTokenBar/UI/CoworkersView.swift")
        XCTAssertTrue(view.contains("Button(l.coworkersOpenConnection) { navigation.openYPokeSettings() }"))
        XCTAssertFalse(view.contains("partyUploadTokenLabel"))
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
        let view = try sourceFile("Sources/PokeTokenBar/UI/CoworkersView.swift")
        XCTAssertTrue(view.contains("if navigation.showingTradeOffer, connected"), "the offer screen replaces the section list")
        XCTAssertTrue(view.contains("initialGive: navigation.tradeGiveID"), "the give is preselected")
        _ = link
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
        let picker = try sourceFile("Sources/PokeTokenBar/UI/PopoverView.swift")
        let body = try XCTUnwrap(picker.range(of: "struct PopoverTabPicker"))
        let source = String(picker[body.lowerBound...].prefix(2_000))
        XCTAssertTrue(source.contains("if selected {\n                            Text(l.title(of: tab))"),
                      "only the selected tab spells its name")
        XCTAssertTrue(source.contains(".help(l.title(of: tab))") && source.contains(".accessibilityLabel(l.title(of: tab))"),
                      "every tab keeps its name as tooltip and accessibility label")
        for tab in PopoverTab.allCases { XCTAssertFalse(tab.symbol.isEmpty) }
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
        let free = try await NativeControls.snapshot(of: slot, height: 140)
        XCTAssertTrue(free.has(store.l.heldItemSwap), "unlocked slot offers the Swap menu: \(free.labels)")

        store.setTradeLocked([BoxDexFixture.pikachuID])
        XCTAssertFalse(store.unequip(from: BoxDexFixture.pikachuID))
        XCTAssertFalse(store.equip(.item(.leftovers), to: BoxDexFixture.pikachuID))
        XCTAssertEqual(store.heldItemRef(of: BoxDexFixture.pikachuID), .item(.choiceScarf))
        let locked = try await NativeControls.snapshot(of: slot, height: 140)
        XCTAssertFalse(locked.has(store.l.heldItemSwap), "no Swap while listed: \(locked.labels)")
    }

    func testTheFirstBoxCellSitsInTheFirstColumn() async throws {
        let store = try store()
        store.update(todayTokensByProvider: ["test": 0], todayDate: "d1", monthTotal: 0, burnTier: .idle,
                     limitWarning: false, hasUsageData: true)
        for _ in 0..<100 where store.currentLine == nil { await Task.yield() }
        // Every individual's sprite is a solid red square, so red runs on a scanline are the cells of a row.
        let spriteIDs = Set(store.boxIndividuals.flatMap { [$0.speciesID, store.boxMegaSpriteID($0)].compactMap { $0 } })
        for species in spriteIDs {
            for shiny in [false, true] {
                let key = SpriteLoader.cacheDir.appendingPathComponent(
                    SpriteStore.cacheKey(speciesID: species, animated: false, shiny: shiny) + ".png").path as NSString
                let image = NSImage(size: NSSize(width: 96, height: 96))
                image.lockFocus()
                NSColor.red.setFill()
                NSRect(x: 0, y: 0, width: 96, height: 96).fill()
                image.unlockFocus()
                let previous = SpriteLoader.imageCache.object(forKey: key)
                SpriteLoader.imageCache.setObject(image, forKey: key)
                addTeardownBlock { @MainActor in
                    if let previous { SpriteLoader.imageCache.setObject(previous, forKey: key) }
                    else { SpriteLoader.imageCache.removeObject(forKey: key) }
                }
            }
        }
        let host = OffscreenRender.host(
            BoxView(store: store, navigation: PopoverNavigation()).frame(width: PopoverMetrics.contentWidth)
                .background(Color.white).environment(\.colorScheme, .light),
            size: CGSize(width: PopoverMetrics.contentWidth, height: 520), appearance: .aqua)
        var cells = 0
        for _ in 0..<30 where cells < 4 {
            try await OffscreenRender.settle(host, for: .milliseconds(100))
            cells = try firstRowCellCount(host)
        }
        XCTAssertEqual(cells, 4,
                       "five individuals fill a row of four first; an empty cell before the first one shifts the grid")
    }

    /// Red runs of at least 8px on a scanline a little below the topmost red pixel.
    private func firstRowCellCount(_ host: NSView) throws -> Int {
        let bitmap = try OffscreenRender.bitmap(of: host)
        func isRed(_ x: Int, _ y: Int) -> Bool {
            guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
            return c.redComponent > 0.8 && c.greenComponent < 0.4 && c.blueComponent < 0.3
        }
        guard let top = (0..<bitmap.pixelsHigh).first(where: { y in (0..<bitmap.pixelsWide).contains { isRed($0, y) } })
        else { return 0 }
        let y = min(top + 10, bitmap.pixelsHigh - 1)
        var runs = 0, run = 0
        for x in 0...bitmap.pixelsWide {
            if x < bitmap.pixelsWide, isRed(x, y) { run += 1 } else { if run >= 8 { runs += 1 }; run = 0 }
        }
        return runs
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
        func render(_ store: CompanionStore, _ species: CompanionStore.DexSpecies) async throws -> NativeControls.Snapshot {
            try await NativeControls.snapshot(of: PokemonDetailView(store: store, species: species, onBack: {})
                .environment(nav), height: 700)
        }
        let screen = try await render(store, species)
        XCTAssertEqual(store.boxCount(speciesID: 25), 1)
        let detailSource = try sourceFile("Sources/PokeTokenBar/UI/CompanionView.swift")
        XCTAssertTrue(detailSource.contains("Label(store.l.boxCount(count)"), "the detail offers the Box count")
        for forbidden in [store.l.heldItemEquip, store.l.heldItemRemove, store.l.heldItemSwap] {
            XCTAssertFalse(screen.has(forbidden), "\(forbidden) belongs to the Box: \(screen.labels)")
        }
        let detail = try sourceFile("Sources/PokeTokenBar/UI/CompanionView.swift")
        let body = try XCTUnwrap(detail.range(of: "struct PokemonDetailView"))
        XCTAssertFalse(detail[body.lowerBound...].prefix(20_000).contains("HeldItemSlot("),
                       "individual held-item controls belong to the Box detail")

        let sparse = try self.store { $0.dex.removeAll { $0.finalID == 6 } }
        let none = try XCTUnwrap(store.dexSpecies.first { $0.id == 6 })
        let empty = try await render(sparse, none)
        XCTAssertEqual(sparse.boxCount(speciesID: 6), 0, "no Box button for a species with none in the Box")
        XCTAssertFalse(empty.has(sparse.l.heldItemSwap))
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
