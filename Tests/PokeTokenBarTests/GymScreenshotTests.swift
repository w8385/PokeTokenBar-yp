import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct OfflineProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// Opt-in captures for the PR: a synthetic save and a stubbed bot, the real views.
///
///     PTB_GYM_SCREENSHOT_DIR=/tmp/shots swift test --filter GymScreenshotTests
@MainActor
final class GymScreenshotTests: XCTestCase {
    private let regions = [("kanto", "Kanto"), ("johto", "Johto"), ("hoenn", "Hoenn"), ("sinnoh", "Sinnoh"),
                           ("unova", "Unova"), ("kalos", "Kalos"), ("alola", "Alola"), ("galar", "Galar"),
                           ("paldea", "Paldea")]
    private var original: URL?

    override func setUp() {
        original = GymTrainerArt.directory
        GymTrainerArt.directory = GymRepo.trainerAssets
        GymTrainerArt.clearCache()
    }

    override func tearDown() {
        GymTrainerArt.directory = original
        GymTrainerArt.clearCache()
    }

    private struct Rig {
        let store: CompanionStore
        let entry: BattleEntryStore
        let uploader: PartyUploader
        let session: GymSession
        let service: GymService
        let scratch: URL
    }

    private func entry(_ species: Int, id: String, level: Int) -> DexEntry {
        var profile = PokemonProfile.generate(seed: UInt64(species), instanceID: id)
        profile.level = level
        var entry = DexEntry(baseID: species, finalID: species, chainOrder: [species], rarity: .common,
                             caughtAt: Date(timeIntervalSince1970: 1_700_000_000), isShiny: false, profile: profile,
                             names: [species: ["ko": "\(species)", "en": "\(species)"]])
        entry.id = id
        return entry
    }

    private func rig(badges: GymBadges, reply: @escaping @Sendable (URLRequest) -> (Data, Int)) throws -> Rig {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("gym-shot-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        var state = CompanionState()
        state.language = .ko
        state.installBaselineSet = true
        state.gymBadges = badges
        state.dex = [entry(25, id: "pikachu", level: 62), entry(94, id: "gengar", level: 38),
                     entry(6, id: "zard", level: 50), entry(130, id: "gyarados", level: 44),
                     entry(149, id: "dragonite", level: 55), entry(3, id: "venusaur", level: 41)]
        let file = scratch.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: OfflineProvider(), fileURL: file)
        let defaults = UserDefaults(suiteName: "gym-shot-\(UUID())")!
        let entryStore = BattleEntryStore(defaults: defaults)
        ["pikachu", "gengar", "zard", "gyarados", "dragonite", "venusaur"].forEach { entryStore.add($0) }
        let uploader = PartyUploader(
            tokenStore: PartyTokenStore(fileURL: scratch.appendingPathComponent("token")), defaults: defaults,
            appVersion: "shot", send: { _ in 200 }, fetch: { _ in (Data(), 404) }, partySource: { [] })
        uploader.saveToken("synthetic-token")
        uploader.serverURL = "http://bot-host:8790"
        let session = GymSession()
        session.setCatalog(try GymCatalog.decode(GymFixtures.catalogData(regions: regions)), for: "http://bot-host:8790")
        let service = GymService(
            link: { uploader.gymLink }, exchange: { request in reply(request) },
            badges: { store.state.gymBadges }, ownedTMs: { MachineMove.ownedIDs(in: store.state.inventory) },
            applyReward: { reward, opponent, region in
                store.applyGymReward(reward, trainer: opponent.trainer.displayName(store.language), region: region.name)
            },
            session: session)
        return Rig(store: store, entry: entryStore, uploader: uploader, session: session, service: service, scratch: scratch)
    }

    private func badges(_ gyms: Set<Int>, hallOfFame: Bool = false) -> GymBadges {
        var badges = GymBadges()
        badges.update("kanto") { $0.gyms = gyms; $0.hallOfFame = hallOfFame }
        badges.update("johto") { $0.gyms = [1, 2] }
        return badges
    }

    private func shot(_ rig: Rig, height: CGFloat, to file: URL) async throws {
        let section = VStack(alignment: .leading, spacing: 6) {
            Text(rig.store.l.gymSectionTitle).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                .textCase(.uppercase).padding(.leading, 4)
            GymSection(store: rig.store, uploader: rig.uploader, entry: rig.entry, service: rig.service).ptbCard()
        }
        .padding(.horizontal, 12).padding(.top, 8)
        .frame(maxHeight: .infinity, alignment: .top)
        let size = NSSize(width: PopoverMetrics.contentWidth, height: height)
        try await OffscreenRender.capture(
            section.frame(width: size.width, height: size.height)
                .background(Color.white).environment(\.colorScheme, .light)
                .environment(\.locale, AppLanguage.ko.displayLocale),
            size: size, appearance: .aqua, to: file)
    }

    func testCaptureGymSectionStates() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_GYM_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_GYM_SCREENSHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let none: @Sendable (URLRequest) -> (Data, Int) = { _ in (Data(), 503) }

        let list = try rig(badges: badges([1, 2, 3, 5]), reply: none)
        defer { try? FileManager.default.removeItem(at: list.scratch) }
        try await shot(list, height: 960, to: directory.appendingPathComponent("pve-gym-list.png"))

        let elite = try rig(badges: badges(Set(1...8)), reply: none)
        defer { try? FileManager.default.removeItem(at: elite.scratch) }
        let team = GymTeam.team(state: elite.store.state, slots: elite.entry.slots, moveChoices: elite.entry.moveChoices,
                                rentalSpeciesID: elite.entry.rentalSpeciesID)
        elite.session.setRun(GymRunProgress(team: team.ids, nextIndex: 2), for: "kanto-elite")
        try await shot(elite, height: 960, to: directory.appendingPathComponent("pve-elite-run.png"))

        let win = GymFixtures.outcomeData(gymID: "kanto-4", kind: "gym", won: true)
        let result = try rig(badges: badges([1, 2, 3]), reply: { _ in (win, 200) })
        defer { try? FileManager.default.removeItem(at: result.scratch) }
        let kanto = try XCTUnwrap(result.service.catalog?.region("kanto"))
        let resultTeam = GymTeam.team(state: result.store.state, slots: result.entry.slots,
                                      moveChoices: result.entry.moveChoices, rentalSpeciesID: result.entry.rentalSpeciesID)
        await result.service.fightGym(kanto.gyms[3], region: kanto, team: resultTeam)
        XCTAssertNotNil(result.service.last?.reward)
        try await shot(result, height: 560, to: directory.appendingPathComponent("pve-battle-result.png"))

        let lossStep = GymFixtures.outcomeData(
            gymID: "kanto-elite-3", kind: "elite", won: false, run: ("kanto-elite", 3, 5, "kanto-elite-1", nil),
            hps: [0, 0, 0, nil, 0, 0], foeHps: [64, 30, 100, 80, 100, 100])
        let loss = try rig(badges: badges(Set(1...8)), reply: { _ in (lossStep, 200) })
        defer { try? FileManager.default.removeItem(at: loss.scratch) }
        let lossRegion = try XCTUnwrap(loss.service.catalog?.region("kanto"))
        loss.session.setRun(GymRunProgress(team: resultTeam.ids, nextIndex: 2), for: "kanto-elite")
        await loss.service.fightRun("kanto-elite", battles: lossRegion.elite.battles, region: lossRegion, team: resultTeam)
        try await shot(loss, height: 560, to: directory.appendingPathComponent("pve-battle-loss.png"))

        let caseRig = try rig(badges: badges([1, 2, 3, 4, 5, 6, 7, 8], hallOfFame: true), reply: none)
        defer { try? FileManager.default.removeItem(at: caseRig.scratch) }
        caseRig.session.showsBadgeCase = true
        try await shot(caseRig, height: 560, to: directory.appendingPathComponent("pve-badge-case.png"))

        let offline = try rig(badges: GymBadges(), reply: none)
        defer { try? FileManager.default.removeItem(at: offline.scratch) }
        let unreachable = GymSession()
        let down = GymService(link: { offline.uploader.gymLink }, exchange: { _ in throw URLError(.cannotConnectToHost) },
                              badges: { GymBadges() }, ownedTMs: { [] }, applyReward: { _, _, _ in }, session: unreachable)
        await down.loadCatalog()
        XCTAssertEqual(down.unavailable, .unreachable)
        let downRig = Rig(store: offline.store, entry: offline.entry, uploader: offline.uploader, session: unreachable,
                          service: down, scratch: offline.scratch)
        try await shot(downRig, height: 120, to: directory.appendingPathComponent("pve-unreachable.png"))
    }
}
