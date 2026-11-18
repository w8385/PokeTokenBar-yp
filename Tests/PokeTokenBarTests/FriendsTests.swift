import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class FriendsTests: XCTestCase {
    private final class Clock { var now = Date(timeIntervalSince1970: 1_700_000_000) }

    private let line = EvoLine(
        baseID: 1,
        tree: EvoNode(speciesID: 1, children: [EvoNode(speciesID: 2, children: [])]),
        rarity: .common,
        names: [1: ["en": "P1"], 2: ["en": "P2"]])

    private func entry(_ id: String, final finalID: Int = 2, released: Bool = false, shiny: Bool = false) -> DexEntry {
        DexEntry(id: id, baseID: 1, finalID: finalID, chainOrder: [1, finalID], rarity: .common,
                 caughtAt: Date(timeIntervalSince1970: 1_700_000_000), isShiny: shiny,
                 releasedAt: released ? Date(timeIntervalSince1970: 1_700_000_100) : nil)
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("friends-\(UUID().uuidString).json")
    }

    private func makeStore(dex: [DexEntry], friends: [String] = [], clock: Clock = Clock(),
                           url: URL? = nil) throws -> CompanionStore {
        let url = url ?? tempURL()
        var state = CompanionState()
        state.installBaselineSet = true
        state.dex = dex
        state.friendEntryIDs = friends
        state.pendingHatchID = 1
        try JSONEncoder().encode(state).write(to: url)
        return CompanionStore(provider: StubProvider(value: line), clock: { clock.now }, fileURL: url,
                              rng: SeededRNG(seed: 7))
    }

    // MARK: Picker rules

    func testPickerOffersOnlyGraduatedEntries() throws {
        let store = try makeStore(dex: [entry("a"), entry("b", released: true), entry("c")])
        XCTAssertEqual(Set(store.friendCandidates.map(\.id)), ["a", "c"])
        XCTAssertFalse(store.addFriend(entryID: "b"), "a released entry cannot join")
        XCTAssertFalse(store.addFriend(entryID: "nope"), "an unknown entry cannot join")
        XCTAssertTrue(store.state.friendEntryIDs.isEmpty)
    }

    func testAtMostTwoFriendsAndNoDuplicates() throws {
        let store = try makeStore(dex: [entry("a"), entry("b"), entry("c")])
        XCTAssertTrue(store.addFriend(entryID: "a"))
        XCTAssertFalse(store.addFriend(entryID: "a"), "the same entry cannot join twice")
        XCTAssertTrue(store.addFriend(entryID: "b"))
        XCTAssertFalse(store.addFriend(entryID: "c"), "a third friend is refused")
        XCTAssertEqual(store.state.friendEntryIDs, ["a", "b"])
        XCTAssertEqual(store.friendSubjects.map(\.entryID), ["a", "b"])
        XCTAssertEqual(store.friendCandidates.map(\.id), ["c"], "picked friends leave the picker")
    }

    func testRemovingAFriendFreesTheSlot() throws {
        let store = try makeStore(dex: [entry("a"), entry("b"), entry("c")], friends: ["a", "b"])
        store.removeFriend(entryID: "a")
        XCTAssertEqual(store.friendSubjects.map(\.entryID), ["b"])
        XCTAssertTrue(store.addFriend(entryID: "c"))
        XCTAssertEqual(store.state.friendEntryIDs, ["b", "c"])
    }

    func testFriendSubjectUsesTheFinalSpecies() throws {
        let store = try makeStore(dex: [entry("a", final: 2, shiny: true)], friends: ["a"])
        let friend = try XCTUnwrap(store.friendSubjects.first)
        XCTAssertEqual(friend.speciesID, 2)
        XCTAssertTrue(friend.isShiny)
    }

    // MARK: Save

    func testSaveWithoutTheFieldLoadsWithNoFriends() throws {
        let url = tempURL()
        let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":0,\"spentTokens\":0,"
            + "\"lastDate\":\"d\",\"active\":null,\"dex\":[],\"collectedFinals\":[],\"eggUsage\":0,\"pendingHatchID\":1}"
        try Data(json.utf8).write(to: url)
        let store = CompanionStore(provider: StubProvider(value: line), clock: { Date() }, fileURL: url,
                                   rng: SeededRNG(seed: 7))
        XCTAssertTrue(store.state.friendEntryIDs.isEmpty)
        XCTAssertTrue(store.friendSubjects.isEmpty)
    }

    func testFriendsSurviveARestart() throws {
        let url = tempURL()
        _ = try makeStore(dex: [entry("a"), entry("b")], friends: ["b"], url: url)
        let reloaded = CompanionStore(provider: StubProvider(value: line), clock: { Date() }, fileURL: url,
                                      rng: SeededRNG(seed: 7))
        XCTAssertEqual(reloaded.friendSubjects.map(\.entryID), ["b"])
    }

    func testLoadDropsFriendsThatAreNotGraduatedEntries() throws {
        let store = try makeStore(dex: [entry("a"), entry("r", released: true)], friends: ["a", "r", "gone", "a"])
        XCTAssertEqual(store.state.friendEntryIDs, ["a"])
    }

    func testLoadKeepsOnlyTheFirstTwoFriends() throws {
        let store = try makeStore(dex: [entry("a"), entry("b"), entry("c")], friends: ["a", "b", "c"])
        XCTAssertEqual(store.state.friendEntryIDs, ["a", "b"])
    }

    func testExportAndImportCarryTheFriends() throws {
        var state = CompanionState()
        state.dex = [entry("a"), entry("b")]
        state.friendEntryIDs = ["b", "a"]
        let data = try SaveTransfer.encode(state: state, appVersion: "2.5.0", deviceName: "Mac",
                                           now: Date(timeIntervalSince1970: 1_700_000_000))
        let envelope = try SaveTransfer.decode(data)
        XCTAssertEqual(envelope.state.friendEntryIDs, ["b", "a"])
    }

    func testImportDropsAFriendWhoseEntryIsMissing() {
        var state = CompanionState()
        state.dex = [entry("a")]
        state.friendEntryIDs = ["a", "missing"]
        XCTAssertEqual(SaveTransfer.sanitized(state).friendEntryIDs, ["a"])
    }

    // MARK: Click

    func testFriendClickGivesNoGrowthAndLeavesTheMainPetClickAlone() throws {
        let suite = "FriendsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let clock = Clock()
        let url = tempURL()
        var state = CompanionState()
        state.installBaselineSet = true
        state.dex = [entry("a"), entry("b")]
        state.friendEntryIDs = ["a", "b"]
        state.pendingHatchID = 1
        try JSONEncoder().encode(state).write(to: url)
        let companion = CompanionStore(provider: StubProvider(value: line), clock: { clock.now }, fileURL: url,
                                       rng: SeededRNG(seed: 7), defaults: defaults)
        let usage = UsageStore(providers: [], autoRefresh: false, defaults: defaults)
        let controller = FloatingPetController(store: usage, companion: companion, defaults: defaults,
                                               motionOverride: true)
        controller.setDisplayAwake(false)
        controller.crowd.configure(order: [1, 0, 2], motionAllowed: true, active: false)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: url)
        }

        controller.friendClicked(0)
        controller.friendClicked(1)
        XCTAssertEqual(companion.state.clickGrowth, 0)
        XCTAssertEqual(companion.state.eggUsage, 0)

        XCTAssertEqual(companion.growByClick(), ClickGrowth.tokensPerClick)
        XCTAssertEqual(companion.state.clickGrowth, ClickGrowth.tokensPerClick)
        controller.friendClicked(0)
        XCTAssertEqual(companion.state.clickGrowth, ClickGrowth.tokensPerClick)
        XCTAssertEqual(controller.crowd.bubble(1), PetCrowd.Bubble.heart)
    }

    func testFriendClickOutOfRangeIsIgnored() throws {
        let suite = "FriendsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let url = tempURL()
        let companion = CompanionStore(provider: StubProvider(value: line), fileURL: url, defaults: defaults)
        let usage = UsageStore(providers: [], autoRefresh: false, defaults: defaults)
        let controller = FloatingPetController(store: usage, companion: companion, defaults: defaults,
                                               motionOverride: true)
        controller.setDisplayAwake(false)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: url)
        }
        controller.friendClicked(0)
        XCTAssertEqual(companion.state.clickGrowth, 0)
    }

    // MARK: Cheer signal

    func testHatchAndEvolveBumpTheCheerSequence() async throws {
        let chain = EvoLine(
            baseID: 1,
            tree: EvoNode(speciesID: 1, children: [EvoNode(speciesID: 2, children: [EvoNode(speciesID: 3, children: [])])]),
            rarity: .common,
            names: [1: ["en": "P1"], 2: ["en": "P2"], 3: ["en": "P3"]])
        let store = CompanionStore(provider: StubProvider(value: chain), clock: { Date() }, fileURL: tempURL(),
                                   rng: SeededRNG(seed: 9))
        XCTAssertEqual(store.cheerSeq, 0)
        await store.hatch(baseID: 1)
        XCTAssertEqual(store.cheerSeq, 1)
        store.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 0))
        XCTAssertEqual(store.cheerSeq, 2)
    }
}

@MainActor
final class PetRowLayoutTests: XCTestCase {
    private let petSize: CGFloat = 96

    func testWithoutFriendsTheLayoutIsTheOldOne() {
        let layout = PetRowLayout.single
        XCTAssertEqual(layout.panelWidth(petSize: petSize, bubbleWidth: nil), petSize)
        XCTAssertEqual(layout.mainXOffset(petSize: petSize, bubbleWidth: nil), 0)
        XCTAssertEqual(layout.slotOrder, [0])
        XCTAssertEqual(layout.hit(x: 5, petSize: petSize, bubbleWidth: nil), .main)
    }

    func testSavedHomeIsTheMainPetWhateverTheFriendsAndBubble() {
        for count in 0...2 {
            for left in [true, false] {
                for bubble in [false, true] {
                    let layout = PetRowLayout(friendCount: count, friendsOnLeft: left)
                    let size = FloatingPetController.panelSize(petSize: petSize, showingBubble: bubble, layout: layout)
                    let home = NSPoint(x: 400, y: 300)
                    let panel = FloatingPetController.panelOrigin(petOrigin: home, petSize: petSize, panelSize: size,
                                                                  layout: layout, showingBubble: bubble)
                    let back = FloatingPetController.petOrigin(panelOrigin: panel, petSize: petSize, panelSize: size,
                                                               layout: layout, showingBubble: bubble)
                    XCTAssertEqual(back, home, "count \(count) left \(left) bubble \(bubble)")
                }
            }
        }
    }

    func testFriendsFillTheMarginSoABubbleDoesNotMoveThem() {
        let layout = PetRowLayout(friendCount: 2, friendsOnLeft: true)
        let friends = layout.friendsWidth(petSize: petSize)
        let calm = layout.margins(petSize: petSize, bubbleWidth: nil)
        let bubble = layout.margins(petSize: petSize, bubbleWidth: FloatingPetController.bubbleMinWidth)
        XCTAssertEqual(calm.left, friends)
        XCTAssertGreaterThanOrEqual(bubble.left, friends)
        XCTAssertEqual(layout.slotOrder, [2, 1, 0])
        XCTAssertEqual(PetRowLayout(friendCount: 2, friendsOnLeft: false).slotOrder, [0, 1, 2])
    }

    func testFriendBoxesOverlapTheirNeighbours() {
        let friend = PetRowLayout.friendSize(petSize: petSize)
        let slot = PetRowLayout.friendSlotWidth(petSize: petSize)
        XCTAssertLessThan(slot, friend)
        XCTAssertGreaterThanOrEqual(friend - slot, friend * 0.15)
        XCTAssertLessThanOrEqual(friend - slot, friend * 0.35)
        let layout = PetRowLayout(friendCount: 2, friendsOnLeft: true)
        XCTAssertEqual(layout.friendsWidth(petSize: petSize), 2 * slot)
        XCTAssertLessThan(layout.friendsWidth(petSize: petSize), 2 * friend)
    }

    func testHitTestFindsTheFriendUnderTheCursor() {
        let layout = PetRowLayout(friendCount: 2, friendsOnLeft: true)
        let mainX = layout.mainXOffset(petSize: petSize, bubbleWidth: nil)
        let slot = PetRowLayout.friendSlotWidth(petSize: petSize)
        XCTAssertEqual(layout.hit(x: mainX + 10, petSize: petSize, bubbleWidth: nil), .main)
        XCTAssertEqual(layout.hit(x: mainX - 2, petSize: petSize, bubbleWidth: nil), .friend(0))
        XCTAssertEqual(layout.hit(x: mainX - slot - 2, petSize: petSize, bubbleWidth: nil), .friend(1))

        let right = PetRowLayout(friendCount: 2, friendsOnLeft: false)
        XCTAssertEqual(right.hit(x: petSize + 2, petSize: petSize, bubbleWidth: nil), .friend(0))
        XCTAssertEqual(right.hit(x: petSize + slot + 2, petSize: petSize, bubbleWidth: nil), .friend(1))
    }

    func testTheSpriteDrawnInFrontGetsTheClickInTheOverlap() {
        let overlap = PetRowLayout.friendOverlap(petSize: petSize)
        let slot = PetRowLayout.friendSlotWidth(petSize: petSize)
        XCTAssertGreaterThan(overlap, 2)
        for left in [true, false] {
            let layout = PetRowLayout(friendCount: 2, friendsOnLeft: left)
            let mainX = layout.mainXOffset(petSize: petSize, bubbleWidth: nil)
            func x(fromMainEdge distance: CGFloat) -> CGFloat { left ? mainX - distance : mainX + petSize + distance }
            let insideMain = left ? mainX + 1 : mainX + petSize - 1
            XCTAssertEqual(layout.hit(x: insideMain, petSize: petSize, bubbleWidth: nil), .main, "main over friend 0")
            XCTAssertEqual(layout.hit(x: x(fromMainEdge: 1), petSize: petSize, bubbleWidth: nil), .friend(0))
            XCTAssertEqual(layout.hit(x: x(fromMainEdge: slot - 1), petSize: petSize, bubbleWidth: nil), .friend(0),
                           "friend 0 over friend 1 up to where its slot ends")
            XCTAssertEqual(layout.hit(x: x(fromMainEdge: slot + 1), petSize: petSize, bubbleWidth: nil), .friend(1))
        }
    }

    func testTwoFriendsFlankTheMainPet() {
        let layout = PetRowLayout(friendCount: 2, friendsOnLeft: true, friendsFlank: true)
        let slot = PetRowLayout.friendSlotWidth(petSize: petSize)
        XCTAssertEqual(layout.slotOrder, [1, 0, 2])
        XCTAssertEqual(layout.margins(petSize: petSize, bubbleWidth: nil).left, slot)
        XCTAssertEqual(layout.margins(petSize: petSize, bubbleWidth: nil).right, slot)
        XCTAssertEqual(layout.panelWidth(petSize: petSize, bubbleWidth: nil), petSize + 2 * slot)
        XCTAssertGreaterThanOrEqual(layout.margins(petSize: petSize, bubbleWidth: FloatingPetController.bubbleMinWidth).left, slot)
    }

    func testFlankingIsOnlyForTwoFriends() {
        for count in [0, 1] {
            let layout = PetRowLayout(friendCount: count, friendsOnLeft: true, friendsFlank: true)
            XCTAssertFalse(layout.isFlanking)
            XCTAssertEqual(layout.slotOrder, count == 0 ? [0] : [1, 0])
        }
        XCTAssertEqual(PetRowLayout(friendCount: 1, friendsOnLeft: false, friendsFlank: true).slotOrder, [0, 1])
    }

    func testHitTestInTheFlankingLayoutFindsEachFriend() {
        let layout = PetRowLayout(friendCount: 2, friendsOnLeft: true, friendsFlank: true)
        let mainX = layout.mainXOffset(petSize: petSize, bubbleWidth: nil)
        let slot = PetRowLayout.friendSlotWidth(petSize: petSize)
        XCTAssertEqual(layout.hit(x: mainX - 2, petSize: petSize, bubbleWidth: nil), .friend(0))
        XCTAssertEqual(layout.hit(x: mainX + 10, petSize: petSize, bubbleWidth: nil), .main)
        XCTAssertEqual(layout.hit(x: mainX + petSize + 2, petSize: petSize, bubbleWidth: nil), .friend(1))
        XCTAssertEqual(layout.hit(x: mainX + petSize + slot + 2, petSize: petSize, bubbleWidth: nil), .main)
        XCTAssertEqual(layout.hit(x: mainX - slot - 2, petSize: petSize, bubbleWidth: nil), .main)
    }

    func testSavedHomeSurvivesTheFlankingLayout() {
        let layout = PetRowLayout(friendCount: 2, friendsOnLeft: true, friendsFlank: true)
        for bubble in [false, true] {
            let size = FloatingPetController.panelSize(petSize: petSize, showingBubble: bubble, layout: layout)
            let home = NSPoint(x: 400, y: 300)
            let panel = FloatingPetController.panelOrigin(petOrigin: home, petSize: petSize, panelSize: size,
                                                          layout: layout, showingBubble: bubble)
            XCTAssertEqual(FloatingPetController.petOrigin(panelOrigin: panel, petSize: petSize, panelSize: size,
                                                           layout: layout, showingBubble: bubble), home)
        }
    }

    func testFlankingNeedsRoomOnBothSides() {
        let screen = NSRect(x: 0, y: 0, width: 1000, height: 800)
        XCTAssertTrue(FloatingPetController.friendsFitBothSides(petOrigin: NSPoint(x: 400, y: 0), petSize: petSize,
                                                                visibleFrame: screen))
        XCTAssertFalse(FloatingPetController.friendsFitBothSides(petOrigin: NSPoint(x: 10, y: 0), petSize: petSize,
                                                                 visibleFrame: screen))
        XCTAssertFalse(FloatingPetController.friendsFitBothSides(petOrigin: NSPoint(x: 900, y: 0), petSize: petSize,
                                                                 visibleFrame: screen))
    }

    func testHomeSlotsStandBesideTheRaisedPokemonAndTheAddSlotTakesTheNextFriendsPlace() {
        typealias A = HomePetRow<EmptyView>.Arrangement
        XCTAssertEqual(HomePetRow<EmptyView>.arrangement(friendCount: 0, canAdd: true), A(leading: .add))
        XCTAssertEqual(HomePetRow<EmptyView>.arrangement(friendCount: 0, canAdd: false), A())
        XCTAssertEqual(HomePetRow<EmptyView>.arrangement(friendCount: 1, canAdd: true),
                       A(leading: .friend(0), trailing: .add))
        XCTAssertEqual(HomePetRow<EmptyView>.arrangement(friendCount: 1, canAdd: false), A(leading: .friend(0)))
        XCTAssertEqual(HomePetRow<EmptyView>.arrangement(friendCount: 2, canAdd: true),
                       A(leading: .friend(0), trailing: .friend(1)))
    }

    func testTheThreeSlotsFitOneTileAndTheTextColumnKeepsItsWidth() {
        typealias Row = HomePetRow<EmptyView>
        let ratio = Row.friendSize / Row.mainSize
        XCTAssertGreaterThanOrEqual(ratio, 0.55)
        XCTAssertLessThanOrEqual(ratio, 0.6)
        let slots = 2 * Row.friendSize + Row.mainSize - 2 * Row.slotOverlap
        XCTAssertEqual(slots + 2 * Row.tileInset, Row.tileWidth, "friends and the raised Pokémon share one tile")
        XCTAssertEqual(Row.slotOverlap / Row.friendSize, 0.3, accuracy: 0.03, "a friend tucks about 30% behind the raised Pokémon")
        XCTAssertGreaterThanOrEqual(PopoverMetrics.contentWidth - Row.tileWidth - Row.headerGap, 196)
    }

    func testCrowdBubbleEmojiStaysSmallInsideTheSpriteBox() {
        for size in stride(from: CGFloat(28), through: 384, by: 4) {
            let emoji = CrowdBubble.emojiSize(for: size)
            XCTAssertLessThanOrEqual(emoji + 2 + BubbleMetrics.mini.tailHeight, size, "size \(size)")
            XCTAssertLessThanOrEqual(emoji, 24, "size \(size)")
        }
    }

    func testFriendsStayOnScreen() {
        let screen = NSRect(x: 0, y: 0, width: 1000, height: 800)
        XCTAssertTrue(FloatingPetController.friendsFitLeft(petOrigin: NSPoint(x: 400, y: 0), petSize: petSize,
                                                           friendCount: 2, visibleFrame: screen))
        XCTAssertFalse(FloatingPetController.friendsFitLeft(petOrigin: NSPoint(x: 10, y: 0), petSize: petSize,
                                                            friendCount: 2, visibleFrame: screen))
    }
}

@MainActor
final class PetCrowdTests: XCTestCase {
    private func crowd(order: [Int] = [1, 0, 2], motion: Bool = true) -> PetCrowd {
        let c = PetCrowd(settle: .milliseconds(20), delayProvider: { 3600 })
        c.configure(order: order, motionAllowed: motion, active: false)
        return c
    }

    func testClickTurnsTheOthersTowardItAndHopsThem() {
        let c = crowd()   // screen order: friend1, main, friend2
        c.clicked(slot: 0)
        XCTAssertTrue(c.isFacingRight(1), "the left friend turns right toward the main pet")
        XCTAssertFalse(c.isFacingRight(2), "the right friend already looks left, toward the main pet")
        XCTAssertEqual(c.hopTick(1), 1)
        XCTAssertEqual(c.hopTick(2), 1)
        XCTAssertEqual(c.hopTick(0), 0, "the clicked main pet reacts through the pet-click path, not here")
        XCTAssertNil(c.bubble(0))
    }

    func testFriendClickHopsItAndShowsAHeart() {
        let c = crowd()
        c.clicked(slot: 2)
        XCTAssertEqual(c.hopTick(2), 1)
        XCTAssertEqual(c.bubble(2), PetCrowd.Bubble.heart)
        XCTAssertEqual(c.hopTick(0), 1)
    }

    func testCheerHopsTheFriendsOnly() {
        let c = crowd()
        c.cheer()
        XCTAssertEqual(c.bubble(1), PetCrowd.Bubble.cheer)
        XCTAssertEqual(c.bubble(2), PetCrowd.Bubble.cheer)
        XCTAssertNil(c.bubble(0))
        XCTAssertEqual(c.hopTick(1), 1)
        XCTAssertEqual(c.hopTick(0), 0)
    }

    func testReactionsSettleBackWithoutATimerLoop() async throws {
        let c = crowd()
        c.cheer()
        XCTAssertNotNil(c.bubble(1))
        try await waitUntil("the cheer to settle back") { c.bubble(1) == nil && !c.isFacingRight(1) }
    }

    func testIdlePairsTwoDifferentPokemon() {
        var rng = SeededRNG(seed: 3)
        for _ in 0..<50 {
            let pick = PetCrowd.pickIdle(slots: [1, 0, 2], using: &rng)
            XCTAssertNotNil(pick)
            XCTAssertNotEqual(pick?.pair.0, pick?.pair.1)
        }
        XCTAssertNil(PetCrowd.pickIdle(slots: [0], using: &rng), "a lone pet has nobody to interact with")
    }

    func testIdleDelayIsTwentyToFortySeconds() {
        XCTAssertEqual(PetCrowd.idleDelayRange, 20...40)
    }

    func testReduceMotionKeepsTheCrowdStill() {
        let c = crowd(motion: false)
        c.clicked(slot: 1)
        c.cheer()
        c.fireIdle()
        for slot in 0...2 {
            XCTAssertEqual(c.hopTick(slot), 0)
            XCTAssertFalse(c.isFacingRight(slot))
        }
    }

    func testStopClearsEveryReaction() {
        let c = crowd()
        c.cheer()
        c.stop()
        XCTAssertNil(c.bubble(1))
        XCTAssertFalse(c.isFacingRight(1))
    }

    func testConfigureArmsTheIdleTimerOnlyWhenShownWithFriendsAndMotion() {
        let c = PetCrowd(settle: .milliseconds(20), delayProvider: { 3600 })
        c.configure(order: [0], motionAllowed: true, active: true)
        XCTAssertFalse(c.isIdleLoopRunning, "no friends, no timer")
        c.configure(order: [1, 0], motionAllowed: false, active: true)
        XCTAssertFalse(c.isIdleLoopRunning, "Reduce Motion, no timer")
        c.configure(order: [1, 0], motionAllowed: true, active: false)
        XCTAssertFalse(c.isIdleLoopRunning, "hidden, no timer")
        c.configure(order: [1, 0], motionAllowed: true, active: true)
        XCTAssertTrue(c.isIdleLoopRunning)
        c.configure(order: [1, 0], motionAllowed: true, active: false)
        XCTAssertFalse(c.isIdleLoopRunning, "hiding stops it")
    }

    func testRemovingTheLastFriendStopsTheTimer() {
        let c = PetCrowd(settle: .milliseconds(20), delayProvider: { 3600 })
        c.configure(order: [1, 0], motionAllowed: true, active: true)
        c.configure(order: [0], motionAllowed: true, active: true)
        XCTAssertFalse(c.isIdleLoopRunning)
    }
}
