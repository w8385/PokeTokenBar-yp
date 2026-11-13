import Foundation

/// What one individual has done since it reached its current form. Resets at every evolution.
struct EvolutionProgress: Codable, Equatable, Sendable {
    var pets = 0
    var won = 0
    var lost = 0
    var played = 0
    var candies = 0
    /// `CompanionState.spentTokens` when the form began; `spent` requirements count from here.
    var spentBaseline = 0
    var flipped = false
    var spun = false
    var rained = false
    /// "darkness" or "waters" once Kubfu's tower is picked.
    var tower: String?
    /// Battles already counted, so a re-read of the recent-battle list adds nothing.
    var seenBattles: [String] = []
    /// Newest battle time already read; only later battles count, so the battles that were there when this
    /// feature arrived (or when the egg hatched) are not credited. Nil until the first read.
    var battleCursor: Date?

    static let seenBattleLimit = 200

    init(spentBaseline: Int = 0, seenBattles: [String] = [], battleCursor: Date? = nil) {
        self.spentBaseline = spentBaseline
        self.seenBattles = seenBattles
        self.battleCursor = battleCursor
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pets = c.lenient(Int.self, forKey: .pets, default: 0)
        won = c.lenient(Int.self, forKey: .won, default: 0)
        lost = c.lenient(Int.self, forKey: .lost, default: 0)
        played = c.lenient(Int.self, forKey: .played, default: 0)
        candies = c.lenient(Int.self, forKey: .candies, default: 0)
        spentBaseline = c.lenient(Int.self, forKey: .spentBaseline, default: 0)
        flipped = c.lenient(Bool.self, forKey: .flipped, default: false)
        spun = c.lenient(Bool.self, forKey: .spun, default: false)
        rained = c.lenient(Bool.self, forKey: .rained, default: false)
        tower = c.lenientOptional(String.self, forKey: .tower)
        seenBattles = c.lenient([String].self, forKey: .seenBattles, default: [])
        battleCursor = c.lenientOptional(Date.self, forKey: .battleCursor)
    }

    /// The next form starts clean, but battles already counted stay counted.
    func nextForm(spentBaseline: Int) -> EvolutionProgress {
        EvolutionProgress(spentBaseline: spentBaseline, seenBattles: seenBattles, battleCursor: battleCursor)
    }

    mutating func record(battle key: String, result: EvolutionRequirement.Tally) {
        guard !seenBattles.contains(key) else { return }
        seenBattles.append(key)
        if seenBattles.count > Self.seenBattleLimit { seenBattles.removeFirst(seenBattles.count - Self.seenBattleLimit) }
        played += 1
        if result == .won { won += 1 }
        if result == .lost { lost += 1 }
    }
}

/// Everything a requirement can look at, gathered once per check so the rules stay pure.
struct EvolutionContext: Sendable {
    var progress = EvolutionProgress()
    var period = DayPeriod.day
    var level = 5
    var knownMoves: Set<String> = []
    /// Level-up moves the species can ever learn; empty when its details are not loaded.
    var learnableMoves: Set<String> = []
    var heldItem: ItemKind?
    var bag: [ItemKind: Int] = [:]
    var friendLines: Set<Int> = []
    var friendTypes: Set<String> = []
    var friendCount = 0
    var spentTokens = 0
    var stageXP = 0
    var stageThreshold = 1
}

extension EvolutionRequirement {
    static let fairyMoves: Set<String> = [
        "baby-doll-eyes", "charm", "fairy-wind", "disarming-voice", "draining-kiss", "play-rough", "dazzling-gleam",
        "moonblast", "sweet-kiss", "misty-terrain", "fairy-lock", "geomancy", "light-of-ruin", "fleur-cannon",
        "moonlight", "alluring-voice", "spirit-break", "strange-steam", "decorate", "magical-torque",
    ]

    /// How far along, in whole numbers; booleans are 0 or 1 of 1.
    func progress(in ctx: EvolutionContext) -> (have: Int, need: Int) {
        switch self {
        case .pets(let n): return (ctx.progress.pets, n)
        case .time(let period): return (ctx.period == period ? 1 : 0, 1)
        case .knownMove(let name, let fallback):
            if ctx.knownMoves.contains(name) { return (1, 1) }
            return (!ctx.learnableMoves.contains(name) && ctx.level >= fallback ? 1 : 0, 1)
        case .knownFairyMove(let fallback):
            if !ctx.knownMoves.isDisjoint(with: Self.fairyMoves) { return (1, 1) }
            return (ctx.learnableMoves.isDisjoint(with: Self.fairyMoves) && ctx.level >= fallback ? 1 : 0, 1)
        case .holds(let kind): return (ctx.heldItem == kind ? 1 : 0, 1)
        case .bag(let kind): return (min(1, ctx.bag[kind] ?? 0), 1)
        case .friendLine(let id): return (ctx.friendLines.contains(id) ? 1 : 0, 1)
        case .friendType(let type): return (ctx.friendTypes.contains(type) ? 1 : 0, 1)
        case .anyFriend: return (ctx.friendCount > 0 ? 1 : 0, 1)
        case .flipped: return (ctx.progress.flipped ? 1 : 0, 1)
        case .spun: return (ctx.progress.spun ? 1 : 0, 1)
        case .tokenRain: return (ctx.progress.rained ? 1 : 0, 1)
        case .longStage(let percent):
            return (min(percent, ctx.stageXP * 100 / max(1, ctx.stageThreshold)), percent)
        case .battles(let tally, let n):
            switch tally {
            case .won: return (ctx.progress.won, n)
            case .lost: return (ctx.progress.lost, n)
            case .played: return (ctx.progress.played, n)
            }
        case .towerChosen: return (ctx.progress.tower != nil ? 1 : 0, 1)
        case .spent(let n): return (max(0, ctx.spentTokens - ctx.progress.spentBaseline), n)
        case .candies(let n): return (ctx.progress.candies, n)
        }
    }

    func isMet(in ctx: EvolutionContext) -> Bool {
        let (have, need) = progress(in: ctx)
        return have >= need
    }
}

extension EvolutionRule {
    /// The first path whose requirements all hold; nil while closed. A rule without paths never closes.
    func openPath(in ctx: EvolutionContext) -> [EvolutionRequirement]? {
        paths.isEmpty ? [] : paths.first { $0.allSatisfy { $0.isMet(in: ctx) } }
    }

    func isOpen(in ctx: EvolutionContext) -> Bool { openPath(in: ctx) != nil }

    /// Paths that use `kind` from the bag, with every other requirement still to hold.
    func path(usingBag kind: ItemKind) -> [EvolutionRequirement]? {
        paths.first { $0.contains(.bag(kind)) }
    }
}
