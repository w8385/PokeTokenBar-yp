import SwiftUI

/// A region's gyms in two columns, read left to right, top to bottom.
@MainActor
struct GymGrid<Cell: View>: View {
    static var columns: Int { 2 }

    let gyms: [GymOpponent]
    @ViewBuilder let cell: (GymOpponent) -> Cell

    static func rows<Item>(_ items: [Item]) -> [[Item]] {
        stride(from: 0, to: items.count, by: columns).map { Array(items[$0..<min($0 + columns, items.count)]) }
    }

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: Spacing.md, verticalSpacing: Spacing.lg) {
            ForEach(Array(Self.rows(gyms).enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(row) { cell($0).frame(maxWidth: .infinity, alignment: .topLeading) }
                }
            }
        }
        .padding(.horizontal, Spacing.lg).padding(.vertical, Spacing.md)
    }
}

/// One gym as a grid cell: its leader, the types they lean to, and the challenge button.
@MainActor
struct GymOpponentCard: View {
    let opponent: GymOpponent
    let language: AppLanguage
    let l: L
    let earned: Bool
    let fighting: Bool
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                TrainerSprite(battleID: opponent.id, size: 32)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(spacing: Spacing.xs) {
                        Text("\(opponent.index). \(opponent.trainer.displayName(language))")
                            .font(.callout.weight(.semibold)).lineLimit(1)
                        if earned { GymBadgeView(emblem: GymBadgeCase.emblem(for: opponent), earned: true, size: 14) }
                    }
                    if !opponent.types.isEmpty {
                        ViewThatFits(in: .horizontal) {
                            TypeBadges(types: opponent.types, language: language)
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                ForEach(opponent.types, id: \.self) { TypeBadges(types: [$0], language: language) }
                            }
                        }
                    }
                    Text(l.gymTeamLine(opponent.team.count, level: opponent.level))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Button(fighting ? l.gymFighting : (earned ? l.gymRematch : l.gymChallenge), action: action)
                .controlSize(.small)
                .disabled(disabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(opponent.trainer.displayLine(language))
    }
}

/// The Elite Four run or a hideout run: its trainers in order, the rule, and one button for the next battle.
@MainActor
struct GymRunRow: View {
    let title: String
    let subtitle: String?
    let emblem: GymEmblem
    let battles: [GymOpponent]
    let l: L
    let lockedReason: String?
    /// 1-based battle the run fights next; 1 when it has not started.
    let nextStep: Int
    let cleared: Bool
    let fighting: Bool
    let disabled: Bool
    let action: () -> Void

    private var started: Bool { nextStep > 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                GymBadgeView(emblem: emblem, earned: cleared, size: 22)
                Text(title).font(.callout.weight(.semibold))
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                Spacer()
            }
            HStack(spacing: Spacing.xs) {
                ForEach(Array(battles.enumerated()), id: \.element.id) { index, battle in
                    TrainerSprite(battleID: battle.id, size: 32)
                        .opacity(lockedReason != nil || index + 1 < nextStep ? 0.4 : 1)
                        .overlay {
                            if started, index + 1 == nextStep {
                                RoundedRectangle(cornerRadius: Radius.chip).stroke(Color.accentColor, lineWidth: 1.5)
                            }
                        }
                }
                if let finale = battles.last?.finale, finale > 0 {
                    Text("+\(finale) ?")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.secondary).monospacedDigit()
                        .help(l.gymFinaleHidden(finale))
                        .accessibilityLabel(l.gymFinaleHidden(finale))
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(lockedReason ?? (started ? l.gymRunStepLine(nextStep, of: battles.count) : l.gymRunRule))
                    .font(.caption2).foregroundStyle(lockedReason == nil ? .secondary : .tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Spacing.xs)
                Button(fighting ? l.gymFighting : (started ? l.gymRunContinue(nextStep) : l.gymRunStart), action: action)
                    .controlSize(.small)
                    .disabled(disabled || lockedReason != nil)
            }
        }
        .padding(.horizontal, Spacing.lg).padding(.vertical, Spacing.md)
    }
}

/// The region's hidden boss: a locked "???" until the champion falls, then a single battle like a gym.
@MainActor
struct GymHiddenRow: View {
    let opponent: GymOpponent
    let language: AppLanguage
    let l: L
    let unlocked: Bool
    let beaten: Bool
    let fighting: Bool
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: Spacing.lg) {
            if unlocked {
                TrainerSprite(battleID: opponent.id, size: 44)
            } else {
                GymBadgeView(emblem: .hidden, earned: false, size: 44)
            }
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(spacing: Spacing.xs) {
                    Text(unlocked ? opponent.trainer.displayName(language) : "???")
                        .font(.callout.weight(.semibold)).lineLimit(1)
                    Text(l.gymHiddenTitle).font(.caption).foregroundStyle(.secondary)
                    if beaten { GymBadgeView(emblem: .hidden, earned: true, size: 16) }
                }
                if unlocked {
                    HStack(spacing: Spacing.xs) {
                        Text(l.gymTeamLine(opponent.team.count, level: opponent.level))
                        if let finale = opponent.finale, finale > 0 {
                            Text("+\(finale) ?").monospacedDigit()
                                .help(l.gymFinaleHidden(finale))
                                .accessibilityLabel(l.gymFinaleHidden(finale))
                        }
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                }
                Text(unlocked ? l.gymHiddenRule : l.gymHiddenLocked)
                    .font(.caption2).foregroundStyle(unlocked ? .secondary : .tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Spacing.xs)
            Button(fighting ? l.gymFighting : (beaten ? l.gymRematch : l.gymChallenge), action: action)
                .controlSize(.small)
                .disabled(disabled || !unlocked)
        }
        .padding(.horizontal, Spacing.lg).padding(.vertical, Spacing.md)
        .help(unlocked ? opponent.trainer.displayLine(language) : l.gymHiddenLocked)
    }
}
