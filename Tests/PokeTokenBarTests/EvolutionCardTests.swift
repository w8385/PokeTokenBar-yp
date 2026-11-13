import XCTest
@testable import PokeTokenBar

private func node(_ id: Int, _ children: [EvoNode] = []) -> EvoNode {
    EvoNode(speciesID: id, children: children, methods: [EvoMethod(trigger: "level-up")])
}

private struct CardProvider: PokeProviding {
    let tree: EvoNode
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: tree.speciesID, tree: tree, rarity: .common, names: [:])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class EvolutionCardTests: XCTestCase {
    nonisolated(unsafe) private var paths: [URL] = []
    nonisolated(unsafe) private var suites: [String] = []
    override func tearDown() {
        for path in paths { try? FileManager.default.removeItem(at: path) }
        for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) }
        super.tearDown()
    }

    private func store(tree: EvoNode, state: CompanionState = CompanionState()) throws -> CompanionStore {
        var state = state
        state.installBaselineSet = true
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("evo-card-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        paths.append(dir)
        let file = dir.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let suite = "evo-card-\(UUID())"
        suites.append(suite)
        return CompanionStore(provider: CardProvider(tree: tree), clock: { Date() }, fileURL: file,
                              rng: SeededRNG(seed: 1), dittoDisguiseRollingEnabled: false,
                              defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
    }

    private func inkay() throws -> CompanionStore {
        var state = CompanionState()
        state.active = MonState(baseID: 686, pathIDs: [686], plannedPathIDs: [686, 687], stageIndex: 0, usedAtStage: 0,
                                rarity: .common, totalForms: 2, profile: PokemonProfile.generate(seed: 7))
        return try store(tree: node(686, [node(687)]), state: state)
    }

    private func loadLine(_ s: CompanionStore) async {
        s.update(todayTokensByProvider: ["test": 0], todayDate: "d1", monthTotal: 0, burnTier: .idle,
                 limitWarning: false, hasUsageData: true)
        for _ in 0..<100 where s.currentLine == nil { await Task.yield() }
    }

    func testRaisedPokemonShowsItsWaitingStepWithLiveProgress() async throws {
        let s = try inkay()
        await loadLine(s)
        let card = try XCTUnwrap(s.evolutionCards(for: 686).first)
        XCTAssertTrue(card.isNextStep)
        XCTAssertEqual(card.rule.species, 687)
        let flip = try XCTUnwrap(card.rule.paths.first?.first)
        XCTAssertFalse(flip.isMet(in: try XCTUnwrap(card.context)))
        s.recordFlip()
        let after = try XCTUnwrap(s.evolutionCards(for: 686).first)
        XCTAssertTrue(flip.isMet(in: try XCTUnwrap(after.context)))
    }

    func testTargetSpeciesShowsTheStepIntoItWithProgressOnlyWhileItIsTheRaisedOnesNextForm() async throws {
        let raised = try inkay()
        await loadLine(raised)
        let live = try XCTUnwrap(raised.evolutionCards(for: 687).first)
        XCTAssertFalse(live.isNextStep)
        XCTAssertNotNil(live.context)

        let other = try store(tree: node(1, [node(2)]))
        await other.hatch(baseID: 1)
        let info = try XCTUnwrap(other.evolutionCards(for: 687).first)
        XCTAssertNil(info.context, "not on that step, so no progress to show")
    }

    func testSpeciesWithoutASpecialStepShowsNoCard() async throws {
        let s = try inkay()
        await loadLine(s)
        XCTAssertEqual(s.evolutionCards(for: 1).count, 0)
        XCTAssertEqual(s.evolutionCards(for: 2).count, 0)
    }

    func testEveryRuleIsTranslatedNotCopiedFromEnglish() {
        let name: (Int) -> String = { "#\($0)" }
        let en = L(.en)
        for language in AppLanguage.allCases where language != .en {
            let l = L(language)
            for rule in EvolutionRules.all {
                for original in rule.original {
                    XCTAssertNotEqual(l.evolutionOriginalText(original, speciesName: name),
                                      en.evolutionOriginalText(original, speciesName: name), "\(rule.species) \(language)")
                }
                for path in rule.paths {
                    XCTAssertNotEqual(l.evolutionPathText(path, speciesName: name),
                                      en.evolutionPathText(path, speciesName: name), "\(rule.species) \(language)")
                }
                if let selector = rule.selector {
                    XCTAssertNotEqual(l.evolutionSelectorText(selector), en.evolutionSelectorText(selector))
                }
            }
        }
    }
}
