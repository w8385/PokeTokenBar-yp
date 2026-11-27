import SwiftUI

/// Battle tab, Tower sub-tab: 3-on-3 streaks at Lv50 against the tower's trainers. The bot owns the run; the app
/// keeps the BP, the entry and a mirror of each mode's record.
@MainActor
struct TowerSection: View {
    let store: CompanionStore
    let entry: BattleEntryStore
    let service: TowerService
    /// Opens the picker for tower entry slot `slot` (0-based).
    let onPickSlot: (Int) -> Void

    private var l: L { store.l }
    private var language: AppLanguage { store.language }
    private var tower: TowerProgress { store.state.tower }

    static func makeService(store: CompanionStore, uploader: PartyUploader) -> TowerService {
        TowerService(link: { uploader.gymLink }, apply: { run, gain in store.applyTower(run, gain: gain) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let reason = service.unavailable {
                unavailableRow(reason)
            } else if let outcome = service.last {
                result(outcome)
            } else if service.runs.isEmpty {
                Text(l.towerLoading).font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, Spacing.lg).padding(.vertical, Spacing.md)
            } else {
                home
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await service.load() }
    }

    private func unavailableRow(_ reason: GymService.Unavailable) -> some View {
        HStack(spacing: Spacing.md) {
            Text(l.gymUnavailable(reason)).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Spacing.xs)
            if reason == .unreachable {
                Button(l.gymRetry) { Task { await service.load() } }.controlSize(.small)
            }
        }
        .padding(.horizontal, Spacing.lg).padding(.vertical, Spacing.md)
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            header
            recordLines(service.mode)
            entryPanel
            if let failure = service.failure {
                Text(l.towerFailure(failure)).font(.caption2).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Spacing.lg).padding(.vertical, Spacing.md)
    }

    private var header: some View {
        HStack(spacing: Spacing.md) {
            Text(l.towerModeName(service.mode)).font(.callout.weight(.semibold))
            Spacer()
            Text(l.towerBP(tower.bp)).font(.callout.weight(.semibold)).monospacedDigit()
        }
    }

    private func recordLines(_ mode: TowerMode) -> some View {
        let record = tower.record(mode)
        return VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(spacing: Spacing.sm) {
                Text(l.towerStreak(record.streak, best: record.best)).font(.caption).monospacedDigit()
                ForEach(record.trophies, id: \.self) { trophy in
                    Image(systemName: "trophy.fill").font(.caption)
                        .foregroundStyle(trophy == "gold" ? Color.yellow : Color.secondary)
                        .help(l.towerTrophyName(trophy))
                }
            }
            if let next = service.runs[mode]?.next {
                Text(l.towerNext(next)).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var entryPanel: some View {
        let members = TowerEntry.members(state: store.state, ids: tower.entry)
        let locked = tower.entryLocked
        let team = TowerEntry.team(state: store.state, ids: tower.entry, moveChoices: entry.moveChoices)
        let next = service.runs[.entry]?.next.battle ?? tower.record(.entry).streak + 1
        return VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                ForEach(0..<TowerProgress.teamSize, id: \.self) { slot in
                    slotCard(slot < members.count ? members[slot] : nil, slot: slot, locked: locked)
                }
            }
            Text(locked ? l.towerEntryLocked : l.towerEntryNote).font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            if team == nil, !locked {
                Text(l.towerNeedsThree).font(.caption2).foregroundStyle(.secondary)
            }
            HStack {
                if tower.record(.entry).streak > 0 {
                    Button(l.towerQuit) { Task { await service.quit(.entry) } }
                        .controlSize(.small).disabled(service.busy)
                }
                Spacer()
                Button(service.busy ? l.gymFighting : l.towerChallenge(next)) {
                    Task { await service.fight(.entry, team: team) }
                }
                .controlSize(.small).buttonStyle(.borderedProminent)
                .disabled(team == nil || service.busy)
            }
        }
    }

    private func slotCard(_ member: BattleCandidate?, slot: Int, locked: Bool) -> some View {
        Button { onPickSlot(slot) } label: {
            VStack(spacing: Spacing.xxs) {
                if let member {
                    let dexEntry = store.dexEntry(for: member)
                    SpriteView(speciesID: member.speciesID, size: 44, shiny: member.member.shiny,
                               form: dexEntry?.form, female: dexEntry?.profile?.gender == .female)
                        .frame(width: 44, height: 44)
                    Text("Lv\(BattleEntry.battleLevel)").font(.caption2).foregroundStyle(.secondary)
                } else {
                    Image(systemName: "plus.circle").font(.title3).foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                    Text(l.towerEmptySlot).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, Spacing.sm)
            .contentShape(Rectangle())
            .ptbPanel()
        }
        .buttonStyle(.plain)
        .disabled(locked || service.busy)
    }

    private func result(_ outcome: TowerOutcome) -> some View {
        let mode = TowerMode(rawValue: outcome.run.mode) ?? .entry
        var notes: [String] = []
        if outcome.gain.bp > 0 { notes.append(l.towerEarned(outcome.gain.bp)) }
        if let trophy = outcome.gain.trophy { notes.append(l.towerTrophyEarned(trophy)) }
        if !outcome.battle.won { notes.append(l.towerStreakEnded(outcome.gain.battle - 1)) }
        let team = TowerEntry.team(state: store.state, ids: tower.entry, moveChoices: entry.moveChoices)
        let primary: String? = outcome.battle.won ? l.towerNextBattle : (mode == .entry && team != nil ? l.gymRematch : nil)
        return VStack(alignment: .leading, spacing: 0) {
            GymResultView(
                record: GymFightRecord(opponent: outcome.opponent, outcome: outcome.battle, reward: nil),
                language: language, l: l, regionName: l.towerTitle,
                tmName: { _ in nil }, primaryTitle: primary, busy: service.busy,
                onPrimary: { Task { await service.fight(mode, team: team) } },
                onClose: { service.dismissResult() }, notes: notes)
            .id("\(outcome.battle.gymId)-\(outcome.battle.seed)")
            if let failure = service.failure {
                Text(l.towerFailure(failure)).font(.caption2).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Spacing.lg).padding(.bottom, Spacing.md)
            }
        }
    }
}
