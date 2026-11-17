import SwiftUI

/// The battle played back on the result screen: the foe's member on top, the player's below, the last move between.
@MainActor
struct GymReplayView: View {
    let player: GymReplayPlayer
    let outcome: GymBattleOutcome
    let l: L
    var autoplay = true

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
                }
            }
            .buttonStyle(.borderless).controlSize(.small)
            VStack(spacing: Spacing.md) {
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
    }

    @ViewBuilder
    private func side(_ side: Int, frame: GymReplay.Frame, fighters: [GymFighter]) -> some View {
        let active = frame.active[side]
        let fighter = active.map { fighters[$0] }
        let hp = active.flatMap { frame.hp[side][$0] }
        let status = active.flatMap { frame.status[side][$0] }
        HStack(spacing: Spacing.md) {
            if side == 0 { sprite(fighter, back: true, fainted: hp == 0) }
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
            if side == 1 { sprite(fighter, back: false, fainted: hp == 0) }
        }
        .accessibilityElement(children: .combine)
    }

    private func sprite(_ fighter: GymFighter?, back: Bool, fainted: Bool) -> some View {
        ZStack {
            if let fighter {
                SpriteView(speciesID: fighter.pokemonId, size: 64, shiny: fighter.shiny, back: back)
                    .id("\(fighter.pokemonId)-\(back)")
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

    private func moveLine(_ frame: GymReplay.Frame) -> some View {
        let fighters = [outcome.playerTeam, outcome.foeTeam]
        let text = frame.lastMove.map { "\(fighters[$0.side][$0.member].name) › \($0.name)" } ?? " "
        return Text(text).font(.caption.weight(.semibold))
            .foregroundStyle(frame.lastMove.map { Self.sideColor($0.side) } ?? .secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .contentTransition(.opacity)
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
