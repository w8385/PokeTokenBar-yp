import SwiftUI

/// Every region's eight gym badges, the Hall of Fame mark and the hideout mark.
@MainActor
struct GymBadgeCase: View {
    let catalog: GymCatalog
    let badges: GymBadges
    let language: AppLanguage
    let l: L

    static func emblem(for gym: GymOpponent) -> GymEmblem {
        .type(gym.types.first.flatMap { PokemonType(apiName: $0) } ?? .normal)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            ForEach(catalog.regions) { region in
                let owned = badges.region(region.id)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack {
                        Text(l.gymRegionName(region)).font(.caption.weight(.semibold))
                        Spacer()
                        Text(l.gymBadgeProgress(owned.gyms.count, of: GymBadges.gymsPerRegion))
                            .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    }
                    HStack(spacing: Spacing.xs) {
                        ForEach(region.gyms) { gym in
                            let earned = owned.gyms.contains(gym.index)
                            GymBadgeView(emblem: Self.emblem(for: gym), earned: earned, size: 24)
                                .help(gym.trainer.displayName(language))
                                .accessibilityElement()
                                .accessibilityLabel("\(gym.trainer.displayName(language)): \(earned ? l.gymBadgeEarned : l.gymBadgeLocked)")
                        }
                        Spacer(minLength: Spacing.xs)
                        GymBadgeView(emblem: .hallOfFame, earned: owned.hallOfFame, size: 24)
                            .help(l.gymHallOfFame)
                            .accessibilityElement()
                            .accessibilityLabel("\(l.gymHallOfFame): \(owned.hallOfFame ? l.gymBadgeEarned : l.gymBadgeLocked)")
                        GymBadgeView(emblem: .org, earned: owned.orgBeaten, size: 24)
                            .help(region.hideout.org.displayName(language))
                            .accessibilityElement()
                            .accessibilityLabel("\(region.hideout.org.displayName(language)): \(owned.orgBeaten ? l.gymBadgeEarned : l.gymBadgeLocked)")
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.lg).padding(.vertical, Spacing.md)
    }
}
