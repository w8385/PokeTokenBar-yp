import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// The Box cell badges and the screens the raise/representative buttons live on, from the synthetic
/// `BoxDexFixture` save. `PTB_RAISEPICK_SHOTS=<dir>` writes the screenshots into that folder; nothing reads the player's save.
@MainActor
final class RaisePickRenderingTests: XCTestCase {
    private func cellLabels(store: CompanionStore, id: String) async throws -> String {
        let individual = try XCTUnwrap(store.boxIndividual(id: id))
        return BoxCell(store: store, individual: individual, onTap: {}).tooltip
    }

    func testParkedLineCellShowsRestingAndAnotherCellDoesNot() async throws {
        let (store, cleanup) = try BoxDexFixture.makeStore(language: .en) { state in
            state.raisedEntryID = BoxDexFixture.pikachuID
            state.parkedSpentTokens = 0
        }
        defer { cleanup() }
        let parked = try await cellLabels(store: store, id: BoxDexFixture.raisedID)
        XCTAssertTrue(parked.contains(store.l.parkedBadge), "parked cell: \(parked)")
        let other = try await cellLabels(store: store, id: BoxDexFixture.onixID)
        XCTAssertFalse(other.contains(store.l.parkedBadge), "other cell: \(other)")
    }

    func testRepresentativeCellShowsTheBadgeAndOnlyThatCell() async throws {
        let (store, cleanup) = try BoxDexFixture.makeStore(language: .en) { state in
            state.representativeSpeciesID = 95
        }
        defer { cleanup() }
        let badge = try await cellLabels(store: store, id: BoxDexFixture.onixID)
        XCTAssertTrue(badge.contains(store.l.representativeBadge), "representative cell: \(badge)")
        let other = try await cellLabels(store: store, id: BoxDexFixture.eeveeID)
        XCTAssertFalse(other.contains(store.l.representativeBadge), "other cell: \(other)")
    }

    func testCaptureRaisePickScreens() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_RAISEPICK_SHOTS"] else {
            throw XCTSkip("Set PTB_RAISEPICK_SHOTS for the raise-pick captures")
        }
        let dir = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let suite = "raise-pick-shots-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let usage = UsageStore(providers: [], discoverClaudeConfigDirs: { [] }, readDefaultIdentity: { nil },
                               claudeUsageEntries: { _ in [] }, autoRefresh: false, defaults: defaults)
        let updater = UpdateChecker(currentVersion: "2.5.7-yp1", defaults: defaults, fetchLatest: { nil })
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("raise-pick-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let uploader = await BoxDexFixture.makeUploader(defaults: defaults, scratch: scratch, connected: false)
        let battle = BattleEntryStore(defaults: defaults)

        func prepared(mutate: @escaping (inout CompanionState) -> Void) async throws
            -> (CompanionStore, () -> Void) {
            let (store, cleanup) = try BoxDexFixture.makeStore(mutate: mutate, defaults: defaults)
            for id in [25, 6, 95, 5] { await store.loadPokemonDetails(speciesID: id) }
            store.update(todayTokensByProvider: ["test": 0], todayDate: "d1", monthTotal: 0, burnTier: .idle,
                         limitWarning: false, hasUsageData: true)
            for _ in 0..<100 where store.currentLine == nil && !store.isLineParked { await Task.yield() }
            return (store, cleanup)
        }
        func popover(_ store: CompanionStore, _ nav: PopoverNavigation) -> some View {
            PopoverView(screenHeight: 5000)
                .environment(usage).environment(store).environment(updater).environment(nav)
                .environment(uploader).environment(battle)
                .environment(\.colorScheme, .light)
                .environment(\.controlActiveState, .active)
        }

        let (plain, cleanPlain) = try await prepared { _ in }
        defer { cleanPlain() }
        let detail = PopoverNavigation(); detail.openBoxDetail(id: BoxDexFixture.onixID)
        try await shot(popover(plain, detail), "raise-pick-box-detail", dir: dir, height: 700)

        let (raised, cleanRaised) = try await prepared { state in
            state.raisedEntryID = BoxDexFixture.pikachuID
            state.parkedSpentTokens = state.spentTokens
        }
        defer { cleanRaised() }
        try await shot(popover(raised, PopoverNavigation()), "raise-pick-home", dir: dir, height: 700)
        let box = PopoverNavigation(); box.tab = .box
        try await shot(popover(raised, box), "raise-pick-parked", dir: dir, height: 520)
        let parkedDetail = PopoverNavigation(); parkedDetail.openBoxDetail(id: BoxDexFixture.raisedID)
        try await shot(popover(raised, parkedDetail), "raise-pick-parked-detail", dir: dir, height: 700)

        let (represented, cleanRep) = try await prepared { state in state.representativeSpeciesID = 95 }
        defer { cleanRep() }
        let repBox = PopoverNavigation(); repBox.tab = .box
        try await shot(popover(represented, repBox), "raise-pick-representative", dir: dir, height: 520)
        let repDetail = PopoverNavigation(); repDetail.openBoxDetail(id: BoxDexFixture.onixID)
        try await shot(popover(represented, repDetail), "raise-pick-representative-detail", dir: dir, height: 700)
    }

    private func shot<V: View>(_ view: V, _ name: String, dir: URL, height: CGFloat) async throws {
        let width = PopoverMetrics.width
        try await OffscreenRender.capture(
            view.frame(width: width, height: height, alignment: .top)
                .background(Color(nsColor: .windowBackgroundColor)),
            size: CGSize(width: width, height: height), appearance: .aqua, scale: 2,
            settle: .seconds(4), to: dir.appendingPathComponent("\(name).png"))
    }
}
