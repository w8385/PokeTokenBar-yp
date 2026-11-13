import XCTest
@testable import PokeTokenBar

private struct FixtureStep {
    let species: Int
    let name: String
    let details: [[String: Any]]

    var signatures: [String?] {
        details.map {
            EvolutionRules.signature(trigger: $0["trigger"] as? String ?? "", keys: Set($0.keys), item: $0["item"] as? String)
        }
    }

    /// Steps with a plain level or stone detail still grow the old way; only the others need a rule.
    var gatedSignatures: Set<String>? {
        let all = signatures
        return all.contains { $0 == nil } ? nil : Set(all.compactMap { $0 })
    }
}

private func loadSteps() throws -> [FixtureStep] {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/evolution-steps.json")
    let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]] ?? []
    return raw.map {
        FixtureStep(species: $0["species"] as? Int ?? 0, name: $0["name"] as? String ?? "",
                    details: $0["details"] as? [[String: Any]] ?? [])
    }
}

private func node(_ id: Int) -> EvoNode { EvoNode(speciesID: id, children: []) }

private func traits(seed: UInt64 = 0, attackIV: Int, defenseIV: Int, nature: PokemonNature? = nil) -> EvolutionTraits {
    let ivs = PokemonIVs(hp: 0, attack: attackIV, defense: defenseIV, specialAttack: 0, specialDefense: 0, speed: 0)
    return EvolutionTraits(seed: seed, ivs: ivs, nature: nature)
}

final class EvolutionRulesTests: XCTestCase {
    func testEverySpecialStepInTheFixtureHasAnAppRule() throws {
        let steps = try loadSteps()
        XCTAssertGreaterThan(steps.count, 400)
        var unmapped: [String] = []
        for step in steps {
            guard let needed = step.gatedSignatures, !step.details.isEmpty else { continue }
            let covered = EvolutionRules.rule(for: step.species)?.covers ?? []
            for signature in needed where !covered.contains(signature) {
                unmapped.append("\(step.species) \(step.name): \(signature)")
            }
        }
        XCTAssertEqual(unmapped, [], "special evolution steps without an app condition")
    }

    func testEveryTradeStepKnowsItsParentAndItsHeldItemOrPartner() throws {
        let steps = Dictionary(uniqueKeysWithValues: try loadSteps().map { ($0.species, $0) })
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("Fixtures/evolution-steps.json")))
        let parents = Dictionary(uniqueKeysWithValues: (raw as? [[String: Any]] ?? []).compactMap { entry in
            (entry["species"] as? Int).flatMap { id in (entry["parent"] as? Int).map { (id, $0) } }
        })
        for rule in EvolutionRules.all {
            guard let trade = rule.trade else { continue }
            let step = try XCTUnwrap(steps[rule.species])
            XCTAssertEqual(rule.from, parents[rule.species], "\(rule.species) \(step.name)")
            let tradeDetails = step.details.filter { $0["trigger"] as? String == "trade" }
            XCTAssertFalse(tradeDetails.isEmpty, "\(rule.species) lists no trade")
            switch trade {
            case .plain:
                XCTAssertTrue(tradeDetails.contains { $0["held_item"] == nil && $0["trade_species"] == nil })
            case .holding(let kind):
                XCTAssertTrue(tradeDetails.contains { $0["held_item"] as? String == kind.evolutionHeldSlug },
                              "\(rule.species) \(kind)")
            case .partner(let id):
                XCTAssertTrue(tradeDetails.contains { ($0["trade_species"] as? String) != nil },
                              "\(rule.species) \(id)")
            }
        }
    }

    func testStepsWithoutAnyConditionAreListedOnPurpose() throws {
        let empty = Set(try loadSteps().filter { $0.details.isEmpty }.map(\.species))
        XCTAssertEqual(empty, EvolutionRules.unconditional)
    }

    func testRulesOnlyCoverSignaturesTheFixtureStillHas() throws {
        let bySpecies = Dictionary(uniqueKeysWithValues: try loadSteps().map { ($0.species, $0) })
        for rule in EvolutionRules.all {
            let step = try XCTUnwrap(bySpecies[rule.species], "rule for \(rule.species) has no step")
            let present = step.gatedSignatures ?? []
            XCTAssertNotNil(step.gatedSignatures, "\(rule.species) also grows by a plain level or stone")
            XCTAssertEqual(rule.covers.subtracting(present), [], "\(rule.species) covers a signature the step lacks")
            XCTAssertEqual(present.subtracting(rule.covers), [], "\(rule.species)")
        }
    }

    func testSignatureLeavesWhatTheXPLoopAlreadyReads() {
        func sig(_ trigger: String, _ keys: Set<String>, item: String? = nil) -> String? {
            EvolutionRules.signature(trigger: trigger, keys: keys.union(["version_group", "is_default", "min_level"]), item: item)
        }
        XCTAssertNil(sig("level-up", []))
        XCTAssertNil(sig("level-up", ["time_of_day"]))
        XCTAssertNil(sig("use-item", ["item"], item: "water-stone"))
        XCTAssertEqual(sig("use-item", ["item"], item: "tart-apple"), "use-item:tart-apple")
        XCTAssertEqual(sig("use-item", ["item", "time_of_day"], item: "peat-block"), "use-item:peat-block+time_of_day")
        XCTAssertEqual(sig("level-up", ["min_happiness", "time_of_day"]), "level-up+min_happiness+time_of_day")
        XCTAssertEqual(sig("trade", ["held_item"]), "trade+held_item")
        XCTAssertEqual(sig("shed", []), "shed")
    }

    func testEveryRuleHasSomethingToCheckOrChoose() {
        for rule in EvolutionRules.all {
            let gate = !rule.paths.isEmpty
            XCTAssertTrue(gate || rule.selector != nil || rule.formNotShown || rule.trade != nil, "\(rule.species) does nothing")
            XCTAssertFalse(rule.original.isEmpty, "\(rule.species) names no original condition")
            XCTAssertTrue(rule.paths.allSatisfy { !$0.isEmpty }, "\(rule.species) has an empty path")
        }
    }

    func testGatesThatDependOnBattlesOrRainCanAlwaysFallBackToTheStage() {
        for rule in EvolutionRules.all {
            let external = rule.paths.contains { path in
                path.contains { if case .battles = $0 { return true } else if case .tokenRain = $0 { return true } else { return false } }
            }
            guard external else { continue }
            XCTAssertTrue(rule.paths.contains { $0 == [.longStage(percent: 200)] }, "\(rule.species) can dead-end")
        }
    }

    func testTyrogueTakesAttackDefenseOrEqualBranchFromIVsAndNature() {
        let kids = [node(106), node(107), node(237)]
        func pick(_ t: EvolutionTraits?) -> [Int] { EvolutionRules.plannable(kids, traits: t).map(\.speciesID) }
        XCTAssertEqual(pick(traits(attackIV: 31, defenseIV: 0)), [106])
        XCTAssertEqual(pick(traits(attackIV: 0, defenseIV: 31)), [107])
        XCTAssertEqual(pick(traits(attackIV: 7, defenseIV: 7)), [237])
        XCTAssertEqual(pick(traits(attackIV: 2, defenseIV: 0)), [237], "Lv.20 stats floor to the same value")
        XCTAssertEqual(pick(traits(attackIV: 0, defenseIV: 0, nature: .lonely)), [106])
        XCTAssertEqual(pick(traits(attackIV: 0, defenseIV: 0, nature: .bold)), [107])
        XCTAssertEqual(pick(nil).count, 1)
    }

    func testWurmpleBranchFollowsTheSeedAndShedinjaIsNeverPlanned() {
        let wurmple = [node(266), node(268)]
        XCTAssertEqual(EvolutionRules.plannable(wurmple, traits: traits(seed: 4, attackIV: 0, defenseIV: 0)).map(\.speciesID), [266])
        XCTAssertEqual(EvolutionRules.plannable(wurmple, traits: traits(seed: 5, attackIV: 0, defenseIV: 0)).map(\.speciesID), [268])
        XCTAssertEqual(EvolutionRules.plannable([node(291), node(292)], traits: nil).map(\.speciesID), [291])
    }

    func testBranchesWithoutRulesAreUntouched() {
        let eevee = [134, 135, 136, 196, 197, 470, 471].map(node)
        let planned = EvolutionRules.plannable(eevee, traits: nil).map(\.speciesID)
        XCTAssertEqual(planned, [134, 135, 136, 196, 197, 470, 471])
        XCTAssertEqual(EvolutionRules.plannable([node(3)], traits: nil).map(\.speciesID), [3])
    }

    func testItemOnlyChildrenWaitForTheirItemUnlessNothingElseIsLeft() {
        XCTAssertEqual(EvolutionRules.plannable([node(212), node(900)], traits: nil).map(\.speciesID), [212])
        XCTAssertEqual(EvolutionRules.plannable([node(841), node(842), node(1011)], traits: nil).count, 3)
        XCTAssertEqual(EvolutionRules.plannable([node(901)], traits: nil).map(\.speciesID), [901])
        XCTAssertTrue(EvolutionRules.rule(for: 855)?.isItemOnly == true)
        XCTAssertFalse(EvolutionRules.rule(for: 892)?.isItemOnly == true, "the towers open Urshifu without an item")
        XCTAssertFalse(EvolutionRules.rule(for: 901)?.paths.isEmpty ?? true)
    }
}
