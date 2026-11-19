import SwiftUI
import XCTest
@testable import PokeTokenBar

/// A raised Pokémon whose full XP waits on the player moves on after 30 unseen minutes.
final class StuckMoveOnTests: StoredLineHarness {
    static let munchID = "munch"
    static let nearID = "near"
    static let farID = "far"

    func fullXP(_ mon: MonState) -> Int { mon.phaseThreshold }

    func munchlax(short: Int = 0) -> MonState {
        var mon = storedMon(Self.munchID, path: [446, 143])
        mon.usedAtStage = fullXP(mon) - short
        return mon
    }

    func stuckState(short: Int = 0) -> CompanionState {
        var state = baseState()
        state.active = munchlax(short: short)
        return state
    }

    func addCandidates(to state: inout CompanionState) {
        var near = storedMon(Self.nearID, path: [4, 5, 6], seed: 31)
        near.usedAtStage = fullXP(near) - 100
        store(near, in: &state, holding: false)
        store(storedMon(Self.farID, path: [704, 705, 706], seed: 32), in: &state, holding: false)
    }

    func loadedStore(_ state: CompanionState) async throws -> CompanionStore {
        let store = try makeStore(state)
        feed(store, 0)
        try await waitUntil("the raised line to load") { store.currentLine != nil }
        return store
    }

    func waitOutTheDelay(_ store: CompanionStore) {
        store.checkEvolutionGate()
        now += CompanionStore.stuckMoveOnDelay
        store.checkEvolutionGate()
    }

    func testAPetsStuckLineGoesToTheBoxAndAnEggStartsAfterThirtyUnseenMinutesWhenNoOneElseNeedsXP() async throws {
        var state = stuckState()
        state.inventory[ItemKind.expShare.rawValue] = 1
        let store = try await loadedStore(state)
        store.checkEvolutionGate()
        XCTAssertEqual(store.state.stuckWatch?.id, Self.munchID)
        now += CompanionStore.stuckMoveOnDelay - 1
        store.checkEvolutionGate()
        XCTAssertEqual(store.state.active?.profile?.instanceID, Self.munchID, "not before 30 minutes")

        now += 1
        store.checkEvolutionGate()
        XCTAssertTrue(store.isEgg)
        XCTAssertNil(store.state.stuckWatch)
        let stored = try storedMon(store, Self.munchID)
        XCTAssertEqual(stored.usedAtStage, fullXP(stored), "its progress goes along")
        XCTAssertEqual(store.state.friendEntryIDs, [CompanionState.friendKey(storedLine: Self.munchID)])
        XCTAssertEqual(store.state.expShareHolders, [], "the bag copy has no one to go to")
        XCTAssertEqual(store.itemCount(.expShare), 1)
    }

    func testOpeningThePopoverRestartsTheWaitAndNothingMovesWhileItIsOpen() async throws {
        let store = try await loadedStore(stuckState())
        store.checkEvolutionGate()
        now += 10 * 60
        XCTAssertEqual(store.moveOnStatus?.minutes, 20)
        XCTAssertEqual(store.moveOnStatus?.next, .egg)

        store.setAttended(true)
        XCTAssertEqual(store.moveOnStatus?.minutes, 30)
        now += CompanionStore.stuckMoveOnDelay * 2
        store.checkEvolutionGate()
        XCTAssertEqual(store.state.active?.profile?.instanceID, Self.munchID, "open popover")

        store.setAttended(false)
        now += CompanionStore.stuckMoveOnDelay - 60
        store.checkEvolutionGate()
        XCTAssertEqual(store.state.active?.profile?.instanceID, Self.munchID, "the wait restarted on close")
        now += 60
        store.checkEvolutionGate()
        XCTAssertTrue(store.isEgg)
    }

    func testAStepThatOnlyWaitsForTheClockNeverMovesOn() async throws {
        var state = baseState()
        var riolu = storedMon("riolu", path: [447, 448])
        riolu.usedAtStage = fullXP(riolu)
        riolu.evolution.pets = 30
        state.active = riolu
        let night = DayPeriod.at(now) == .night ? now : now + DayPeriod.length
        now = night
        let store = try await loadedStore(state)
        store.checkEvolutionGate()
        now += 6 * DayPeriod.length
        XCTAssertEqual(DayPeriod.at(now), .night)
        store.checkEvolutionGate()
        XCTAssertEqual(store.state.active?.profile?.instanceID, "riolu")
        XCTAssertNil(store.state.stuckWatch)
        XCTAssertNil(store.moveOnStatus)
    }

    func testKeepWaitingStopsItForThatPokemon() async throws {
        let store = try await loadedStore(stuckState())
        store.checkEvolutionGate()
        store.keepWaitingOnStuck()
        XCTAssertEqual(store.state.keepWaiting, [Self.munchID: 446])
        XCTAssertNil(store.moveOnStatus)
        waitOutTheDelay(store)
        XCTAssertEqual(store.state.active?.profile?.instanceID, Self.munchID)
        XCTAssertNil(store.state.stuckWatch)
    }

    func testTheSettingOffStopsItAndIsRemembered() async throws {
        let store = try await loadedStore(stuckState())
        store.checkEvolutionGate()
        store.autoMoveOn = false
        XCTAssertEqual(store.defaults.object(forKey: CompanionStore.autoMoveOnKey) as? Bool, false)
        waitOutTheDelay(store)
        XCTAssertEqual(store.state.active?.profile?.instanceID, Self.munchID)
        XCTAssertNil(store.state.stuckWatch)
    }

    func testAPokemonShortOfXPNeverMovesOn() async throws {
        let store = try await loadedStore(stuckState(short: 1))
        waitOutTheDelay(store)
        XCTAssertEqual(store.state.active?.profile?.instanceID, Self.munchID)
        XCTAssertNil(store.state.stuckWatch)
    }

    func testAStuckRaisedGraduateGoesBackToTheGraduatesAndTheParkedLineResumes() async throws {
        var state = baseState()
        state.dex.append(graduate("munch-grad", species: 446, seed: 41, caught: 4_000))
        state.raisedEntryID = "munch-grad"
        state.parkedSpentTokens = 0
        let store = try makeStore(state)
        await store.checkRaisedGraduateEvolution()
        let parked = try XCTUnwrap(store.parkedLineName)
        XCTAssertEqual(store.moveOnStatus?.next, .resume(parked))
        waitOutTheDelay(store)
        XCTAssertNil(store.state.raisedEntryID)
        XCTAssertEqual(store.state.active?.profile?.instanceID, Self.lineID)
        XCTAssertTrue(store.state.dex.contains { $0.id == "munch-grad" && !$0.isReleased })
        XCTAssertEqual(store.state.friendEntryIDs, ["munch-grad"])
    }

    func testTheClosestStoredCandidateIsRaisedAndTheBagCopyGoesStraightToTheNextClosest() async throws {
        var state = stuckState()
        addCandidates(to: &state)
        state.inventory[ItemKind.expShare.rawValue] = 1
        let store = try await loadedStore(state)
        XCTAssertEqual(store.moveOnStatus?.next, .raise(store.candidateName(Self.nearID)))
        waitOutTheDelay(store)
        XCTAssertEqual(store.state.active?.profile?.instanceID, Self.nearID)
        XCTAssertNotNil(store.state.storedLines[Self.munchID])
        XCTAssertEqual(store.state.friendEntryIDs, [CompanionState.friendKey(storedLine: Self.munchID)])
        XCTAssertEqual(store.state.expShareHolders, [Self.farID], "never on the stuck one")
        XCTAssertEqual(store.itemCount(.expShare), 0)
    }

    func testTheWatchAndKeepWaitingSurviveARoundTripAndOldOrBrokenSavesDecode() throws {
        var state = stuckState()
        state.stuckWatch = StuckWatch(id: Self.munchID, since: now)
        state.keepWaiting = ["other": 4]
        let data = try JSONEncoder().encode(state)
        let roundTrip = try JSONDecoder().decode(CompanionState.self, from: data)
        XCTAssertEqual(roundTrip.stuckWatch, state.stuckWatch)
        XCTAssertEqual(roundTrip.keepWaiting, ["other": 4])

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["stuckWatch"] = nil
        json["keepWaiting"] = nil
        let old = try JSONDecoder().decode(CompanionState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.stuckWatch)
        XCTAssertEqual(old.keepWaiting, [:])
        XCTAssertEqual(old.active?.profile?.instanceID, Self.munchID)

        json["stuckWatch"] = 7
        json["keepWaiting"] = "x"
        let broken = try JSONDecoder().decode(CompanionState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(broken.stuckWatch)
        XCTAssertEqual(broken.keepWaiting, [:])
        XCTAssertEqual(broken.active?.profile?.instanceID, Self.munchID)
    }
}

/// An Exp. Share holder that can't use more XP passes its copy on without waiting.
final class ExpShareMoveOnTests: StoredLineHarness {
    static let idleID = "box-munch"
    static let nearID = "near"

    func idleHolderState() -> CompanionState {
        var state = baseState()
        var munch = storedMon(Self.idleID, path: [446, 143], seed: 51)
        munch.usedAtStage = munch.phaseThreshold
        store(munch, in: &state, holding: true)
        return state
    }

    func addNear(to state: inout CompanionState, holding: Bool) {
        var near = storedMon(Self.nearID, path: [4, 5, 6], seed: 52)
        near.usedAtStage = 10
        store(near, in: &state, holding: holding)
        store(storedMon("far", path: [704, 705, 706], seed: 53), in: &state, holding: false)
    }

    func testAFullHolderWaitingOnPetsHandsItsCopyToTheClosestCandidate() async throws {
        var state = idleHolderState()
        addNear(to: &state, holding: false)
        let store = try makeStore(state)
        await store.checkExpShareEvolution()
        XCTAssertEqual(store.state.expShareHolders, [Self.nearID])
        XCTAssertEqual(store.itemCount(.expShare), 0)
    }

    func testWithNoCandidateTheCopyGoesBackToTheBag() async throws {
        let store = try makeStore(idleHolderState())
        await store.checkExpShareEvolution()
        XCTAssertEqual(store.state.expShareHolders, [])
        XCTAssertEqual(store.itemCount(.expShare), 1)
    }

    func testTheRaisedPokemonAndOtherHoldersAreNeverTargets() async throws {
        var state = idleHolderState()
        addNear(to: &state, holding: true)
        var profile = PokemonProfile.generate(seed: 54, instanceID: "slig")
        profile.level = 30
        state.dex.append(DexEntry(id: "slig", baseID: 704, finalID: 705, chainOrder: [704, 705], rarity: .common,
                                  caughtAt: Date(timeIntervalSince1970: 5_000), profile: profile))
        let sliggooThreshold = PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 1)
        var progress = EvolutionProgress()
        progress.graduateXP = sliggooThreshold - 1
        state.graduateEvolution["slig"] = progress
        state.raisedEntryID = "slig"
        state.parkedSpentTokens = 0
        let store = try makeStore(state)
        let closest = CompanionStore.closestCandidate(store.moveOnCandidates(), excluding: [Self.idleID])
        XCTAssertEqual(closest?.id, "slig", "the raised one would be the closest")
        await store.checkExpShareEvolution()
        XCTAssertEqual(store.state.expShareHolders, [Self.nearID, "far"])
        XCTAssertEqual(store.itemCount(.expShare), 0)
    }

    func testAFullHolderWaitingForAFriendPassesItsCopyOn() async throws {
        var state = baseState()
        var mantyke = storedMon("mantyke", path: [458, 226], seed: 55)
        mantyke.usedAtStage = mantyke.phaseThreshold
        store(mantyke, in: &state, holding: true)
        addNear(to: &state, holding: false)
        let store = try makeStore(state)
        await store.checkExpShareEvolution()
        XCTAssertEqual(store.state.expShareHolders, [Self.nearID])
    }

    func testAHolderThatStillNeedsXPKeepsItsCopy() async throws {
        var state = baseState()
        store(storedMon(Self.idleID, path: [446, 143], seed: 51), in: &state, holding: true)
        addNear(to: &state, holding: false)
        let store = try makeStore(state)
        await store.checkExpShareEvolution()
        XCTAssertEqual(store.state.expShareHolders, [Self.idleID])
    }
}

final class MoveOnCandidateTests: XCTestCase {
    func testTheLeastXPLeftWinsThenTheOneBoxedLongest() {
        let old = Date(timeIntervalSince1970: 1_000)
        let new = Date(timeIntervalSince1970: 2_000)
        let candidates = [
            MoveOnCandidate(id: "done", xpLeft: 0, boxedAt: old),
            MoveOnCandidate(id: "far", xpLeft: 500, boxedAt: old),
            MoveOnCandidate(id: "near-new", xpLeft: 100, boxedAt: new),
            MoveOnCandidate(id: "near-old", xpLeft: 100, boxedAt: old),
        ]
        XCTAssertEqual(CompanionStore.closestCandidate(candidates)?.id, "near-old")
        XCTAssertEqual(CompanionStore.closestCandidate(candidates, excluding: ["near-old"])?.id, "near-new")
        XCTAssertEqual(CompanionStore.closestCandidate(candidates, excluding: ["near-old", "near-new"])?.id, "far")
        XCTAssertNil(CompanionStore.closestCandidate(Array(candidates.prefix(1))), "nothing left to earn")
    }

    func testOnlyAStepThePlayerMustActOnWaits() {
        var ctx = EvolutionContext()
        ctx.stageThreshold = 100
        ctx.stageXP = 100
        let pets = EvolutionRule(species: 143, covers: [], original: [], paths: [[.pets(30)]])
        let rain = EvolutionRule(species: 706, covers: [], original: [], paths: [[.tokenRain], [.longStage(percent: 200)]])
        let dusk = EvolutionRule(species: 448, covers: [], original: [], paths: [[.pets(30), .time(.day)]])
        ctx.period = .night
        XCTAssertTrue(pets.waitsOnPlayer(in: ctx))
        XCTAssertFalse(rain.waitsOnPlayer(in: ctx))
        XCTAssertEqual(rain.stageXPLeft(in: ctx), 100)
        XCTAssertTrue(dusk.waitsOnPlayer(in: ctx), "pets unmet")
        ctx.progress.pets = 30
        XCTAssertFalse(dusk.waitsOnPlayer(in: ctx), "only the clock is left")
    }
}

@MainActor
final class MoveOnCountdownLayoutTests: XCTestCase {
    func testTheCountdownLineIsNeverTruncatedInEveryLanguage() {
        for language in AppLanguage.allCases {
            let l = L(language)
            let needs = [EvolutionRequirement.pets(30), .holds(.expShare)]
                .map { l.evolutionRequirementText($0, speciesName: { _ in "Fletchinder" }) }
                .joined(separator: " + ")
            let text = l.moveOnCountdown(needs, minutes: 30, next: .raise("Fletchinder"), toGraduates: true)
            let button = LayoutMeasure.size(Button(l.keepWaiting) {}.buttonStyle(.bordered).controlSize(.mini).fixedSize())
            for width: CGFloat in [180, 240, PopoverMetrics.contentWidth] {
                let textWidth = width - button.width - 6 - 4
                let wrapped = LayoutMeasure.size(Text(text).font(.caption2), width: textWidth).height
                let row = LayoutMeasure.size(MoveOnCountdownRow(text: text, keepWaiting: l.keepWaiting) {}, width: width)
                XCTAssertGreaterThanOrEqual(row.height, wrapped - 0.5, "\(language) at \(width)pt")
                XCTAssertLessThanOrEqual(row.width, width + 0.5, "\(language) at \(width)pt")
            }
        }
    }
}
