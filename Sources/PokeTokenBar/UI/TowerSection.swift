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

    @State private var picked: [Int] = []
    @State private var give: Int?
    @State private var take: Int?

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
            switch service.mode {
            case .entry: entryPanel
            case .rental: rentalPanel
            }
            if let failure = service.failure {
                Text(l.towerFailure(failure)).font(.caption2).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Spacing.lg).padding(.vertical, Spacing.md)
    }

    private var header: some View {
        HStack(spacing: Spacing.md) {
            Picker("", selection: Binding(get: { service.mode }, set: { service.mode = $0 })) {
                ForEach(TowerMode.allCases, id: \.self) { Text(l.towerModeName($0)).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize().controlSize(.small)
            .disabled(service.busy)
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

    private var rentalPanel: some View {
        let run = service.runs[.rental]
        let next = run?.next.battle ?? tower.record(.rental).streak + 1
        return VStack(alignment: .leading, spacing: Spacing.md) {
            if let team = run?.team {
                rentalRow(team, selected: run?.beaten == nil ? [] : [give].compactMap { $0 }) { slot in
                    guard run?.beaten != nil else { return }
                    give = give == slot ? nil : slot
                }
                if let beaten = run?.beaten {
                    Text(l.towerSwapTheirs).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    rentalRow(beaten, selected: [take].compactMap { $0 }) { slot in take = take == slot ? nil : slot }
                }
                Text(run?.beaten == nil ? l.towerRentalNote : l.towerSwapNote).font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    if tower.record(.rental).streak > 0 {
                        Button(l.towerQuit) { Task { await service.quit(.rental) } }
                            .controlSize(.small).disabled(service.busy)
                    }
                    Spacer()
                    if run?.beaten != nil {
                        Button(l.towerSwap) {
                            guard let give, let take else { return }
                            Task {
                                await service.rental(.swap(give: give, take: take))
                                clearSwap()
                            }
                        }
                        .controlSize(.small).disabled(give == nil || take == nil || service.busy)
                    }
                    Button(service.busy ? l.gymFighting : l.towerChallenge(next)) {
                        clearSwap()
                        Task { await service.fight(.rental, team: nil) }
                    }
                    .controlSize(.small).buttonStyle(.borderedProminent).disabled(service.busy)
                }
            } else if let offer = run?.offer {
                rentalRow(offer, selected: picked) { index in
                    if let at = picked.firstIndex(of: index) {
                        picked.remove(at: at)
                    } else if picked.count < TowerProgress.teamSize {
                        picked.append(index)
                    }
                }
                Text(l.towerRentalNote).font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button(l.towerRentalStart(picked.count)) {
                        let choice = picked
                        Task {
                            await service.rental(.pick(choice))
                            picked = []
                        }
                    }
                    .controlSize(.small).buttonStyle(.borderedProminent)
                    .disabled(picked.count != TowerProgress.teamSize || service.busy)
                }
            } else {
                Text(l.towerRentalNote).font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button(l.towerRentalGet) { Task { await service.rental() } }
                        .controlSize(.small).buttonStyle(.borderedProminent).disabled(service.busy)
                }
            }
        }
    }

    private func clearSwap() {
        give = nil
        take = nil
    }

    private func rentalRow(_ members: [TowerRental], selected: [Int], onTap: @escaping (Int) -> Void) -> some View {
        rentalGrid(members, selected: selected, onTap: onTap)
            .task { await store.loadSpeciesIndexIfNeeded() }
    }

    private func rentalGrid(_ members: [TowerRental], selected: [Int], onTap: @escaping (Int) -> Void) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.sm), count: TowerProgress.teamSize),
                  spacing: Spacing.sm) {
            ForEach(Array(members.enumerated()), id: \.offset) { index, member in
                Button { onTap(index) } label: { rentalCard(member, selected: selected.contains(index)) }
                    .buttonStyle(.plain).disabled(service.busy)
            }
        }
    }

    private func rentalCard(_ member: TowerRental, selected: Bool) -> some View {
        VStack(spacing: Spacing.xxs) {
            ZStack(alignment: .bottomTrailing) {
                SpriteView(speciesID: member.pokemonId, size: 40, shiny: false).frame(width: 40, height: 40)
                if let item = member.item { HeldItemBadge(ref: item, size: 16) }
            }
            if let name = store.speciesIndex?.entry(member.pokemonId).flatMap({ language.resolveName($0.names) }) {
                Text(name).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            ForEach(member.moves.prefix(4), id: \.self) { move in
                MoveNameLabel(id: move, botName: "", language: language)
                    .font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, Spacing.sm).padding(.horizontal, Spacing.xs)
        .contentShape(Rectangle())
        .ptbPanel()
        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Color.accentColor, lineWidth: 2)
            .opacity(selected ? 1 : 0))
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
        if outcome.run.beaten != nil { notes.append(l.towerSwapNote) }
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
