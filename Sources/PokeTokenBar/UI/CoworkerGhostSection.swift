import SwiftUI

/// Battle tab, Battle sub-tab: the coworkers from the last upload reply, each a ghost of their last uploaded
/// party to fight at Lv50, and the result of the last fight through the gym views.
@MainActor
struct CoworkerGhostSection: View {
    let store: CompanionStore
    let info: BattleInfo?
    let entry: BattleEntryStore
    let service: GymService

    private var l: L { store.l }

    static func makeService(store: CompanionStore, uploader: PartyUploader) -> GymService {
        GymService(link: { uploader.gymLink }, badges: { store.state.gymBadges }, ownedTMs: { [] },
                   applyReward: { _, _, _ in }, claimCoworkerTrophy: { store.claimCoworkerTrophy($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let record = service.last {
                result(record)
            } else {
                Text(l.ghostHint).font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Spacing.lg).padding(.vertical, Spacing.md)
                Divider()
                if let empty = Self.emptyText(info, l) {
                    Text(empty).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Spacing.lg).padding(.vertical, Spacing.md)
                } else {
                    ForEach(Array(Self.fightable(info).enumerated()), id: \.offset) { index, coworker in
                        if index > 0 { Divider() }
                        row(coworker)
                    }
                }
                if let failure = service.failure { failureLine(failure) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The coworkers the bot gave an id; a bot from before ghosts gives none.
    static func fightable(_ info: BattleInfo?) -> [BattleInfo.Coworker] {
        (info?.coworkers ?? []).filter { $0.id != nil }
    }

    /// The line shown instead of the rows, nil when there is someone to fight.
    static func emptyText(_ info: BattleInfo?, _ l: L) -> String? {
        guard let info else { return l.battleInfoPending }
        if info.coworkers.isEmpty { return l.ghostEmpty }
        return fightable(info).isEmpty ? l.ghostBotTooOld : nil
    }

    private func row(_ coworker: BattleInfo.Coworker) -> some View {
        let beaten = coworker.id.map(store.state.coworkerTrophies.contains) ?? false
        return HStack(spacing: Spacing.md) {
            if let target = BattleInfo.spriteTarget(pokemonID: coworker.pokemonId) {
                SpriteView(speciesID: target.speciesID, size: 32, shiny: coworker.shiny, form: target.form,
                           female: target.female)
                    .frame(width: 32, height: 32)
            }
            Text(coworker.label(l)).lineLimit(1)
            if beaten { CoworkerTrophyMark(l: l) }
            Spacer(minLength: Spacing.xs)
            Button(l.gymChallenge) {
                Task { await service.fightCoworker(coworker, l: l, team: currentTeam) }
            }
            .controlSize(.small).disabled(service.inFlight != nil)
        }
        .padding(.horizontal, Spacing.lg).padding(.vertical, Spacing.sm)
        .frame(minHeight: 38)
    }

    private func result(_ record: GymFightRecord) -> some View {
        let coworker = Self.fightable(info).first { $0.id == record.coworkerID }
        return VStack(alignment: .leading, spacing: 0) {
            GymResultView(
                record: record, language: store.language, l: l, regionName: l.ghostTitle,
                tmName: { _ in nil }, primaryTitle: coworker == nil ? nil : l.gymRematch, busy: service.inFlight != nil,
                onPrimary: {
                    guard let coworker else { return }
                    Task { await service.fightCoworker(coworker, l: l, team: currentTeam) }
                },
                onClose: { service.dismissResult() },
                notes: record.trophy ? [l.ghostTrophyEarned(record.opponent.trainer.displayName(store.language))] : [])
            .id("\(record.outcome.gymId)-\(record.outcome.seed)")
            if let failure = service.failure { failureLine(failure) }
        }
    }

    private func failureLine(_ failure: GymService.Failure) -> some View {
        Text(l.gymFailure(failure)).font(.caption2).foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Spacing.lg).padding(.bottom, Spacing.md)
    }

    private var currentTeam: GymTeam.Team {
        GymTeam.team(state: store.state, slots: entry.slots, moveChoices: entry.moveChoices,
                     rentalSpeciesID: entry.rentalSpeciesID)
    }
}

/// The mark a coworker gets on the lists once their ghost has been beaten.
@MainActor
struct CoworkerTrophyMark: View {
    let l: L

    var body: some View {
        Image(systemName: "trophy.fill").font(.caption).foregroundStyle(.yellow)
            .help(l.ghostTrophy)
            .accessibilityLabel(l.ghostTrophy)
    }
}
