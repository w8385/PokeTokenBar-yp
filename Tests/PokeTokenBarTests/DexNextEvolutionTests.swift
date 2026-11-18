import XCTest
@testable import PokeTokenBar

private struct LineProvider: PokeProviding, SpeciesIndexProviding {
    let tree: EvoNode
    let indexed: [Int]
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: tree.speciesID, tree: tree, rarity: .common, names: [:])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func speciesIndex() async throws -> SpeciesIndex {
        SpeciesIndex(entries: try indexed.map { try SpeciesFacts.indexEntry($0) })
    }
}

private final class FakeClock: @unchecked Sendable {
    var now = Date(timeIntervalSinceReferenceDate: 800_000_000)
}

private func node(_ id: Int, _ children: [EvoNode] = []) -> EvoNode {
    EvoNode(speciesID: id, children: children, methods: [EvoMethod(trigger: "level-up")])
}

private let munchlaxLine = node(446, [node(143)])
private let eeveeLine = node(133, [134, 135, 136, 196, 197, 470, 471, 700].map { node($0) })

@MainActor
final class DexNextEvolutionTests: XCTestCase {
    private func store(tree: EvoNode = munchlaxLine, indexed: [Int] = [446, 143],
                       clock: FakeClock = FakeClock()) throws -> CompanionStore {
        var state = CompanionState()
        state.installBaselineSet = true
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dex-next-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let suite = "dex-next-\(UUID())"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        return CompanionStore(provider: LineProvider(tree: tree, indexed: indexed), clock: { clock.now },
                              fileURL: file, rng: SeededRNG(seed: 1), dittoDisguiseRollingEnabled: false,
                              defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
    }

    private func pets(_ s: CompanionStore) -> Int? { s.state.active?.evolution.pets }

    func testEveryPreEvolutionPageShowsEachSpecialStepOutOfIt() throws {
        let s = try store()
        var parents: Set<Int> = []
        for rule in EvolutionRules.all where !rule.paths.isEmpty || rule.selector != nil || rule.trade != nil {
            let from = try XCTUnwrap(rule.from, "\(rule.species)")
            let card = s.evolutionCards(for: from).first { $0.rule.species == rule.species }
            XCTAssertEqual(card?.isNextStep, true, "#\(from) page lacks the step into #\(rule.species) \(rule.covers)")
            XCTAssertNil(card?.context, "nobody is raised")
            parents.insert(from)
        }
        XCTAssertEqual(parents.count, 86)
        for parent in parents {
            let ids = s.evolutionCards(for: parent).map(\.id)
            XCTAssertEqual(ids.count, Set(ids).count, "#\(parent) has two cards with one id")
        }
    }

    func testRaisedMunchlaxPageShowsLivePetProgressTowardSnorlax() async throws {
        let clock = FakeClock()
        let s = try store(clock: clock)
        await s.loadSpeciesIndexIfNeeded()
        await s.hatch(baseID: 446)
        for _ in 0..<3 {
            clock.now.addTimeInterval(1)
            XCTAssertEqual(s.growByClick(), .counted(ClickGrowth.tokensPerClick))
        }
        let next = try XCTUnwrap(s.evolutionCards(for: 446).first { $0.rule.species == 143 })
        XCTAssertTrue(next.isNextStep)
        let progress = try XCTUnwrap(next.rule.paths.first?.first?.progress(in: try XCTUnwrap(next.context)))
        XCTAssertEqual(progress.have, 3)
        XCTAssertEqual(progress.need, 30)
        XCTAssertFalse(next.offersSkip, "the Pokédex page never changes state")

        let into = try XCTUnwrap(s.evolutionCards(for: 143).first)
        XCTAssertFalse(into.isNextStep)
        XCTAssertNotNil(into.context, "Snorlax's page shows the raised Munchlax's progress too")
    }

    func testHomeNextNodeOpensTheNextSpeciesPageEvenWhenUncaught() async throws {
        let s = try store()
        await s.loadSpeciesIndexIfNeeded()
        await s.hatch(baseID: 446)
        let nodes = s.lineNodes
        let ids = nodes.compactMap { if case .species(let id) = $0.content { id } else { nil } }
        XCTAssertEqual(ids, [446, 143])
        let links = s.dexLinkTargets(including: ids)
        let target = try XCTUnwrap(EvoLineView.dexLinkTarget(for: try XCTUnwrap(nodes.last), links: links))
        XCTAssertTrue(s.unownedDexSpecies.contains { $0.collectionID == target }, "Snorlax is not caught")
        XCTAssertNotNil(s.evolutionCards(for: 143).first?.context)
    }

    func testHomeBranchMarkerOpensTheRaisedPageWithEveryBranch() async throws {
        let s = try store(tree: eeveeLine, indexed: [133])
        await s.loadSpeciesIndexIfNeeded()
        await s.hatch(baseID: 133)
        let line = s.lineNodes
        let marker = try XCTUnwrap(line.last)
        guard case .mystery = marker.content else { return XCTFail("a branching line ends in the ? marker") }
        let links = s.dexLinkTargets(including: [133])
        let eevee = try XCTUnwrap(links[133])
        XCTAssertEqual(EvoLineView.dexLinkTarget(for: marker, links: links, line: line), eevee)
        XCTAssertNil(EvoLineView.dexLinkTarget(for: marker, links: links.filter { $0.key != 133 }, line: line),
                     "a page that does not link to itself keeps a dead ?")
        let cards = s.evolutionCards(for: 133)
        XCTAssertEqual(Set(cards.filter(\.isNextStep).map(\.rule.species)), [196, 197, 700])
        XCTAssertLessThanOrEqual(cards.filter { $0.context != nil }.count, 1, "only the planned branch is live")
    }

    func testTenClicksJustPastTheAutoclickerGuardGiveTenPets() async throws {
        let clock = FakeClock()
        let s = try store(clock: clock)
        await s.hatch(baseID: 446)
        let step = ClickGrowth.minInterval + 0.01
        for click in 1...10 {
            XCTAssertEqual(s.growByClick(), .counted(ClickGrowth.tokensPerClick), "click \(click)")
            clock.now.addTimeInterval(step)
        }
        XCTAssertEqual(pets(s), 10)
        clock.now.addTimeInterval(-step + ClickGrowth.minInterval / 2)
        XCTAssertEqual(s.growByClick(), .tooSoon, "the autoclicker guard stays")
        XCTAssertEqual(pets(s), 10)
    }
}
