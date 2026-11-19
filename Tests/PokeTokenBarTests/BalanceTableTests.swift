import XCTest
@testable import PokeTokenBar

/// The tables are the v2 tables at the former lowest slider (0.1), so a player who had 0.1 sees the same numbers.
@MainActor
final class BalanceTableTests: XCTestCase {
    private static let lowestSlider = 0.1

    /// The v2 app's `scaled(base, by: 0.1)`.
    private func atLowestSlider(_ v2: Int) -> Int { max(1, Int((Double(v2) * Self.lowestSlider).rounded())) }

    private func v2PhaseThreshold(_ rarity: Rarity, forms k: Int, stage: Int, multiplier: Int) -> Int {
        let total = v2Total(rarity)
        let standard = Int((total * Double(stage + 1) / (Double(k * (k + 1)) / 2)).rounded())
        return max(1, Int((Double(standard) / Double(multiplier)).rounded()))
    }

    func testEveryFormerlyScaledValueIsTheV2ValueAtTheLowestSlider() {
        let pairs: [(String, Int, Int)] = [
            ("egg hatch", PokemonBalance.eggHatchThreshold, 1_000_000),
            ("rare candy", RareCandy.price, 100_000_000),
            ("mint", Mint.price, 20_000_000),
            ("shiny charm", ShinyCharm.price, 600_000_000),
            ("exp share 1", ExpShare.prices[0], 600_000_000),
            ("exp share 2", ExpShare.prices[1], 1_200_000_000),
            ("fresh egg", FreshEgg.price, 200_000_000),
            ("scout ticket", ScoutTicket.price, 600_000_000),
            ("evolution stone", EvolutionStone.price, 200_000_000),
            ("held item", HeldItem.price, 600_000_000),
            ("mega stone", MegaStone.price, 1_200_000_000),
            ("form tool", FormTool.price, 150_000_000),
            ("ability capsule", AbilityCapsule.price, 50_000_000),
            ("ability patch", AbilityPatch.price, 200_000_000),
            ("bottle cap", BottleCap.price, 50_000_000),
            ("gold bottle cap", BottleCap.goldPrice, 300_000_000),
            ("mirror herb", MirrorHerb.price, 50_000_000),
            ("weak machine", PokemonBalance.machinePrice(power: 40, isWeather: false), 40_000_000),
            ("mid machine", PokemonBalance.machinePrice(power: 80, isWeather: false), 80_000_000),
            ("strong machine", PokemonBalance.machinePrice(power: 120, isWeather: false), 120_000_000),
            ("weather machine", PokemonBalance.machinePrice(power: 0, isWeather: true), 120_000_000),
        ]
        for (name, now, v2) in pairs {
            XCTAssertEqual(now, atLowestSlider(v2), name)
        }
        XCTAssertEqual(EvolutionRules.rule(for: 1000)?.paths, [[.spent(atLowestSlider(200_000_000))]], "Gholdengo")
        for rarity in Rarity.allCases {
            XCTAssertEqual(PokemonBalance.graduationTotal(rarity), atLowestSlider(Int(v2Total(rarity))))
        }
    }

    private func v2Total(_ rarity: Rarity) -> Double {
        switch rarity {
        case .common: 150_000_000
        case .uncommon: 375_000_000
        case .rare: 600_000_000
        case .legendary: 1_200_000_000
        }
    }

    func testStageThresholdsMatchTheLowestSliderForEveryReachableLine() {
        for rarity in Rarity.allCases {
            for forms in 1...5 {
                for stage in 0..<forms {
                    for multiplier in [1, PokemonBalance.repeatGrowthMultiplier] {
                        XCTAssertEqual(
                            PokemonBalance.phaseThreshold(rarity: rarity, totalForms: forms, stageIndex: stage,
                                                          growthMultiplier: multiplier),
                            atLowestSlider(v2PhaseThreshold(rarity, forms: forms, stage: stage, multiplier: multiplier)),
                            "\(rarity) \(forms) forms, stage \(stage), ×\(multiplier)")
                    }
                }
            }
        }
    }

    func testValuesThatWereNeverScaledStay() {
        XCTAssertEqual(RareCandy.xp, 20_000_000)
    }

    func testTimeModeAndPettingRates() {
        XCTAssertEqual(PokemonBalance.timeTokensPerActiveSecond, 25_000)
        XCTAssertEqual(PokemonBalance.timeTokens(forActiveSeconds: 1), 25_000)
        XCTAssertEqual(ClickGrowth.tokensPerClick, 50_000)
    }

    func testFirstRunEggHintShowsTheHatchPoint() {
        for language in AppLanguage.allCases {
            let hint = L(language).eggFirstRunHint(TokenFormatter.compact(PokemonBalance.eggHatchThreshold))
            XCTAssertTrue(hint.contains("100K"), "\(language.rawValue): \(hint)")
        }
    }

    func testTimeHintNamesTheRateInEveryLanguage() {
        for language in AppLanguage.allCases {
            XCTAssertTrue(L(language).growthModeTimeHint.contains("25K"), language.rawValue)
        }
    }
}
