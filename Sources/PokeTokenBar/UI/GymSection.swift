import SwiftUI

/// Battle tab, below the entry: gyms by region, the Elite Four run, the hideout run, the badge case and the
/// result of the last battle. Everything runs on the bot; the app sends the entry and keeps the rewards.
@MainActor
struct GymSection: View {
    let store: CompanionStore
    let entry: BattleEntryStore
    @State private var service: GymService

    private var l: L { store.l }
    private var language: AppLanguage { store.language }

    init(store: CompanionStore, uploader: PartyUploader, entry: BattleEntryStore, service: GymService? = nil) {
        self.store = store
        self.entry = entry
        _service = State(initialValue: service ?? GymService(
            link: { uploader.gymLink },
            badges: { store.state.gymBadges },
            ownedTMs: { MachineMove.ownedIDs(in: store.state.inventory) },
            applyReward: { reward, opponent, region in
                store.applyGymReward(reward, trainer: opponent.trainer.displayName(store.language), region: region.name)
            }))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let reason = service.unavailable {
                unavailableRow(reason)
            } else if let catalog = service.catalog {
                loaded(catalog)
            } else {
                Text(l.gymLoading).font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, Spacing.lg).padding(.vertical, Spacing.md)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await service.loadCatalog() }
    }

    private func unavailableRow(_ reason: GymService.Unavailable) -> some View {
        HStack(spacing: Spacing.md) {
            Text(l.gymUnavailable(reason)).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Spacing.xs)
            if reason == .unreachable {
                Button(l.gymRetry) { Task { await service.loadCatalog() } }.controlSize(.small)
            }
        }
        .padding(.horizontal, Spacing.lg).padding(.vertical, Spacing.md)
    }

    @ViewBuilder
    private func loaded(_ catalog: GymCatalog) -> some View {
        let region = catalog.region(service.session.regionID) ?? catalog.regions[0]
        let badges = store.state.gymBadges
        let team = currentTeam
        if let record = service.last {
            let fought = catalog.regions.first { $0.opponent(record.opponent.id) != nil } ?? region
            result(record, region: fought, team: team)
        } else if service.session.showsBadgeCase {
            header(catalog, region: region, badges: badges)
            Divider()
            GymBadgeCase(catalog: catalog, badges: badges, language: language, l: l)
        } else {
            header(catalog, region: region, badges: badges)
            Divider()
            ForEach(region.gyms) { gym in
                GymOpponentRow(opponent: gym, language: language, l: l,
                               earned: badges.hasGymBadge(region.id, index: gym.index),
                               fighting: service.inFlight == gym.id, disabled: service.inFlight != nil) {
                    Task { await service.fightGym(gym, region: region, team: team) }
                }
                Divider()
            }
            eliteRow(region, badges: badges, team: team)
            Divider()
            hideoutRow(region, badges: badges, team: team)
            if let failure = service.failure { failureLine(failure) }
        }
    }

    private func header(_ catalog: GymCatalog, region: GymRegion, badges: GymBadges) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.md) {
                if service.session.showsBadgeCase {
                    Text(l.gymBadgeCaseTitle).font(.callout.weight(.semibold))
                } else {
                    Picker(l.gymRegionLabel, selection: Bindable(service.session).regionID) {
                        ForEach(catalog.regions) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden().fixedSize().disabled(service.inFlight != nil)
                    Text(l.gymBadgeProgress(badges.badgeCount(region.id), of: GymBadges.gymsPerRegion))
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                Button {
                    service.session.showsBadgeCase.toggle()
                } label: {
                    Label(service.session.showsBadgeCase ? l.gymClose : l.gymBadgeCaseTitle,
                          systemImage: service.session.showsBadgeCase ? "xmark" : "rosette")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
            if !service.session.showsBadgeCase {
                Text(l.gymTeamNote).font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Spacing.lg).padding(.vertical, Spacing.md)
    }

    private func eliteRow(_ region: GymRegion, badges: GymBadges, team: GymTeam.Team) -> some View {
        let open = badges.eliteOpen(region)
        return GymRunRow(
            title: l.gymEliteTitle, subtitle: nil, emblem: .hallOfFame, battles: region.elite.battles, l: l,
            lockedReason: open ? nil : l.gymEliteLocked(have: badges.badgeCount(region.id), needed: region.elite.badgesNeeded),
            nextStep: service.nextStep(of: region.elite.run, battles: region.elite.battles, team: team),
            cleared: badges.region(region.id).hallOfFame,
            fighting: region.elite.battles.contains { $0.id == service.inFlight },
            disabled: service.inFlight != nil) {
            Task { await service.fightRun(region.elite.run, battles: region.elite.battles, region: region, team: team) }
        }
    }

    private func hideoutRow(_ region: GymRegion, badges: GymBadges, team: GymTeam.Team) -> some View {
        GymRunRow(
            title: l.gymHideoutTitle, subtitle: region.hideout.org.displayName(language), emblem: .org,
            battles: region.hideout.battles, l: l, lockedReason: nil,
            nextStep: service.nextStep(of: region.hideout.run, battles: region.hideout.battles, team: team),
            cleared: badges.region(region.id).orgBeaten,
            fighting: region.hideout.battles.contains { $0.id == service.inFlight },
            disabled: service.inFlight != nil) {
            Task { await service.fightRun(region.hideout.run, battles: region.hideout.battles, region: region, team: team) }
        }
    }

    private func result(_ record: GymFightRecord, region: GymRegion, team: GymTeam.Team) -> some View {
        let opponent = record.opponent
        let outcome = record.outcome
        let primary: String? = {
            guard let run = opponent.run else { return l.gymRematch }
            if !outcome.won { return l.gymRestartRun }
            if outcome.run?.next == nil { return nil }
            let battles = run.id == region.elite.run ? region.elite.battles : region.hideout.battles
            return service.nextStep(of: run.id, battles: battles, team: team) == 1 ? l.gymRestartRun : l.gymNextBattle
        }()
        return VStack(alignment: .leading, spacing: 0) {
            GymResultView(
                record: record, language: language, l: l, regionName: region.name,
                tmName: { id in MachineCatalog.moves.first { $0.id == id }?.name(language) },
                primaryTitle: primary, busy: service.inFlight != nil,
                onPrimary: {
                    Task {
                        if let run = opponent.run {
                            let battles = run.id == region.elite.run ? region.elite.battles : region.hideout.battles
                            await service.fightRun(run.id, battles: battles, region: region, team: team)
                        } else {
                            await service.fightGym(opponent, region: region, team: team)
                        }
                    }
                },
                onClose: { service.dismissResult() })
            .id("\(outcome.gymId)-\(outcome.seed)")
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
