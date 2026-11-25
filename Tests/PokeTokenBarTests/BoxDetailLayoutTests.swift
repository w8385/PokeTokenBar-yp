import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// Where each part of a Box page lands and whether it is enabled, resolved from the page's own anchors.
@MainActor
final class BoxDetailMarkRecorder {
    struct Mark: Equatable {
        let frame: CGRect
        let enabled: Bool
    }

    private(set) var marks: [BoxDetailMark: Mark] = [:]

    func record(_ marks: [BoxDetailMark: Mark]) { self.marks = marks }

    var enabledByMark: [BoxDetailMark: Bool] { marks.mapValues(\.enabled) }
}

private struct BoxDetailMarkReader<Content: View>: View {
    let content: Content
    let recorder: BoxDetailMarkRecorder

    var body: some View {
        content.overlayPreferenceValue(BoxDetailMarks.self) { marks in
            GeometryReader { proxy in
                let _ = recorder.record(marks.mapValues { .init(frame: proxy[$0.bounds], enabled: $0.enabled) })
                Color.clear
            }
        }
    }
}

/// A synthetic save with one Pokémon in every Box role, a bot that answers moves and Miracle Trade, and a
/// Linking Cord in the bag.
@MainActor
final class BoxDetailFixture {
    static let storedID = "stored-bulbasaur"
    static let steelixID = "steelix"

    let store: CompanionStore
    let uploader: PartyUploader
    let battle: BattleEntryStore
    private let cleanups: [() -> Void]

    /// `steelix` adds a graduate that evolved by trade, so its page carries an evolution card; `expShare` puts an
    /// Exp. Share in the bag.
    init(language: AppLanguage = .en, raisingGraduate: String? = nil, steelix: Bool = false,
         expShare: Bool = false) throws {
        let (store, cleanup) = try BoxDexFixture.makeStore(language: language, mutate: { state in
            state.inventory[ItemKind.linkingCord.rawValue] = 1
            if expShare { state.inventory[ItemKind.expShare.rawValue] = 1 }
            if let raisingGraduate { state.raisedEntryID = raisingGraduate }
            if steelix {
                var profile = PokemonProfile.generate(seed: 208, instanceID: Self.steelixID)
                profile.level = 45
                state.dex.append(DexEntry(id: Self.steelixID, baseID: 95, finalID: 208, chainOrder: [95, 208],
                                          rarity: .rare, caughtAt: Date(timeIntervalSince1970: 1_700_000_600),
                                          profile: profile, names: [95: ["ko": "롱스톤", "en": "Onix"],
                                                                    208: ["ko": "강철톤", "en": "Steelix"]]))
            }
            var profile = PokemonProfile.generate(seed: 1, instanceID: Self.storedID)
            profile.level = 18
            let mon = MonState(baseID: 1, pathIDs: [1], plannedPathIDs: [1, 2, 3], stageIndex: 0, usedAtStage: 0,
                               rarity: .common, totalForms: 3, nature: .hardy, profile: profile)
            state.storedLines[Self.storedID] = StoredLine(mon: mon, spentAtStore: state.spentTokens)
            state.dex.append(DexEntry(id: Self.storedID, baseID: 1, finalID: 1, chainOrder: [1], rarity: .common,
                                      caughtAt: Date(timeIntervalSince1970: 1_700_000_500), profile: profile,
                                      names: [1: ["ko": "이상해씨", "en": "Bulbasaur"]],
                                      releasedAt: Date(timeIntervalSince1970: 1_700_000_500)))
        })
        let suite = "box-detail-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let uploader = PartyUploader(
            tokenStore: PartyTokenStore(fileURL: scratch.appendingPathComponent("token")), defaults: defaults,
            appVersion: "test", send: { _ in 200 },
            fetch: { request in
                let path = request.url?.path ?? ""
                if path.hasSuffix("/v1/moves") { return (Data(trainingMovesJSON.utf8), 200) }
                if path.hasSuffix("/v1/miracle") { return (Data(#"{"ok":true,"offer":null}"#.utf8), 200) }
                return (Data("{}".utf8), 404)
            },
            partySource: { [] })
        uploader.saveToken("synthetic-token")
        uploader.serverURL = "http://bot-host:8790"
        let battle = BattleEntryStore(defaults: defaults)
        _ = battle.add(BoxDexFixture.pikachuID)
        self.store = store
        self.uploader = uploader
        self.battle = battle
        cleanups = [cleanup, { defaults.removePersistentDomain(forName: suite) },
                    { try? FileManager.default.removeItem(at: scratch) }]
    }

    func finish() { cleanups.forEach { $0() } }

    func individual(_ id: String) throws -> BoxIndividual {
        try XCTUnwrap(store.boxIndividual(id: id), "no Box individual \(id)")
    }

    func page(_ id: String, bot: Bool = true, miracle: MiracleTradeModel? = nil) throws -> some View {
        let individual = try individual(id)
        let miracle = miracle ?? MiracleTradeModel(uploader: uploader, availability: .available, offer: nil)
        return BoxDetailView(store: store, individual: individual, navigation: PopoverNavigation(), onBack: {},
                             initialMiracle: bot ? miracle : nil)
            .environment(bot ? uploader : nil).environment(battle).environment(store)
    }

    /// Renders `view` at the popover's content width and waits for the details and marks to load.
    func marks<V: View>(_ view: V, of id: String, height: CGFloat = 2_400,
                        until ready: (BoxDetailMarkRecorder) -> Bool = { _ in true }) async throws -> BoxDetailMarkRecorder {
        let recorder = BoxDetailMarkRecorder()
        let individual = try individual(id)
        let size = CGSize(width: PopoverMetrics.contentWidth, height: height)
        let host = OffscreenRender.host(
            BoxDetailMarkReader(content: view.frame(width: size.width, height: size.height, alignment: .top),
                                recorder: recorder),
            size: size, appearance: .aqua)
        try await OffscreenRender.settle(host) {
            store.pokemonDetails(speciesID: individual.speciesID, form: individual.entry.form,
                                 gender: individual.entry.profile?.gender) != nil
                && recorder.marks[.header] != nil && ready(recorder)
        }
        return recorder
    }
}

@MainActor
final class BoxDetailLayoutTests: XCTestCase {
    private static let order: [BoxDetailMark] = [.header, .quickActions, .heldItem, .moveTraining, .activeMoves,
                                                 .expShare, .individual, .evolution, .exchange]

    func testTheQuickActionsAreOneRowInKoreanAndStayInsideTheColumn() async throws {
        for language in [AppLanguage.ko, .ja, .en, .de] {
            let fixture = try BoxDetailFixture(language: language)
            defer { fixture.finish() }
            let recorder = try await fixture.marks(try fixture.page(BoxDexFixture.eeveeID), of: BoxDexFixture.eeveeID)
            let row = try [BoxDetailMark.raise, .representative, .friendAdd].map {
                try XCTUnwrap(recorder.marks[$0]?.frame, "\(language) \($0)")
            }
            for frame in row {
                XCTAssertLessThanOrEqual(frame.maxX, PopoverMetrics.scrollContentWidth + 0.5, "\(language) \(row)")
            }
            if language == .ko || language == .ja {
                XCTAssertEqual(Set(row.map { $0.minY.rounded() }).count, 1, "\(language) wraps: \(row)")
            }
            let heldItem = try XCTUnwrap(recorder.marks[.heldItem]?.frame)
            XCTAssertLessThan(try XCTUnwrap(recorder.marks[.quickActions]?.frame).maxY, heldItem.minY + 0.5)
        }
    }

    func testTheSectionsRunFromQuickActionsToTheExchangeRow() async throws {
        let fixture = try BoxDetailFixture(steelix: true, expShare: true)
        defer { fixture.finish() }
        let id = BoxDetailFixture.steelixID
        let recorder = try await fixture.marks(try fixture.page(id), of: id) { recorder in
            Self.order.allSatisfy { recorder.marks[$0] != nil }
        }
        let frames = Self.order.map { recorder.marks[$0]?.frame ?? .null }
        let top = Self.order.sorted { (recorder.marks[$0]?.frame.minY ?? 0) < (recorder.marks[$1]?.frame.minY ?? 0) }
        XCTAssertEqual(top, Self.order, "sections top to bottom: \(zip(Self.order, frames).map { "\($0) \($1)" })")
        for (above, below) in zip(frames, frames.dropFirst()) {
            XCTAssertLessThanOrEqual(above.maxY, below.minY + 0.5, "\(above) overlaps \(below)")
        }
    }
}

@MainActor
final class BoxDetailControlsTests: XCTestCase {
    private static let sections: Set<BoxDetailMark> = [.header, .quickActions, .heldItem, .moveTraining,
                                                       .activeMoves, .expShare, .individual, .evolution, .exchange]

    private func controls(_ id: String, in fixture: BoxDetailFixture, bot: Bool = true) async throws -> [BoxDetailMark: Bool] {
        try await fixture.marks(try fixture.page(id, bot: bot), of: id).enabledByMark
            .filter { !Self.sections.contains($0.key) }
    }

    func testEveryRoleKeepsItsButtonsAndTheirEnabledState() async throws {
        let fixture = try BoxDetailFixture()
        defer { fixture.finish() }
        let raised = try fixture.individual(BoxDexFixture.raisedID)
        let pikachu = try fixture.individual(BoxDexFixture.pikachuID)
        let charizard = try fixture.individual(BoxDexFixture.charizardID)
        let eevee = try fixture.individual(BoxDexFixture.eeveeID)
        let stored = try fixture.individual(BoxDetailFixture.storedID)
        XCTAssertEqual([raised.role, pikachu.role, charizard.role, eevee.role, stored.role],
                       [.raising, .graduated, .friend, .graduated, .stored])

        let raisingControls = try await controls(raised.id, in: fixture)
        XCTAssertEqual(raisingControls,
                       [.battleSlots: true, .dexLink: true, .mint: true, .representative: true, .trade: false],
                       "raising: no raise or friend button, trade shown but refused")
        let fightingControls = try await controls(pikachu.id, in: fixture)
        XCTAssertEqual(fightingControls,
                       [.battleSlots: true, .dexLink: true, .friendAdd: true, .linkingCord: true, .mint: true,
                        .raise: true, .representative: true, .trade: false],
                       "a graduate in the lineup: trade refused, no Miracle post")
        let friendControls = try await controls(charizard.id, in: fixture)
        XCTAssertEqual(friendControls,
                       [.battleSlots: true, .dexLink: true, .friendRemove: true, .linkingCord: true, .mint: true,
                        .miracle: true, .raise: true, .representative: true, .trade: true])
        let graduatedControls = try await controls(eevee.id, in: fixture)
        XCTAssertEqual(graduatedControls,
                       [.battleSlots: true, .dexLink: true, .friendAdd: true, .linkingCord: true, .mint: true,
                        .miracle: true, .raise: true, .representative: true, .trade: true])
        let offlineControls = try await controls(eevee.id, in: fixture, bot: false)
        XCTAssertEqual(offlineControls,
                       [.battleSlots: true, .dexLink: true, .friendAdd: true, .linkingCord: true, .mint: true,
                        .raise: true, .representative: true],
                       "without the bot there is no trade or Miracle button")
        let storedControls = try await controls(stored.id, in: fixture)
        XCTAssertEqual(storedControls,
                       [.dexLink: true, .friendAdd: true, .mint: true, .representative: true, .resumeStored: true],
                       "stored: resume, friend, no battle slot, no trade")
    }

    func testAParkedLineAndARaisedGraduateKeepTheirButtons() async throws {
        let fixture = try BoxDetailFixture(raisingGraduate: BoxDexFixture.onixID)
        defer { fixture.finish() }
        let parked = try fixture.individual(BoxDexFixture.raisedID)
        let onix = try fixture.individual(BoxDexFixture.onixID)
        XCTAssertEqual([parked.role, onix.role], [.parked, .raising])

        let parkedControls = try await controls(parked.id, in: fixture)
        XCTAssertEqual(parkedControls,
                       [.dexLink: true, .mint: true, .representative: true, .resumeLine: true, .trade: false])
        let raisingControls = try await controls(onix.id, in: fixture)
        XCTAssertEqual(raisingControls,
                       [.battleSlots: true, .dexLink: true, .mint: true, .representative: true, .trade: false])
    }
}

/// Opt-in captures for the PR: the Box page of a graduate and of the raised Pokémon at the popover's width.
///
///     PTB_BOX_DETAIL_SHOT_DIR=/tmp/shots swift test --filter BoxDetailShotTests
@MainActor
final class BoxDetailShotTests: XCTestCase {
    func testCaptureGraduatedAndRaisingPages() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_BOX_DETAIL_SHOT_DIR"] else {
            throw XCTSkip("Set PTB_BOX_DETAIL_SHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for id in [5, 133] { _ = await SpriteLoader.image(speciesID: id) }
        for name in ItemKind.allCases.compactMap(\.spriteName) { _ = await SpriteLoader.itemImage(name: name) }
        for language in [AppLanguage.en, .ko] {
            let fixture = try BoxDetailFixture(language: language)
            defer { fixture.finish() }
            for (id, name) in [(BoxDexFixture.eeveeID, "graduated"), (BoxDexFixture.raisedID, "raising")] {
                let individual = try fixture.individual(id)
                let size = CGSize(width: PopoverMetrics.width, height: 1_500)
                let host = OffscreenRender.host(
                    try fixture.page(id)
                        .padding(PopoverMetrics.padding)
                        .frame(width: size.width, height: size.height, alignment: .top)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .environment(\.colorScheme, .dark)
                        .environment(\.controlActiveState, .active)
                        .environment(\.animatesSprites, false),
                    size: size, appearance: .darkAqua)
                try await OffscreenRender.settle(host) {
                    fixture.store.pokemonDetails(speciesID: individual.speciesID, form: individual.entry.form,
                                                 gender: individual.entry.profile?.gender) != nil
                }
                try OffscreenRender.writePNG(of: host, to: directory.appendingPathComponent(
                    "box-detail-\(name)-\(language.rawValue).png"), scale: 2)
            }
        }
    }
}
