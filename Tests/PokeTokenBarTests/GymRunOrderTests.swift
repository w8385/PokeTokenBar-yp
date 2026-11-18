import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct RunOrderProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// The Battle sub-tab lists a region's gyms, then the hideout, the Elite Four and the hidden boss.
///
///     PTB_RUN_ORDER_SHOT_DIR=/tmp/shots swift test --filter GymRunOrderTests
@MainActor
final class GymRunOrderTests: XCTestCase {
    private let height: CGFloat = 1300
    private let caseHeight: CGFloat = 420
    private var original: URL?
    private var scratch: URL!

    override func setUp() async throws {
        original = GymTrainerArt.directory
        GymTrainerArt.directory = GymRepo.trainerAssets
        GymTrainerArt.clearCache()
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("gym-run-order-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        GymTrainerArt.directory = original
        GymTrainerArt.clearCache()
        try? FileManager.default.removeItem(at: scratch)
    }

    /// Seven badges: the hideout is open, the Elite Four is locked and the hidden boss waits for the Hall of Fame.
    private func section(_ language: AppLanguage, badgeCase: Bool = false) throws -> some View {
        var badges = GymBadges()
        badges.update("kanto") { $0.gyms = Set(1...7); $0.orgBeaten = badgeCase }
        var state = CompanionState()
        state.language = language
        state.installBaselineSet = true
        state.gymBadges = badges
        let file = scratch.appendingPathComponent("state-\(language.rawValue).json")
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: RunOrderProvider(), fileURL: file)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "gym-run-order-\(UUID())"))
        let uploader = PartyUploader(
            tokenStore: PartyTokenStore(fileURL: scratch.appendingPathComponent("token")), defaults: defaults,
            appVersion: "shot", send: { _ in 200 }, fetch: { _ in (Data(), 404) }, partySource: { [] })
        uploader.saveToken("synthetic-token")
        uploader.serverURL = "http://bot-host:8790"
        let session = GymSession()
        session.showsBadgeCase = badgeCase
        session.setCatalog(try GymCatalog.decode(GymFixtures.catalogData(hidden: true)), for: "http://bot-host:8790")
        let service = GymService(link: { uploader.gymLink }, exchange: { _ in (Data(), 503) },
                                 badges: { store.state.gymBadges }, ownedTMs: { [] },
                                 applyReward: { _, _, _ in }, session: session)
        return GymSection(store: store, uploader: uploader, entry: BattleEntryStore(defaults: defaults), service: service)
            .ptbCard()
            .padding(.horizontal, 12).padding(.top, 8)
            .frame(width: PopoverMetrics.contentWidth, height: badgeCase ? caseHeight : height, alignment: .top)
            .background(Color.white).environment(\.colorScheme, .light)
            .environment(\.locale, language.displayLocale)
    }

    func testBattleSubTabListsTheHideoutBeforeTheEliteFourAndTheHiddenBossLast() throws {
        let withHidden = try XCTUnwrap(GymFixtures.catalog(hidden: true).region("kanto"))
        XCTAssertEqual(GymSection.runRows(withHidden), [.hideout, .elite, .hidden])
        let withoutHidden = try XCTUnwrap(GymFixtures.catalog().region("kanto"))
        XCTAssertEqual(GymSection.runRows(withoutHidden), [.hideout, .elite])
    }

    func testCaptureTheBattleSubTab() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_RUN_ORDER_SHOT_DIR"] else {
            throw XCTSkip("Set PTB_RUN_ORDER_SHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for language in [AppLanguage.ko, .en, .de] {
            _ = try await OffscreenRender.capture(
                try section(language), size: CGSize(width: PopoverMetrics.contentWidth, height: height),
                appearance: .aqua, to: directory.appendingPathComponent("battle-run-order-\(language.rawValue).png"))
            _ = try await OffscreenRender.capture(
                try section(language, badgeCase: true), size: CGSize(width: PopoverMetrics.contentWidth, height: caseHeight),
                appearance: .aqua, to: directory.appendingPathComponent("badge-case-\(language.rawValue).png"))
        }
    }
}
