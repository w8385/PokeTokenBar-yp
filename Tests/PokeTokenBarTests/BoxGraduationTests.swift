import XCTest
@testable import PokeTokenBar

/// A stored line holding an Exp. Share graduates in the Box once it has no step left and its XP is full.
final class BoxGraduationTests: StoredLineHarness {
    static let zardID = "zard"
    static let goodraID = "goodra"
    static let nearID = "near"

    func fullXP(_ mon: MonState) -> Int { mon.phaseThreshold }

    func finalForm(_ id: String, path: [Int], seed: UInt64, short: Int = 0) -> MonState {
        var mon = storedMon(id, path: path, stage: path.count - 1, seed: seed)
        mon.usedAtStage = fullXP(mon) - short
        return mon
    }

    func addNear(to state: inout CompanionState) {
        var near = storedMon(Self.nearID, path: [4, 5, 6], seed: 62)
        near.usedAtStage = 10
        store(near, in: &state, holding: false)
    }

    func graduatedState(short: Int = 0, near: Bool = true) -> CompanionState {
        var state = baseState()
        store(finalForm(Self.zardID, path: [4, 5, 6], seed: 61, short: short), in: &state)
        state.friendEntryIDs = [CompanionState.friendKey(storedLine: Self.zardID)]
        if near { addNear(to: &state) }
        return state
    }

    func graduate(_ store: CompanionStore, _ id: String) -> DexEntry? {
        store.state.dex.first { $0.id == id && !$0.isReleased }
    }

    func testAFullHolderAtItsFinalFormGraduatesAndPassesItsCopyToTheClosestCandidate() async throws {
        let store = try makeStore(graduatedState())
        let active = store.state.active
        await store.checkExpShareEvolution()

        XCTAssertNil(store.state.storedLines[Self.zardID])
        let record = try XCTUnwrap(graduate(store, Self.zardID))
        XCTAssertEqual(record.finalID, 6)
        XCTAssertEqual(record.chainOrder, [4, 5, 6])
        XCTAssertEqual(record.profile?.level, 100)
        XCTAssertEqual(store.state.dex.filter { $0.id == Self.zardID }.count, 1, "the released record is replaced")
        XCTAssertTrue(store.state.collectedFinals.contains("4:6"))
        XCTAssertEqual(store.state.friendEntryIDs, [Self.zardID], "it keeps its friend slot")
        XCTAssertEqual(store.boxIndividual(id: Self.zardID)?.role, .friend)
        XCTAssertEqual(store.friendSubjects.map(\.entryID), [Self.zardID])
        XCTAssertEqual(store.state.expShareHolders, [Self.nearID])
        XCTAssertEqual(store.itemCount(.expShare), 0)
        XCTAssertNil(store.justGraduated, "Home belongs to the raised Pokémon")
        XCTAssertEqual(store.state.active?.profile?.instanceID, active?.profile?.instanceID)
        XCTAssertEqual(store.state.active?.usedAtStage, active?.usedAtStage)
        let name = "#6"
        XCTAssertEqual(store.latestEvent?.text,
                       [store.l.boxGraduatedLine(name), store.l.expShareMovedLine(name, to: "#4")].joined(separator: "\n"))
    }

    func testWithNoCandidateTheGraduatesCopyGoesBackToTheBag() async throws {
        let store = try makeStore(graduatedState(near: false))
        await store.checkExpShareEvolution()
        XCTAssertNotNil(graduate(store, Self.zardID))
        XCTAssertEqual(store.state.expShareHolders, [])
        XCTAssertEqual(store.itemCount(.expShare), 1)
    }

    func testWithMoveOnOffItStillGraduatesAndKeepsItsCopy() async throws {
        let store = try makeStore(graduatedState())
        store.autoMoveOn = false
        await store.checkExpShareEvolution()
        XCTAssertNotNil(graduate(store, Self.zardID))
        XCTAssertEqual(store.state.expShareHolders, [Self.zardID])
        XCTAssertEqual(store.latestEvent?.text, store.l.boxGraduatedLine("#6"))
    }

    func testAHolderShortOfXPStaysInTheBoxAndKeepsItsCopyEvenAtLevel100() async throws {
        var state = graduatedState(short: 1)
        state.storedLines[Self.zardID]?.mon.profile?.level = 100
        let store = try makeStore(state)
        await store.checkExpShareEvolution()
        XCTAssertNotNil(store.state.storedLines[Self.zardID])
        XCTAssertNil(graduate(store, Self.zardID))
        XCTAssertEqual(store.state.expShareHolders, [Self.zardID], "it still needs XP to graduate")
    }

    func testAHolderWithAStepLeftDoesNotGraduate() async throws {
        var state = baseState()
        var charmeleon = storedMon("meleon", path: [4, 5, 6], stage: 1, seed: 63)
        charmeleon.usedAtStage = fullXP(charmeleon)
        store(charmeleon, in: &state)
        var munchlax = storedMon("munch", path: [446, 143], seed: 64)
        munchlax.usedAtStage = fullXP(munchlax)
        store(munchlax, in: &state)
        let store = try makeStore(state)
        await store.checkExpShareEvolution()
        XCTAssertEqual(try storedMon(store, "meleon").currentID, 6, "it evolves and starts its last stage")
        XCTAssertEqual(try storedMon(store, "munch").currentID, 446, "its step waits on the player")
        XCTAssertNil(graduate(store, "meleon"))
        XCTAssertNil(graduate(store, "munch"))
    }

    func testADittoInDisguiseDoesNotGraduate() async throws {
        var state = baseState()
        var ditto = finalForm("ditto", path: [4, 5, 6], seed: 65)
        ditto.dittoDisguise = 4
        store(ditto, in: &state)
        let store = try makeStore(state)
        await store.checkExpShareEvolution()
        XCTAssertNotNil(store.state.storedLines["ditto"])
        XCTAssertNil(graduate(store, "ditto"))
    }

    func testAnEverstoneStopsTheStepButNotTheGraduation() async throws {
        var state = graduatedState()
        var charmeleon = storedMon("meleon", path: [4, 5, 6], stage: 1, seed: 63)
        charmeleon.usedAtStage = fullXP(charmeleon)
        store(charmeleon, in: &state)
        state.heldItems[Self.zardID] = ItemKind.everstone.rawValue
        state.heldItems["meleon"] = ItemKind.everstone.rawValue
        let store = try makeStore(state)
        await store.checkExpShareEvolution()
        XCTAssertNotNil(graduate(store, Self.zardID))
        XCTAssertEqual(store.heldItem(of: Self.zardID), .everstone)
        XCTAssertEqual(try storedMon(store, "meleon").currentID, 5)
        XCTAssertEqual(store.state.expShareHolders, ["meleon", Self.nearID], "the graduate's copy still moves on")
    }

    func testTwoHoldersFinishingTogetherGraduateInOneNotice() async throws {
        var state = graduatedState()
        store(finalForm(Self.goodraID, path: [704, 705, 706], seed: 66), in: &state)
        let store = try makeStore(state)
        let before = store.latestEvent?.seq ?? 0
        await store.checkExpShareEvolution()
        XCTAssertNotNil(graduate(store, Self.zardID))
        XCTAssertNotNil(graduate(store, Self.goodraID))
        XCTAssertEqual(store.latestEvent?.seq, before + 1)
        let text = try XCTUnwrap(store.latestEvent?.text)
        XCTAssertTrue(text.contains(store.l.boxGraduatedLine("#6")), text)
        XCTAssertTrue(text.contains(store.l.boxGraduatedLine("#706")), text)
        XCTAssertEqual(store.state.expShareHolders, [Self.nearID])
        XCTAssertEqual(store.itemCount(.expShare), 1)
    }

    func testASavedHolderPastItsGraduationPointGraduatesOnTheFirstPeriodicCheck() async throws {
        var state = graduatedState()
        state.storedLines[Self.zardID]?.mon.usedAtStage *= 3
        let data = try JSONEncoder().encode(state)
        let store = try makeStore(try JSONDecoder().decode(CompanionState.self, from: data))
        XCTAssertNotNil(store.state.storedLines[Self.zardID], "loading changes nothing")
        store.checkEvolutionGate()
        try await waitUntil("the stored holder to graduate") { self.graduate(store, Self.zardID) != nil }
        XCTAssertNil(store.state.storedLines[Self.zardID])
    }

    func testASavedFullFinalFormWhoseCopyWasPassedOnGraduatesOnTheFirstPeriodicCheck() async throws {
        var state = graduatedState(near: false)
        state.storedLines[Self.zardID]?.mon.profile?.level = 100
        state.expShareHolders = []
        state.inventory[ItemKind.expShare.rawValue] = 1
        let store = try makeStore(state)
        store.checkEvolutionGate()
        try await waitUntil("the stored line to graduate") { self.graduate(store, Self.zardID) != nil }
        XCTAssertNil(store.state.storedLines[Self.zardID])
        XCTAssertEqual(store.itemCount(.expShare), 1)
    }

    func testAttachingACopyToAFullFinalFormGraduatesIt() async throws {
        var state = graduatedState(near: false)
        state.expShareHolders = []
        state.inventory[ItemKind.expShare.rawValue] = 1
        let store = try makeStore(state)
        XCTAssertTrue(store.attachExpShare(to: Self.zardID))
        try await waitUntil("the stored holder to graduate") { self.graduate(store, Self.zardID) != nil }
        try await waitUntil("its copy to go back to the bag") { store.itemCount(.expShare) == 1 }
    }

    func testAFinalFormGraduateHolderAtLevel100PassesItsCopyWithoutGraduatingAgain() async throws {
        var state = baseState()
        var profile = PokemonProfile.generate(seed: 67, instanceID: "charizard")
        profile.level = 100
        state.dex.append(DexEntry(id: "charizard", baseID: 4, finalID: 6, chainOrder: [4, 5, 6], rarity: .common,
                                  caughtAt: Date(timeIntervalSince1970: 4_000), profile: profile))
        state.expShareHolders = ["charizard"]
        state.heldItems["charizard"] = ItemKind.everstone.rawValue
        addNear(to: &state)
        let store = try makeStore(state)
        let records = store.state.dex.count
        await store.checkExpShareEvolution()
        XCTAssertEqual(store.state.dex.count, records)
        XCTAssertEqual(store.state.expShareHolders, [Self.nearID], "an Everstone does nothing on a final form")
        XCTAssertEqual(store.latestEvent?.text, store.l.expShareMovedLine("#6", to: "#4"))
    }
}
