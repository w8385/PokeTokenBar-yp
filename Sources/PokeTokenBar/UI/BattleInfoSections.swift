import SwiftUI

/// Battle tab lists from the bot's last upload reply: the user's recent battles and the coworkers' lead Pokémon.
@MainActor
struct BattleInfoSections: View {
    let info: BattleInfo?
    let l: L

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            section(l.battleRecentTitle) {
                if let empty = Self.recentEmptyText(info, l) {
                    emptyRow(empty)
                } else {
                    ForEach(Array((info?.recentBattles ?? []).enumerated()), id: \.offset) { index, battle in
                        if index > 0 { Divider() }
                        battleRow(battle)
                    }
                }
            }
            section(l.battleCoworkersTitle) {
                if let empty = Self.coworkersEmptyText(info, l) {
                    emptyRow(empty)
                } else {
                    ForEach(Array((info?.coworkers ?? []).enumerated()), id: \.offset) { index, coworker in
                        if index > 0 { Divider() }
                        coworkerRow(coworker)
                    }
                }
            }
        }
    }

    /// The empty-state line, nil when there are battles to list. No reply yet reads differently from an empty list.
    static func recentEmptyText(_ info: BattleInfo?, _ l: L) -> String? {
        guard let info else { return l.battleInfoPending }
        return info.recentBattles.isEmpty ? l.battleRecentEmpty : nil
    }

    static func coworkersEmptyText(_ info: BattleInfo?, _ l: L) -> String? {
        guard let info else { return l.battleInfoPending }
        return info.coworkers.isEmpty ? l.battleCoworkersEmpty : nil
    }

    private func battleRow(_ battle: BattleInfo.RecentBattle) -> some View {
        row {
            sprite(battle.myPokemonId, size: 32)
            Text("vs").font(.caption2).foregroundStyle(.tertiary)
            sprite(battle.opponentPokemonId, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(battle.opponentName ?? l.battleUnnamed).lineLimit(1)
                HStack(spacing: 6) {
                    Text(battle.isWin ? l.battleWin : l.battleLoss)
                        .foregroundStyle(battle.isWin ? Color.green : Color.orange)
                    if let turns = battle.turns { Text(l.battleTurns(turns)) }
                    if let date = battle.date {
                        Text(date, format: .dateTime.month().day().hour().minute())
                    }
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func coworkerRow(_ coworker: BattleInfo.Coworker) -> some View {
        row {
            sprite(coworker.pokemonId, size: 32, shiny: coworker.shiny)
            Text(coworker.name ?? l.battleUnnamed).lineLimit(1)
            Spacer(minLength: 4)
            Text("\(coworker.shiny ? "✨ " : "")Lv\(coworker.level)")
                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func sprite(_ pokemonID: Int?, size: CGFloat, shiny: Bool = false) -> some View {
        if let pokemonID, let target = BattleInfo.spriteTarget(pokemonID: pokemonID) {
            SpriteView(speciesID: target.speciesID, size: size, shiny: shiny, form: target.form)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "questionmark")
                .foregroundStyle(.tertiary)
                .frame(width: size, height: size)
        }
    }

    private func emptyRow(_ text: String) -> some View {
        row { Text(text).font(.caption).foregroundStyle(.secondary); Spacer(minLength: 0) }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                .textCase(.uppercase).padding(.leading, 4)
            VStack(spacing: 0) { content() }
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1))
        }
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10) { content() }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .frame(minHeight: 38)
    }
}
