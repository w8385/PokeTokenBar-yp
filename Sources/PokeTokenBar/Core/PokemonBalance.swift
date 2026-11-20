import Foundation

/// The balance table. Every threshold, price and income rate the game uses is a number here, and the player sees
/// exactly these numbers, so rebalancing means editing a value in this file.
/// A line's graduation total T is the same for every line of a rarity; with k forms, form i costs T·i / (k(k+1)/2).
enum PokemonBalance {

    // MARK: Growth

    /// Tokens an egg needs to hatch. The excess carries over to the hatched Pokémon.
    static let eggHatchThreshold = 100_000

    static func graduationTotal(_ rarity: Rarity) -> Int {
        switch rarity {
        case .common:    return  15_000_000
        case .uncommon:  return  37_500_000
        case .rare:      return  60_000_000
        case .legendary: return 120_000_000
        }
    }

    /// A hatch from a line the player already graduated grows this many times faster.
    static let repeatGrowthMultiplier = 2

    // MARK: Income

    /// Time mode: growth tokens and shop tokens for each active second.
    static let timeTokensPerActiveSecond = 25_000
    /// Growth from one click or pat on the pet.
    static let tokensPerPet = 50_000
    /// Growth from one Rare Candy.
    static let rareCandyXP = 20_000_000

    // MARK: Prices

    enum Price {
        static let rareCandy = 10_000_000
        static let mint = 2_000_000
        static let shinyCharm = 60_000_000
        /// The first and the second Exp. Share.
        static let expShare = [60_000_000, 120_000_000]
        /// An egg with no rarity guarantee. Guaranteed eggs cost this × the rarity's graduation total ÷ common's.
        static let egg = 20_000_000
        static let scoutTicket = 60_000_000
        static let evolutionStone = 20_000_000
        static let heldItem = 60_000_000
        static let gem = 20_000_000
        static let burden = 5_000_000
        static let megaStone = 120_000_000
        static let formTool = 15_000_000
        static let abilityCapsule = 5_000_000
        static let abilityPatch = 20_000_000
        static let bottleCap = 5_000_000
        static let goldBottleCap = 30_000_000
        static let mirrorHerb = 5_000_000
        static let machineWeak = 4_000_000
        static let machineMid = 8_000_000
        static let machineStrong = 12_000_000
        /// Shop tokens Gimmighoul's Roaming Form needs spent before it evolves.
        static let gimmighoulSpend = 20_000_000
    }

    static func machinePrice(power: Int, isWeather: Bool) -> Int {
        if isWeather || power >= 100 { return Price.machineStrong }
        return power >= 70 ? Price.machineMid : Price.machineWeak
    }

    /// Tokens to the next stage or graduation from `stageIndex` (0-based).
    static func phaseThreshold(rarity: Rarity, totalForms k: Int, stageIndex: Int,
                               growthMultiplier: Int = 1) -> Int {
        let kk = max(1, k)
        let i = stageIndex + 1
        let total = Double(graduationTotal(rarity))
        let denom = Double(kk * (kk + 1)) / 2.0
        let standardThreshold = Int((total * Double(i) / denom).rounded())
        return max(1, Int((Double(standardThreshold) / Double(max(1, growthMultiplier))).rounded()))
    }

    // MARK: Time mode

    static func timeTokens(forActiveSeconds seconds: TimeInterval) -> Int {
        max(0, Int(seconds * Double(timeTokensPerActiveSecond)))
    }
    /// Input within this long counts as active.
    static let timeIdleLimit: TimeInterval = 5 * 60
    /// One tick never credits more than this, so a long gap (sleep, a stalled timer) cannot pay out.
    static let timeMaxStep: TimeInterval = 2 * 60
    /// Time mode writes the save at most this often; a break, a mode switch and quit write it at once.
    static let timeSaveInterval: TimeInterval = 30
    /// Token mode with no usage for this long offers the switch to time mode.
    static let idleTokenHintAfter: TimeInterval = 3 * 86400
    /// With no token usage for this long the companion turns its back (`CompanionStateKind.sulk`).
    static let sulkAfterIdle: TimeInterval = 3 * 3600

    // MARK: Save scale

    /// Which table scale a save's stage credits and profile growth are in (`CompanionState.economyVersion`).
    /// 1: the first tables. 2: ÷5. 3: ÷10 again, the former lowest difficulty baked in.
    static let economyVersion = 3
}
