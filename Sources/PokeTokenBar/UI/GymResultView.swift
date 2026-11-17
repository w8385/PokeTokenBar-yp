import SwiftUI

/// A thin HP bar; green above half, orange above a fifth, red below. `nil` is a member that never fought.
@MainActor
struct GymHPBar: View {
    let hp: Int?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: Radius.bar).fill(Color.secondary.opacity(0.2))
                RoundedRectangle(cornerRadius: Radius.bar).fill(color)
                    .frame(width: proxy.size.width * CGFloat(max(0, min(100, hp ?? 0))) / 100)
            }
        }
        .frame(height: 4)
    }

    private var color: Color {
        switch hp ?? 0 {
        case 51...: .green
        case 21...: .orange
        default: .red
        }
    }
}

/// One side's six, as the battle left them: sprite, level and HP.
@MainActor
private struct GymTeamStrip: View {
    let title: String
    let fighters: [GymFighter]
    let l: L

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: Spacing.sm) {
                ForEach(Array(fighters.enumerated()), id: \.offset) { _, fighter in
                    VStack(spacing: Spacing.xxs) {
                        SpriteView(speciesID: fighter.pokemonId, size: 36, shiny: fighter.shiny)
                            .frame(width: 36, height: 36)
                            .grayscale(fighter.hp == 0 ? 1 : 0)
                        GymHPBar(hp: fighter.hp).frame(width: 34)
                        Text("Lv\(fighter.level)").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .opacity(fighter.hp == nil ? 0.3 : (fighter.hp == 0 ? 0.55 : 1))
                    .help(fighter.name)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(fighter.name), Lv\(fighter.level), \(status(fighter))")
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func status(_ fighter: GymFighter) -> String {
        guard let hp = fighter.hp else { return l.gymNeverSentOut }
        return hp == 0 ? l.gymFainted : "HP \(hp)%"
    }
}

/// The finished battle: who it was against, the outcome, any reward, both teams, and the turn log.
@MainActor
struct GymResultView: View {
    let record: GymFightRecord
    let language: AppLanguage
    let l: L
    let regionName: String
    let tmName: (Int) -> String?
    /// Nil when nothing follows (a won finale); otherwise what the main button does and says.
    let primaryTitle: String?
    let busy: Bool
    let onPrimary: () -> Void
    let onClose: () -> Void
    @State private var showsLog = false
    /// Nil when the bot sent no events; the result shows at once.
    @State private var replay: GymReplayPlayer?

    init(record: GymFightRecord, language: AppLanguage, l: L, regionName: String, tmName: @escaping (Int) -> String?,
         primaryTitle: String?, busy: Bool, onPrimary: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.record = record
        self.language = language
        self.l = l
        self.regionName = regionName
        self.tmName = tmName
        self.primaryTitle = primaryTitle
        self.busy = busy
        self.onPrimary = onPrimary
        self.onClose = onClose
        _replay = State(initialValue: GymReplay(record.outcome).map { GymReplayPlayer($0) })
    }

    private var outcome: GymBattleOutcome { record.outcome }
    private var revealed: Bool { replay?.finished ?? true }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.lg) {
                TrainerSprite(battleID: record.opponent.id, size: 56)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(record.opponent.trainer.displayName(language)).font(.headline).lineLimit(1)
                    Text(record.opponent.trainer.displayLine(language))
                        .font(.caption).foregroundStyle(.secondary).italic()
                        .fixedSize(horizontal: false, vertical: true)
                    if let run = outcome.run {
                        Text(l.gymRunStepLine(run.step, of: run.steps)).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            if let replay { GymReplayView(player: replay, outcome: outcome, l: l) }
            if revealed { summary }
            logToggle
            HStack {
                Button(l.gymClose, action: onClose).controlSize(.small)
                Spacer()
                if revealed, let primaryTitle {
                    Button(busy ? l.gymFighting : primaryTitle, action: onPrimary)
                        .controlSize(.small).keyboardShortcut(.defaultAction).disabled(busy)
                }
            }
        }
        .padding(.horizontal, Spacing.lg).padding(.vertical, Spacing.md)
    }

    /// Outcome, reward and both teams: held back until the replay ends so it does not give the result away.
    @ViewBuilder
    private var summary: some View {
        HStack(spacing: Spacing.sm) {
            Text(outcome.won ? l.gymWon : l.gymLost)
                .font(.callout.weight(.bold)).foregroundStyle(outcome.won ? Color.green : Color.red)
            Text(l.gymTurnCount(outcome.turns)).font(.caption).foregroundStyle(.secondary)
        }
        if let reward = record.reward { rewardLines(reward) }
        if outcome.won, outcome.run != nil, outcome.run?.next == nil { Text(l.gymRunCleared).font(.caption) }
        if !outcome.won, outcome.run != nil { Text(l.gymRunLostHint).font(.caption2).foregroundStyle(.secondary) }
        GymTeamStrip(title: l.gymYourTeam, fighters: outcome.playerTeam, l: l)
        GymTeamStrip(title: l.gymTheirTeam, fighters: outcome.foeTeam, l: l)
    }

    @ViewBuilder
    private func rewardLines(_ reward: GymReward) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(l.gymRewardLine(reward.kind)).font(.caption.weight(.semibold))
            if let moveID = reward.tmMoveID, let name = tmName(moveID) {
                Text(l.gymRewardTM(name)).font(.caption)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ptbPanel()
    }

    private var logToggle: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Button { showsLog.toggle() } label: {
                Label(showsLog ? l.gymHideLog : l.gymShowLog, systemImage: showsLog ? "chevron.up" : "chevron.down")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            if showsLog {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        ForEach(outcome.log, id: \.turn) { turn in
                            Text(l.gymTurnHeading(turn.turn)).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            ForEach(Array(turn.lines.enumerated()), id: \.offset) { _, line in
                                Text(line.text).font(.caption2).foregroundStyle(color(of: line.side))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .reservesScrollerLane()
                }
                .frame(maxHeight: 180)
                .padding(Spacing.md)
                .ptbPanel()
            }
        }
    }

    private func color(of side: Int?) -> Color {
        switch side {
        case 0: .accentColor
        case 1: .orange
        default: .secondary
        }
    }
}
