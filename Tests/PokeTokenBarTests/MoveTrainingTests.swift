import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct TrainingProvider: PokeProviding, PokemonDetailProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        try SpeciesFacts.details(speciesID)
    }
}

/// Counts what a `Sendable` closure sees.
final class TrainingLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    func add(_ value: String) { lock.lock(); values.append(value); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return values }
}

let trainingMovesJSON = """
{"ok":true,"default":[84,209],"moves":[
 {"id":84,"name":"Thunder Shock","type":"electric","power":40,"damage_class":"special","accuracy":100,"level":1,"pp":30,"source":"level"},
 {"id":209,"name":"Spark","type":"electric","power":65,"damage_class":"physical","accuracy":100,"level":20,"pp":20,"source":"level"},
 {"id":85,"name":"Thunderbolt","type":"electric","power":90,"damage_class":"special","accuracy":100,"level":0,"pp":15,"source":"machine"},
 {"id":89,"name":"Earthquake","type":"ground","power":100,"damage_class":"physical","accuracy":100,"level":0,"pp":10,"source":"machine"}
]}
"""

/// A synthetic save with the real Box page and Battle tab mounted in a window that is never on screen.
@MainActor
final class TrainingRig {
    let scratch: URL
    let store: CompanionStore
    let battle: BattleEntryStore
    let uploader: PartyUploader
    let navigation = PopoverNavigation()
    let posts = TrainingLog()
    let fetches = TrainingLog()
    private var windows: [NSWindow] = []

    init(movesJSON: String = trainingMovesJSON) async throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("training-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        var state = CompanionState()
        state.language = .en
        state.usedSinceInstall = 1_000_000_000
        state.active = MonState(baseID: 4, pathIDs: [4, 5], stageIndex: 1, usedAtStage: 0, rarity: .common,
                                totalForms: 2, profile: PokemonProfile.generate(seed: 5, instanceID: "raised"))
        for (id, species, name, level) in [("pikachu", 25, "Pikachu", 42), ("snorlax", 143, "Snorlax", 47)] {
            var profile = PokemonProfile.generate(seed: UInt64(species), instanceID: id)
            profile.level = level
            var entry = DexEntry(baseID: species, finalID: species, chainOrder: [species], rarity: .common,
                                 caughtAt: Date(timeIntervalSince1970: 1_700_000_000), profile: profile,
                                 names: [species: ["ko": name, "en": name]])
            entry.id = id
            state.dex.append(entry)
        }
        let file = scratch.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let defaults = UserDefaults(suiteName: "training-\(UUID())")!
        store = CompanionStore(provider: TrainingProvider(), fileURL: file, defaults: defaults)
        battle = BattleEntryStore(defaults: defaults)
        let posts = self.posts, fetches = self.fetches
        let body = Data(movesJSON.utf8)
        uploader = PartyUploader(
            tokenStore: PartyTokenStore(fileURL: scratch.appendingPathComponent("token")), defaults: defaults,
            appVersion: "test", send: { _ in posts.add("post"); return 200 },
            fetch: { request in fetches.add(request.url?.absoluteString ?? ""); return (body, 200) },
            partySource: { [store, battle] in
                BattleEntry.party(state: store.state, slots: battle.slots, moveChoices: battle.moveChoices,
                                  rentalSpeciesID: 4)
            })
        uploader.saveToken("synthetic-token")
        uploader.serverURL = "http://bot-host:8790"
    }

    deinit { try? FileManager.default.removeItem(at: scratch) }

    func boxDetail(_ id: String) throws -> some View {
        let entry = try XCTUnwrap(store.state.dex.first { $0.id == id })
        return BoxDetailView(store: store, individual: BoxIndividual(id: id, entry: entry, role: .graduated),
                             navigation: navigation, onBack: {})
            .environment(uploader).environment(battle).environment(store)
    }

    func battleTab() -> some View {
        BattleView(store: store, navigation: navigation, initialPickerQuery: "")
            .environment(uploader).environment(battle).environment(store).environment(navigation)
    }

    /// The Moves section on its own, with the picker open on slot 1 and the Box page's upload hook.
    func section(_ id: String, editing: Int? = 0) throws -> some View {
        let candidate = try XCTUnwrap(BattleEntry.candidates(in: store.state).first { $0.id == id })
        let uploader = self.uploader
        return MoveTrainingSection(store: store, battleEntry: battle, uploader: uploader, candidate: candidate,
                                   initialEditing: editing, onChange: { Task { await uploader.tick() } })
            .padding(12)
    }

    /// Hosts `view` in an off-screen window and lets its tasks finish.
    func mount<V: View>(_ view: V, height: CGFloat = 1400) async throws -> NSView {
        let size = CGSize(width: PopoverMetrics.contentWidth, height: height)
        let host = OffscreenRender.host(view.frame(width: size.width, height: size.height, alignment: .top)
            .background(Color.white).environment(\.colorScheme, .light), size: size, appearance: .aqua)
        windows.append(OffscreenRender.windowHosting(host, appearance: .aqua))
        try await OffscreenRender.settle(host)
        return host
    }

    /// SwiftUI buttons carry no title, label or tooltip in the AppKit tree, so they are addressed by where they
    /// sit: top to bottom, then left to right. Bordered buttons draw without a native view and are not listed.
    func buttons(in host: NSView) -> [NSButton] {
        NativeControls.descendants(host).compactMap { $0 as? NSButton }
            .map { (button: $0, frame: host.convert($0.bounds, from: $0)) }
            .sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
            .map(\.button)
    }

    func frame(of button: NSButton, in host: NSView) -> CGRect { host.convert(button.bounds, from: button) }

    /// The buttons once `ready` accepts them; fails the test with their frames if SwiftUI never gets there.
    func buttons(in host: NSView, until ready: ([NSButton]) -> Bool, file: StaticString = #filePath,
                 line: UInt = #line) async throws -> [NSButton] {
        var found: [NSButton] = []
        try await OffscreenRender.waitUntil(
            "the buttons to reach the expected shape: \(found.map { "\(frame(of: $0, in: host)) enabled=\($0.isEnabled)" })",
            in: host, file: file, line: line) {
            found = buttons(in: host)
            return ready(found)
        }
        return found
    }

    /// The full-width picker rows. Which small controls (Buy, Auto reset) have a native view differs between
    /// macOS versions, so only the rows are counted.
    func chooseRows(in host: NSView, count: Int) async throws -> [NSButton] {
        let rows = try await buttons(in: host, until: { list in
            list.filter { self.frame(of: $0, in: host).width > 250 }.count == count
        })
        return rows.filter { frame(of: $0, in: host).width > 250 }
    }

    /// The section's Auto reset: the short button on the section's right edge. The Box page has other small
    /// controls (Back, held item) on other macOS versions, so it is found by where it sits, not by a count.
    func autoReset(in host: NSView, enabled: Bool? = nil) async throws -> NSButton {
        let isReset: (NSButton) -> Bool = { button in
            let frame = self.frame(of: button, in: host)
            return frame.height < 15 && frame.maxX > 308 && enabled.map { $0 == button.isEnabled } ?? true
        }
        let found = try await buttons(in: host, until: { $0.contains(where: isReset) })
        return try XCTUnwrap(found.first(where: isReset))
    }

    /// The Battle tab's "Training" links: the small text buttons in the right column, one per lineup row.
    func trainingLinks(in host: NSView) async throws -> [NSButton] {
        let isLink: (NSButton) -> Bool = { button in
            let frame = self.frame(of: button, in: host)
            return frame.minX > 200 && frame.width > 30 && frame.height < 20
        }
        _ = try await buttons(in: host, until: { $0.contains(where: isLink) })
        try await OffscreenRender.settle(host)
        return buttons(in: host).filter(isLink)
    }

    func press(_ button: NSButton, in host: NSView, until done: () throws -> Bool = { true }) async throws {
        button.performClick(nil)
        try await OffscreenRender.settle(host, until: done)
    }

    func close() { windows.forEach { $0.close() }; windows = [] }
}

@MainActor
final class MoveTrainingTests: XCTestCase {
    func testAnOwnedTMIsChoosableFromThePickerAndUploadsOnce() async throws {
        let rig = try await TrainingRig()
        defer { rig.close() }
        rig.store.grantTM(moveID: 89)
        let host = try await rig.mount(rig.section("pikachu"))

        // Spark, Thunder Shock, then the owned Earthquake at the end of the TM group.
        let rows = try await rig.chooseRows(in: host, count: 3)
        try await rig.press(try XCTUnwrap(rows.last), in: host, until: { !rig.posts.all.isEmpty })

        XCTAssertEqual(rig.battle.chosenMoves(for: "pikachu", pokemonID: 25), [89, 209])
        XCTAssertEqual(rig.battle.chosenMoves(for: "snorlax", pokemonID: 143), [], "choices are per instance")
        XCTAssertEqual(rig.battle.slots, [], "a Box edit never changes the lineup")
        XCTAssertEqual(rig.posts.all.count, 1)
        XCTAssertEqual(rig.fetches.all.filter { $0.contains("/v1/moves") && $0.contains("machine=1") }.count, 1)
    }

    func testAnUnownedTMHasNoChooseRowUntilItIsBought() async throws {
        let rig = try await TrainingRig()
        defer { rig.close() }
        rig.store.grantTM(moveID: 89)
        let before = rig.store.availableTokens
        let host = try await rig.mount(rig.section("pikachu"))

        // Spark, Thunder Shock and the owned Earthquake. The locked Thunderbolt has no choose row.
        _ = try await rig.chooseRows(in: host, count: 3)

        XCTAssertTrue(rig.store.buyTM(moveID: 85, power: 90, isWeather: false))
        XCTAssertEqual(before - rig.store.availableTokens, 80_000_000)
        _ = try await rig.chooseRows(in: host, count: 4)
    }

    func testTheBoxPageMountsTheSectionAndItsChangesUploadOnce() async throws {
        let rig = try await TrainingRig()
        defer { rig.close() }
        rig.battle.chooseMove(209, at: 0, for: "pikachu", pokemonID: 25, current: [84, 209])
        let host = try await rig.mount(rig.boxDetail("pikachu"))

        try await rig.press(try await rig.autoReset(in: host, enabled: true), in: host,
                            until: { !rig.posts.all.isEmpty })

        XCTAssertEqual(rig.battle.chosenMoves(for: "pikachu", pokemonID: 25), [])
        XCTAssertEqual(rig.posts.all.count, 1)
    }

    func testTheBoxPageAsksTheBotForThatPokemonsMoves() async throws {
        let rig = try await TrainingRig()
        defer { rig.close() }
        rig.store.grantTM(moveID: 89)
        let host = try await rig.mount(rig.boxDetail("snorlax"))
        _ = try await rig.autoReset(in: host)
        XCTAssertEqual(rig.fetches.all.filter { $0.contains("pokemon_id=143") }.count, 1)
    }

    func testBattleTabHasNoMoveOrHeldItemRowsAndLinksToTraining() async throws {
        let rig = try await TrainingRig()
        defer { rig.close() }
        rig.battle.add("pikachu")
        rig.battle.add("snorlax")
        let host = try await rig.mount(rig.battleTab(), height: 900)

        let links = try await rig.trainingLinks(in: host)

        XCTAssertEqual(links.count, 2, "one link per lineup row")
        XCTAssertTrue(rig.fetches.all.isEmpty, "the Battle tab no longer asks the bot for moves")
    }

    func testTheTrainingLinkOpensThatPokemonsBoxPage() async throws {
        let rig = try await TrainingRig()
        defer { rig.close() }
        rig.battle.add("pikachu")
        rig.battle.add("snorlax")
        let host = try await rig.mount(rig.battleTab(), height: 900)
        XCTAssertNil(rig.navigation.boxDetailID)

        let links = try await rig.trainingLinks(in: host)
        try await rig.press(try XCTUnwrap(links.first), in: host)

        XCTAssertEqual(rig.navigation.boxDetailID, "pikachu")
    }
}

/// Writes the PR screenshots from synthetic data (nothing is read from or written to the real save):
///
///     PTB_TM_SCREENSHOT_DIR=/tmp/shots swift test --filter MoveTrainingScreenshotTests
@MainActor
final class MoveTrainingScreenshotTests: XCTestCase {
    private func outputDirectory() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment["PTB_TM_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_TM_SCREENSHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func testBattleTabKeepsOnlyTheLineupAndLinksToTraining() async throws {
        let directory = try outputDirectory()
        let rig = try await TrainingRig()
        defer { rig.close() }
        rig.battle.add("pikachu")
        rig.battle.add("snorlax")
        let host = try await rig.mount(rig.battleTab(), height: 700)
        _ = try await rig.trainingLinks(in: host)
        try OffscreenRender.writePNG(of: host, to: directory.appendingPathComponent("tm-battle-after.png"), scale: 2)
    }

    func testBoxPageShowsTheMoves() async throws {
        let directory = try outputDirectory()
        let rig = try await TrainingRig()
        defer { rig.close() }
        let host = try await rig.mount(rig.boxDetail("pikachu"), height: 1000)
        _ = try await rig.autoReset(in: host)
        try OffscreenRender.writePNG(of: host, to: directory.appendingPathComponent("tm-box-moves.png"), scale: 2)
    }

    func testThePickerOffersLevelUpMovesAndOwnedAndLockedTMs() async throws {
        let directory = try outputDirectory()
        let rig = try await TrainingRig()
        defer { rig.close() }
        rig.store.grantTM(moveID: 89)
        let host = try await rig.mount(rig.section("pikachu"), height: 620)
        _ = try await rig.chooseRows(in: host, count: 3)
        try OffscreenRender.writePNG(of: host, to: directory.appendingPathComponent("tm-box-picker.png"), scale: 2)
    }
}

@MainActor
final class MachineOwnershipTests: XCTestCase {
    private func chooseTM(_ rig: TrainingRig, _ instance: String, _ pokemonID: Int) {
        rig.battle.chooseMove(85, at: 2, for: instance, pokemonID: pokemonID, current: [84, 209], isMachine: true)
    }

    private func party(_ rig: TrainingRig) -> [PartyMember] {
        BattleEntry.party(state: rig.store.state, slots: [BattleEntrySlot(instanceID: "pikachu"),
                                                           BattleEntrySlot(instanceID: "snorlax")],
                          moveChoices: rig.battle.moveChoices, rentalSpeciesID: 4)
    }

    func testPriceTiersFollowPowerAndWeatherThenScaleWithShopDifficulty() async throws {
        XCTAssertEqual([0, 69, 70, 99, 100, 150].map { PokemonBalance.machinePrice(power: $0, isWeather: false) },
                       [40, 40, 80, 80, 120, 120].map { $0 * 1_000_000 })
        XCTAssertEqual(PokemonBalance.machinePrice(power: 0, isWeather: true), 120_000_000)

        let rig = try await TrainingRig()
        defer { rig.close() }
        XCTAssertEqual(rig.store.tmPrice(power: 90, isWeather: false), 80_000_000)
        rig.store.setShopDifficulty(0.5)
        XCTAssertEqual(rig.store.tmPrice(power: 90, isWeather: false), 40_000_000)
        XCTAssertEqual(rig.store.tmPrice(power: 120, isWeather: false), 60_000_000)
    }

    func testBuyingATMChargesOnceAndMakesItChoosableOnEveryPokemon() async throws {
        let rig = try await TrainingRig()
        defer { rig.close() }
        chooseTM(rig, "pikachu", 25)
        chooseTM(rig, "snorlax", 143)
        XCTAssertEqual(party(rig).map(\.moves), [[84, 209], [84, 209]].map { Optional($0) }, "unowned: dropped")
        let before = rig.store.availableTokens

        XCTAssertTrue(rig.store.buyTM(moveID: 85, power: 90, isWeather: false))
        XCTAssertFalse(rig.store.buyTM(moveID: 85, power: 90, isWeather: false), "owned already")

        XCTAssertEqual(before - rig.store.availableTokens, 80_000_000)
        XCTAssertEqual(party(rig).map(\.moves), [[84, 209, 85], [84, 209, 85]].map { Optional($0) })
    }

    func testAnUnownedTMNeverReachesTheUpload() async throws {
        let rig = try await TrainingRig()
        defer { rig.close() }
        rig.battle.chooseMove(85, at: 0, for: "pikachu", pokemonID: 25, current: [], isMachine: true)

        XCTAssertNil(party(rig).first?.moves, "only the unowned TM was chosen, so the bot picks")
        rig.store.grantTM(moveID: 85)
        XCTAssertEqual(party(rig).first?.moves, [85])
    }

    func testGrantingATMIsFreeAndIdempotent() async throws {
        let rig = try await TrainingRig()
        defer { rig.close() }
        let before = rig.store.availableTokens

        XCTAssertTrue(rig.store.grantTM(moveID: 89))
        XCTAssertFalse(rig.store.grantTM(moveID: 89))

        XCTAssertTrue(rig.store.ownsTM(89))
        XCTAssertEqual(rig.store.availableTokens, before)
        XCTAssertEqual(rig.store.state.inventory["tm:89"], 1)
    }

    func testTheMachineMarkFollowsTheMoveWhenItIsSwappedOut() async throws {
        let rig = try await TrainingRig()
        defer { rig.close() }
        chooseTM(rig, "pikachu", 25)
        XCTAssertEqual(rig.battle.moveChoices["pikachu"]?.machine, [85])

        rig.battle.chooseMove(85, at: 0, for: "pikachu", pokemonID: 25, current: [84, 209, 85])
        XCTAssertEqual(rig.battle.moveChoices["pikachu"]?.moves, [85, 209, 84])
        XCTAssertEqual(rig.battle.moveChoices["pikachu"]?.machine, [85], "moving it keeps the mark")

        rig.battle.chooseMove(300, at: 0, for: "pikachu", pokemonID: 25, current: [85, 209, 84])
        XCTAssertEqual(rig.battle.moveChoices["pikachu"]?.machine, [], "replaced, so no longer a TM entry")
    }
}

final class LearnableMoveSourceTests: XCTestCase {
    func testSourceSplitsTheListAndAnOlderBotMeansEveryMoveIsLevelUp() throws {
        let both = try LearnableMoves.decode(Data(trainingMovesJSON.utf8))
        XCTAssertEqual(both.levelUpMoves.map(\.id), [84, 209])
        XCTAssertEqual(both.machineMoves.map(\.id), [85, 89])

        let old = try LearnableMoves.decode(Data(
            #"{"ok":true,"default":[85],"moves":[{"id":85,"name":"a","type":"electric","power":90,"damage_class":"special","accuracy":100,"level":26}]}"#.utf8))
        XCTAssertEqual(old.levelUpMoves.map(\.id), [85])
        XCTAssertTrue(old.machineMoves.isEmpty)
    }

    func testWeatherMovesDecodeTheirWeather() throws {
        let moves = try LearnableMoves.decode(Data(
            #"{"ok":true,"default":[],"moves":[{"id":241,"name":"Sunny Day","type":"fire","power":0,"damage_class":"status","accuracy":null,"level":0,"source":"machine","weather":"sun"}]}"#.utf8))
        XCTAssertTrue(try XCTUnwrap(moves.moves.first).isWeather)
    }

    @MainActor
    func testTheUploaderAsksTheBotOncePerPokemonAndLevel() async throws {
        let rig = try await TrainingRig()
        defer { rig.close() }

        _ = await rig.uploader.learnableMoves(pokemonID: 25, level: 42)
        _ = await rig.uploader.learnableMoves(pokemonID: 25, level: 42)
        _ = await rig.uploader.learnableMoves(pokemonID: 25, level: 43)

        XCTAssertEqual(rig.fetches.all.count, 2)
    }

    @MainActor
    func testTheLearnsetCacheIsPerServer() async throws {
        let rig = try await TrainingRig()
        defer { rig.close() }

        _ = await rig.uploader.learnableMoves(pokemonID: 25, level: 42)
        rig.uploader.serverURL = "http://other-bot:8790"
        _ = await rig.uploader.learnableMoves(pokemonID: 25, level: 42)

        XCTAssertEqual(rig.fetches.all.count, 2)
    }
}
