import SwiftUI

/// Coworkers tab: each tower mode's best streaks, the player's own row in bold. Hidden until the bot answers with one.
@MainActor
struct TowerRankingCard: View {
    let service: TowerService
    let l: L

    private var modes: [TowerMode] { TowerMode.allCases.filter { !(service.ranking[$0] ?? []).isEmpty } }

    var body: some View {
        Group {
            if modes.isEmpty {
                Color.clear.frame(height: 0)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(l.towerRankingTitle)
                        .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                        .textCase(.uppercase).padding(.leading, 4)
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        ForEach(modes, id: \.self) { modeList($0) }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .ptbCard()
                }
            }
        }
        .task { await service.load() }
    }

    private func modeList(_ mode: TowerMode) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(l.towerModeName(mode)).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(Array((service.ranking[mode] ?? []).enumerated()), id: \.offset) { index, rank in
                HStack(spacing: Spacing.sm) {
                    Text("\(index + 1)").font(.caption).monospacedDigit().foregroundStyle(.tertiary)
                        .frame(width: 16, alignment: .trailing)
                    Text(rank.name ?? l.battleUnnamed).font(.caption).fontWeight(rank.me == true ? .bold : .regular)
                        .lineLimit(1)
                    Spacer(minLength: Spacing.xs)
                    Text(l.towerBestStreak(rank.best)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
    }
}
