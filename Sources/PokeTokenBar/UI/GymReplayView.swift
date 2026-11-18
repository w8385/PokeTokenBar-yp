import SwiftUI

/// The battle played back on the result screen: the foe's member on top, the player's below, the last move between.
@MainActor
struct GymReplayView: View {
    let player: GymReplayPlayer
    let outcome: GymBattleOutcome
    let l: L
    var autoplay = true
    /// Shown where Fast and Skip were once the replay is over: the result screen's next step.
    var next: Next? = nil
    @Environment(\.pokemonNameProvider) private var nameProvider
    @Environment(\.pokemonNameStore) private var injectedNames

    private var names: PokemonNameDisplayStore { injectedNames ?? .shared }

    var body: some View {
        let frame = player.frame
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Text(frame.turn == 0 ? l.gymReplayStart : l.gymTurnHeading(frame.turn))
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary).monospacedDigit()
                Spacer(minLength: 0)
                if !player.finished {
                    Button { player.toggleSpeed() } label: {
                        Label(l.gymReplayFast, systemImage: "forward.fill").labelStyle(.iconOnly)
                            .foregroundStyle(player.fast ? Color.accentColor : .secondary)
                    }
                    .help(l.gymReplayFast)
                    Button { withAnimation { player.skip() } } label: {
                        Label(l.gymReplaySkip, systemImage: "forward.end.fill").font(.caption)
                    }
                } else if let next {
                    Button(next.title, action: next.action)
                        .buttonStyle(.bordered).keyboardShortcut(.defaultAction).disabled(next.busy)
                }
            }
            .buttonStyle(.borderless).controlSize(.small)
            VStack(spacing: Spacing.md) {
                if frame.finale { finaleBanner }
                side(1, frame: frame, fighters: outcome.foeTeam)
                moveLine(frame)
                side(0, frame: frame, fighters: outcome.playerTeam)
            }
            .padding(Spacing.md)
            .ptbPanel()
        }
        .task {
            guard autoplay else { return }
            await player.play { withAnimation(.easeOut(duration: 0.25)) { player.advance() } }
        }
        .task {
            await MoveName.load(ids: (outcome.events ?? []).compactMap(\.moveId), store: names, provider: nameProvider)
        }
    }

    struct Next {
        let title: String
        let busy: Bool
        let action: () -> Void
    }

    @ViewBuilder
    private func side(_ side: Int, frame: GymReplay.Frame, fighters: [GymFighter]) -> some View {
        let active = frame.active[side]
        let fighter = active.map { fighters[$0] }
        let hp = active.flatMap { frame.hp[side][$0] }
        let status = active.flatMap { frame.status[side][$0] }
        let spriteID = active.map { frame.spriteID(side: side, member: $0, roster: fighters) }
        HStack(spacing: Spacing.md) {
            if side == 0 { sprite(fighter, id: spriteID, back: true, fainted: hp == 0) }
            VStack(alignment: side == 0 ? .trailing : .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    Text(fighter?.name ?? " ").font(.callout.weight(.semibold)).lineLimit(1)
                    if let fighter { Text("Lv\(fighter.level)").font(.caption).foregroundStyle(.secondary).monospacedDigit() }
                    if let status, hp != 0 {
                        Text(l.moveAilment(status)).font(.caption2.weight(.semibold))
                            .foregroundStyle(status == "paralysis" ? Color.black : .white)
                            .padding(.horizontal, Spacing.xs)
                            .background(Capsule().fill(Self.color(of: status)))
                    }
                }
                HStack(spacing: Spacing.sm) {
                    GymHPBar(hp: hp)
                    Text(hp.map { "\($0)%" } ?? "").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                        .frame(width: 32, alignment: .trailing)
                }
                pips(side, frame: frame, count: fighters.count)
            }
            .frame(maxWidth: .infinity, alignment: side == 0 ? .trailing : .leading)
            if side == 1 { sprite(fighter, id: spriteID, back: false, fainted: hp == 0) }
        }
        .accessibilityElement(children: .combine)
    }

    private func sprite(_ fighter: GymFighter?, id: Int?, back: Bool, fainted: Bool) -> some View {
        ZStack {
            if let fighter, let id {
                SpriteView(speciesID: id, size: 64, shiny: fighter.shiny, back: back)
                    .id("\(id)-\(back)")
                    .transition(.opacity)
            }
        }
        .frame(width: 64, height: 64)
        .grayscale(fainted ? 1 : 0)
        .opacity(fainted ? 0.4 : 1)
    }

    /// One dot a member: filled while it can still fight, hollow once it has fainted.
    private func pips(_ side: Int, frame: GymReplay.Frame, count: Int) -> some View {
        HStack(spacing: Spacing.xxs) {
            ForEach(0..<count, id: \.self) { member in
                Circle()
                    .fill(frame.hp[side][member] == 0 ? Color.secondary.opacity(0.25) : Self.sideColor(side))
                    .frame(width: 6, height: 6)
            }
        }
    }

    private var finaleBanner: some View {
        Label(l.gymFinaleEntrance, systemImage: "sparkles")
            .font(.caption.weight(.bold)).foregroundStyle(Self.sideColor(1))
            .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.xs)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: Radius.chip).fill(Self.sideColor(1).opacity(0.15)))
            .transition(.opacity)
            .accessibilityAddTraits(.isHeader)
    }

    private func moveLine(_ frame: GymReplay.Frame) -> some View {
        Text(Self.moveText(frame.lastMove, outcome: outcome, language: l.lang, names: names.names))
            .font(.caption.weight(.semibold))
            .foregroundStyle(frame.lastMove.map { Self.sideColor($0.side) } ?? .secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .contentTransition(.opacity)
    }

    static func moveText(_ move: GymReplay.Move?, outcome: GymBattleOutcome, language: AppLanguage,
                         names: [PokemonNameResource: [String: String]]) -> String {
        guard let move else { return " " }
        let fighter = [outcome.playerTeam, outcome.foeTeam][move.side][move.member]
        return "\(fighter.name) › \(MoveName.text(id: move.id, botName: move.name, language: language, names: names))"
    }

    private static func sideColor(_ side: Int) -> Color { side == 0 ? .accentColor : .orange }

    private static func color(of status: String) -> Color {
        switch status {
        case "burn": .red
        case "poison", "toxic": .purple
        case "sleep": .gray
        case "freeze": .cyan
        default: .yellow
        }
    }
}
