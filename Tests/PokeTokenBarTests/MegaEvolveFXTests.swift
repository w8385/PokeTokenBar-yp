import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct FXNoProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

final class MegaEvolveTimelineTests: XCTestCase {
    func testTheBaseChargesUpThenTheMegaAppearsUnderTheFlash() {
        let start = MegaEvolveFX.frame(at: 0)
        XCTAssertFalse(start.showsMega)
        XCTAssertEqual(start.glow, 0)
        XCTAssertEqual(start.flash, 0)
        XCTAssertEqual(start.scale, 1)

        let charged = MegaEvolveFX.frame(at: MegaEvolveFX.swapTime - 0.001)
        XCTAssertFalse(charged.showsMega)
        XCTAssertGreaterThan(charged.glow, 0.95)
        XCTAssertGreaterThan(charged.flash, 0.95, "the swap happens at the flash peak")

        let swapped = MegaEvolveFX.frame(at: MegaEvolveFX.swapTime)
        XCTAssertTrue(swapped.showsMega)
        XCTAssertGreaterThan(swapped.flash, 0.95)
    }

    func testTheSwapHappensOnceAndTheEffectEndsAtRest() {
        let samples = stride(from: 0.0, through: MegaEvolveFX.duration, by: 0.01).map(MegaEvolveFX.frame(at:))
        let swapIndex = samples.firstIndex { $0.showsMega }
        XCTAssertNotNil(swapIndex)
        XCTAssertTrue(samples[..<swapIndex!].allSatisfy { !$0.showsMega })
        XCTAssertTrue(samples[swapIndex!...].allSatisfy(\.showsMega))

        let end = MegaEvolveFX.frame(at: MegaEvolveFX.duration)
        XCTAssertEqual(end.scale, 1)
        XCTAssertEqual(end.glow, 0, accuracy: 0.0001)
        XCTAssertEqual(end.flash, 0, accuracy: 0.0001)
        XCTAssertNil(end.ring)
        XCTAssertGreaterThan(MegaEvolveFX.duration, 1.2)
        XCTAssertLessThan(MegaEvolveFX.duration, 1.6)
    }

    func testTheRingPulsesOutAndFadesBeforeTheEnd() {
        XCTAssertNil(MegaEvolveFX.frame(at: 0.2).ring)
        let early = try? XCTUnwrap(MegaEvolveFX.frame(at: 0.5).ring)
        let late = try? XCTUnwrap(MegaEvolveFX.frame(at: 1.0).ring)
        XCTAssertNotNil(early)
        XCTAssertNotNil(late)
        XCTAssertGreaterThan(late!.scale, early!.scale)
        XCTAssertLessThanOrEqual(late!.scale, 1.15)
        XCTAssertNil(MegaEvolveFX.frame(at: 1.3).ring)
    }
}

final class MegaEvolveStageModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func event(_ id: Int = 1, _ kind: MegaEvolveEvent.Kind = .equip, sprite: Int = 10034,
                       ago: TimeInterval = 0) -> MegaEvolveEvent {
        MegaEvolveEvent(id: id, kind: kind, instanceID: "zard", megaSpriteID: sprite, at: now.addingTimeInterval(-ago))
    }

    func testAFreshEquipOfTheDisplayedHolderPlaysTheEffect() {
        var model = MegaEvolveStageModel()
        model.megaChanged(from: nil, to: 10034, event: event(), now: now, reduceMotion: false)

        XCTAssertTrue(model.isRunning)
        let charging = model.render(at: now.addingTimeInterval(0.1), megaSpriteID: 10034)
        XCTAssertEqual(charging.layers.map(\.megaID), [nil, 10034], "the Mega layer is mounted from the start")
        XCTAssertEqual(charging.layers.map(\.opacity), [1, 0], "but only the base sprite shows while it charges")
        let after = model.render(at: now.addingTimeInterval(MegaEvolveFX.swapTime + 0.05), megaSpriteID: 10034)
        XCTAssertEqual(after.layers.map(\.megaID), [10034])
        XCTAssertNotNil(after.fx)
    }

    func testTheMegaLayerKeepsItsIdentityAcrossTheSwap() {
        var model = MegaEvolveStageModel()
        model.megaChanged(from: nil, to: 10034, event: event(), now: now, reduceMotion: false)
        let before = model.render(at: now.addingTimeInterval(MegaEvolveFX.swapTime - 0.05), megaSpriteID: 10034)
        let after = model.render(at: now.addingTimeInterval(MegaEvolveFX.swapTime + 0.05), megaSpriteID: 10034)
        XCTAssertEqual(before.layers.last?.id, after.layers.last?.id,
                       "a new identity would remount the sprite and restart its image load at the swap")
    }

    func testSwitchingToAnotherSubjectMidEffectCancelsTheEffect() {
        var model = MegaEvolveStageModel()
        model.megaChanged(from: nil, to: 10034, event: event(), now: now, reduceMotion: false)
        XCTAssertTrue(model.isRunning)

        model.megaChanged(from: 10034, to: nil, event: event(), now: now.addingTimeInterval(0.3), reduceMotion: false)
        XCTAssertFalse(model.isRunning, "the used event cannot explain this change, so the new subject must not transform")
        XCTAssertEqual(model.render(at: now.addingTimeInterval(0.4), megaSpriteID: nil).layers.map(\.megaID), [nil])
    }

    func testTheEffectEndsIdleAndLeavesJustTheMega() {
        var model = MegaEvolveStageModel()
        model.megaChanged(from: nil, to: 10034, event: event(), now: now, reduceMotion: false)
        let late = model.render(at: now.addingTimeInterval(MegaEvolveFX.duration + 0.01), megaSpriteID: 10034)
        XCTAssertEqual(late, MegaEvolveRender(layers: [.init(megaID: 10034, opacity: 1)], fx: nil))

        model.finish()
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.phase, .idle)
    }

    func testASpriteChangeWithNoEventDoesNotPlay() {
        var model = MegaEvolveStageModel()
        model.megaChanged(from: nil, to: 10034, event: nil, now: now, reduceMotion: false)
        XCTAssertFalse(model.isRunning)
    }

    func testAHolderThatIsNotOnScreenNeverPlays() {
        var model = MegaEvolveStageModel()
        model.megaChanged(from: nil, to: 10033, event: event(sprite: 10034), now: now, reduceMotion: false)
        XCTAssertFalse(model.isRunning, "the event was for another Mega; this surface's sprite change is not it")
        model.megaChanged(from: nil, to: 10033, event: event(sprite: 10033), now: now, reduceMotion: false)
        XCTAssertTrue(model.isRunning, "control: the matching event does play")
    }

    func testAStaleEventDoesNotPlay() {
        var model = MegaEvolveStageModel()
        model.megaChanged(from: nil, to: 10034, event: event(ago: MegaEvolveFX.eventWindow + 0.1), now: now,
                          reduceMotion: false)
        XCTAssertFalse(model.isRunning)
    }

    func testTheSameEventPlaysOnceOnASurfaceEvenIfItRedraws() {
        var model = MegaEvolveStageModel()
        let equip = event()
        model.megaChanged(from: nil, to: 10034, event: equip, now: now, reduceMotion: false)
        model.finish()
        model.megaChanged(from: nil, to: 10034, event: equip, now: now.addingTimeInterval(0.5), reduceMotion: false)
        XCTAssertFalse(model.isRunning)
        model.mounted(megaSpriteID: 10034, event: equip, now: now.addingTimeInterval(0.5), reduceMotion: false)
        XCTAssertFalse(model.isRunning)
    }

    func testASurfaceThatAppearsRightAfterTheEquipPlaysButNotLater() {
        var fresh = MegaEvolveStageModel()
        fresh.mounted(megaSpriteID: 10034, event: event(ago: 0.2), now: now, reduceMotion: false)
        XCTAssertTrue(fresh.isRunning)

        var relaunch = MegaEvolveStageModel()
        relaunch.mounted(megaSpriteID: 10034, event: nil, now: now, reduceMotion: false)
        XCTAssertFalse(relaunch.isRunning, "a relaunch has no event")

        var late = MegaEvolveStageModel()
        late.mounted(megaSpriteID: 10034, event: event(ago: MegaEvolveFX.mountWindow + 0.1), now: now, reduceMotion: false)
        XCTAssertFalse(late.isRunning)
    }

    func testReduceMotionCrossfadesInsteadOfPlayingTheEffect() {
        var model = MegaEvolveStageModel()
        model.megaChanged(from: nil, to: 10034, event: event(), now: now, reduceMotion: true)

        let middle = model.render(at: now.addingTimeInterval(MegaEvolveFX.crossfadeDuration / 2), megaSpriteID: 10034)
        XCTAssertEqual(middle.layers.map(\.megaID), [nil, 10034])
        XCTAssertNil(middle.fx, "no glow, ring or flash")
        XCTAssertEqual(middle.layers.map(\.opacity).reduce(0, +), 1, accuracy: 0.0001)
        let done = model.render(at: now.addingTimeInterval(MegaEvolveFX.crossfadeDuration + 0.01), megaSpriteID: 10034)
        XCTAssertEqual(done.layers.map(\.megaID), [10034])
    }

    func testTheScheduleStopsWhenThePhaseEndsNotWhenTheLongestPhaseWould() {
        var effect = MegaEvolveStageModel()
        effect.megaChanged(from: nil, to: 10034, event: event(), now: now, reduceMotion: false)
        XCTAssertEqual(effect.runDuration, MegaEvolveFX.duration)

        var reduced = MegaEvolveStageModel()
        reduced.megaChanged(from: nil, to: 10034, event: event(), now: now, reduceMotion: true)
        XCTAssertEqual(reduced.runDuration, MegaEvolveFX.crossfadeDuration)

        var unequip = MegaEvolveStageModel()
        unequip.megaChanged(from: 10034, to: nil, event: event(2, .unequip), now: now, reduceMotion: false)
        XCTAssertEqual(unequip.runDuration, MegaEvolveFX.crossfadeDuration)

        XCTAssertEqual(MegaEvolveStageModel().runDuration, 0)
    }

    func testUnequipFadesTheMegaBackToTheBaseSprite() {
        var model = MegaEvolveStageModel()
        model.megaChanged(from: 10034, to: nil, event: event(2, .unequip), now: now, reduceMotion: false)

        XCTAssertTrue(model.isRunning)
        let middle = model.render(at: now.addingTimeInterval(0.1), megaSpriteID: nil)
        XCTAssertEqual(middle.layers.map(\.megaID), [10034, nil])
        XCTAssertNil(middle.fx)
    }

    func testLosingTheMegaWithoutAnUnequipEventDoesNotFade() {
        var model = MegaEvolveStageModel()
        model.megaChanged(from: 10034, to: nil, event: event(2, .equip), now: now, reduceMotion: false)
        XCTAssertFalse(model.isRunning, "the surface switched to a species with no Mega; nothing was unequipped")
        model.megaChanged(from: 10034, to: nil, event: nil, now: now, reduceMotion: false)
        XCTAssertFalse(model.isRunning)
    }

    func testSwappingOneStoneForAnotherCrossfadesBetweenTheTwoMegas() {
        var model = MegaEvolveStageModel()
        model.megaChanged(from: 10034, to: 10035, event: event(3, sprite: 10035), now: now, reduceMotion: false)
        let middle = model.render(at: now.addingTimeInterval(0.1), megaSpriteID: 10035)
        XCTAssertEqual(middle.layers.map(\.megaID), [10034, 10035])
    }
}

@MainActor
final class MegaEvolveEventTests: XCTestCase {
    private func entry(_ finalID: Int, id: String) -> DexEntry {
        var entry = DexEntry(baseID: finalID, finalID: finalID, chainOrder: [finalID], rarity: .common, caughtAt: nil,
                             profile: PokemonProfile.generate(seed: 7, instanceID: id))
        entry.id = id
        return entry
    }

    private let charizardX = MegaStone.stone(slug: "charizardite-x")!
    private let charizardY = MegaStone.stone(slug: "charizardite-y")!

    private func store(inventory: [String: Int] = [:], held: [String: String] = [:]) throws -> CompanionStore {
        var state = CompanionState()
        state.installBaselineSet = true
        state.dex = [entry(6, id: "zard"), entry(25, id: "pikachu")]
        state.inventory = inventory
        state.heldItems = held
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mega-fx-\(UUID().uuidString).json")
        try JSONEncoder().encode(state).write(to: url)
        return CompanionStore(provider: FXNoProvider(), clock: { Date(timeIntervalSince1970: 1_700_000_000) },
                              fileURL: url, rng: SeededRNG(seed: 1))
    }

    func testEquippingTheMatchingStoneAnnouncesTheEvolution() throws {
        let store = try store(inventory: [charizardX.inventoryKey: 1])
        XCTAssertNil(store.megaEvolveEvent)

        XCTAssertTrue(store.equip(charizardX, to: "zard"))

        let event = try XCTUnwrap(store.megaEvolveEvent)
        XCTAssertEqual(event.kind, .equip)
        XCTAssertEqual(event.instanceID, "zard")
        XCTAssertEqual(event.megaSpriteID, charizardX.spriteID)
    }

    func testAHolderLoadedWithItsStoneAlreadyOnAnnouncesNothing() throws {
        let store = try store(held: ["zard": charizardX.inventoryKey])
        XCTAssertEqual(store.megaSpriteID(instanceID: "zard", speciesID: 6), charizardX.spriteID)
        XCTAssertNil(store.megaEvolveEvent, "a relaunch must not replay the effect")
    }

    func testAStoneOnTheWrongSpeciesAnnouncesNothing() throws {
        let store = try store(inventory: [charizardX.inventoryKey: 1])
        XCTAssertTrue(store.equip(charizardX, to: "pikachu"))
        XCTAssertNil(store.megaEvolveEvent)
    }

    func testEquippingTheSameStoneAgainAnnouncesNothingNew() throws {
        let store = try store(inventory: [charizardX.inventoryKey: 1])
        store.equip(charizardX, to: "zard")
        let first = try XCTUnwrap(store.megaEvolveEvent)
        store.equip(charizardX, to: "zard")
        XCTAssertEqual(store.megaEvolveEvent, first)
    }

    func testUnequippingAnnouncesTheMegaGoingAway() throws {
        let store = try store(inventory: [charizardX.inventoryKey: 1])
        store.equip(charizardX, to: "zard")
        let equip = try XCTUnwrap(store.megaEvolveEvent)

        XCTAssertTrue(store.unequip(from: "zard"))

        let event = try XCTUnwrap(store.megaEvolveEvent)
        XCTAssertEqual(event.kind, .unequip)
        XCTAssertEqual(event.megaSpriteID, charizardX.spriteID)
        XCTAssertGreaterThan(event.id, equip.id)
    }

    func testSwappingToTheOtherStoneAnnouncesTheNewMega() throws {
        let store = try store(inventory: [charizardX.inventoryKey: 1, charizardY.inventoryKey: 1])
        store.equip(charizardX, to: "zard")
        store.equip(charizardY, to: "zard")
        let event = try XCTUnwrap(store.megaEvolveEvent)
        XCTAssertEqual(event.kind, .equip)
        XCTAssertEqual(event.megaSpriteID, charizardY.spriteID)
    }
}
