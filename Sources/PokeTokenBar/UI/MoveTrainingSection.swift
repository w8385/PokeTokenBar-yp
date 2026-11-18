import SwiftUI

/// The Box page's move training: the four moves a Pokémon takes into battle, each swapped from the list
/// the bot says it can use now: level-up moves up to its level, TM moves at any level once the TM is owned, attacking
/// egg moves once a Mirror Herb is used, and the battle's status moves in their own group. An unowned TM is listed
/// locked with its price and an inline buy button; egg moves are listed locked under one Mirror Herb button.
@MainActor
struct MoveTrainingSection: View {
    let store: CompanionStore
    let battleEntry: BattleEntryStore
    let uploader: PartyUploader
    let candidate: BattleCandidate
    /// Called once per change, so the bot's copy of the lineup follows.
    let onChange: () -> Void

    @State private var learnable: LearnableMoves?
    @State private var loadedSpecies: Int?
    @State private var unavailable = false
    @State private var editing: Int?
    /// Attacking egg moves shown locked until a Mirror Herb is used; empty with the herb, where `learnable` has them.
    @State private var lockedEggMoves: [LearnableMove] = []
    @State private var confirmingHerb = false
    @Environment(\.pokemonNameStore) private var injectedNames

    init(store: CompanionStore, battleEntry: BattleEntryStore, uploader: PartyUploader,
         candidate: BattleCandidate, initialEditing: Int? = nil, onChange: @escaping () -> Void) {
        self.store = store
        self.battleEntry = battleEntry
        self.uploader = uploader
        self.candidate = candidate
        self.onChange = onChange
        _editing = State(initialValue: initialEditing)
    }

    private var l: L { store.l }
    private var member: PartyMember { candidate.member }
    private var hasHerb: Bool { member.mirrorHerb == true }
    private var fetchKey: String { "\(member.pokemonID)-\(member.level)-\(hasHerb)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let learnable {
                content(learnable)
            } else if unavailable {
                Text(l.battleEntryMovesUnavailable).font(.caption2).foregroundStyle(.orange)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: Radius.panel))
        .task(id: fetchKey) {
            if learnable != nil { editing = nil }
            unavailable = false
            confirmingHerb = false
            if loadedSpecies != member.pokemonID { learnable = nil }
            if let moves = await uploader.learnableMoves(pokemonID: member.pokemonID, level: member.level, egg: hasHerb) {
                lockedEggMoves = await herbLessEggMoves(besides: moves)
                learnable = moves
                loadedSpecies = member.pokemonID
            } else {
                learnable = nil
                unavailable = true
            }
        }
    }

    /// The egg moves a Mirror Herb would add, from a display-only `egg=1` reply; the herb-less list stays today's.
    private func herbLessEggMoves(besides moves: LearnableMoves) async -> [LearnableMove] {
        guard !hasHerb, !store.isTradeLocked(candidate.id), let individual = store.trainable(id: candidate.id),
              store.canUseMirrorHerb(on: individual),
              let withEggs = await uploader.learnableMoves(pokemonID: member.pokemonID, level: member.level, egg: true)
        else { return [] }
        let listed = Set(moves.moves.map(\.id))
        return withEggs.eggMoves.filter { !listed.contains($0.id) }
    }

    private func content(_ moves: LearnableMoves) -> some View {
        let custom = battleEntry.chosenMoves(for: candidate.id, pokemonID: member.pokemonID)
        let usable = Set(moves.moves.map(\.id))
        let selected = (custom.isEmpty ? moves.default : custom).filter(usable.contains)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(l.battleEntryMoves).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                Spacer()
                Button(l.battleEntryAutoMoves) {
                    change { battleEntry.resetMoves(for: candidate.id) }
                    editing = nil
                }
                .buttonStyle(.borderless).font(.caption)
                .help(l.battleEntryAutoMoves)                .disabled(custom.isEmpty)
            }
            MoveSlotStack(count: BattleEntry.maxMoves) { index in
                slotRow(index: index, move: index < selected.count ? moves.moves.first { $0.id == selected[index] } : nil,
                        selected: selected)
            }
            if let editing {
                picker(moves, editing: editing, selected: selected)
            } else {
                Text(l.moveTrainingHint).font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func slotRow(index: Int, move: LearnableMove?, selected: [Int]) -> some View {
        let isEditing = editing == index
        return HStack(spacing: Spacing.xs) {
            Button {
                editing = isEditing ? nil : index
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Text("\(index + 1)").font(.ptb(.small, weight: .bold))
                        .foregroundStyle(isEditing ? Color.white : Color.primary)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(isEditing ? Color.accentColor : Color.secondary.opacity(0.2)))
                    if let move {
                        moveLabel(move)
                    } else {
                        Text(l.moveSlotEmpty).font(.callout).foregroundStyle(Color.accentColor)
                        Spacer()
                    }
                }
                .padding(.leading, Spacing.md).padding(.vertical, Spacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if move != nil {
                VStack(spacing: 0) {
                    orderButton("chevron.up", l.moveSlotUp, disabled: index == 0) {
                        swap(index, index - 1, selected: selected)
                    }
                    orderButton("chevron.down", l.moveSlotDown, disabled: index >= selected.count - 1) {
                        swap(index, index + 1, selected: selected)
                    }
                }
            }
        }
        .padding(.trailing, Spacing.md)
        .moveSlotCard(editing: isEditing)
    }

    private func orderButton(_ symbol: String, _ label: String, disabled: Bool,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 18, height: 16) }
            .buttonStyle(.borderless)
            .help(label)
            .accessibilityLabel(label)
            .disabled(disabled)
    }

    private func swap(_ a: Int, _ b: Int, selected: [Int]) {
        change { battleEntry.swapMoves(a, b, for: candidate.id, pokemonID: member.pokemonID, current: selected) }
        editing = nil
    }

    @ViewBuilder
    private func picker(_ moves: LearnableMoves, editing index: Int, selected: [Int]) -> some View {
        group(l.moveGroupLevelUp, moves.levelUpMoves.reversed(), index: index, selected: selected, moves: moves)
        group(l.moveGroupMachine, moves.machineMoves, index: index, selected: selected, moves: moves)
        if hasHerb {
            group(l.moveGroupEgg, moves.eggMoves, index: index, selected: selected, moves: moves)
        } else if !lockedEggMoves.isEmpty {
            lockedEggGroup
        }
        group(l.moveGroupStatus, moves.statusMoves, index: index, selected: selected, moves: moves)
    }

    @ViewBuilder
    private var lockedEggGroup: some View {
        Text(l.moveGroupEgg).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary).padding(.top, Spacing.sm)
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(Array(lockedEggMoves.enumerated()), id: \.element.id) { offset, move in
                if offset > 0 { Divider() }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary)
                    moveLabel(move)
                }
            }
            Divider()
            herbUnlock
        }
    }

    @ViewBuilder
    private var herbUnlock: some View {
        let payment = store.mirrorHerbPayment
        if confirmingHerb {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(l.mirrorHerbPaymentLine(payment)).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button(l.cancel) { confirmingHerb = false }.buttonStyle(.borderless).controlSize(.small)
                    if case .short = payment {} else {
                        Button(l.mintConfirmButton(payment)) {
                            confirmingHerb = false
                            if store.useMirrorHerb(on: candidate.id) == .changed { onChange() }
                        }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                    }
                }
            }
        } else {
            HStack(spacing: 6) {
                ItemIconView(kind: .mirrorHerb, size: 14)
                Text(l.mirrorHerbNeeded).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if case .short = payment {
                    Text(l.notEnoughTokens).font(.caption2).foregroundStyle(.tertiary)
                } else {
                    Button(l.mirrorHerbUse) { confirmingHerb = true }
                        .buttonStyle(.bordered).controlSize(.small)
                        .help(l.mirrorHerbEffect)
                }
            }
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ list: [LearnableMove], index: Int, selected: [Int],
                       moves: LearnableMoves) -> some View {
        if !list.isEmpty {
            Text(title).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary).padding(.top, Spacing.sm)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(Array(list.enumerated()), id: \.element.id) { offset, move in
                    if offset > 0 { Divider() }
                    candidateRow(move, index: index, selected: selected)
                }
            }
        }
    }

    @ViewBuilder
    private func candidateRow(_ move: LearnableMove, index: Int, selected: [Int]) -> some View {
        if move.isMachine && !store.ownsTM(move.id) {
            lockedRow(move)
        } else {
            Button {
                change {
                    battleEntry.chooseMove(move.id, at: index, for: candidate.id, pokemonID: member.pokemonID,
                                           current: selected, isMachine: move.isMachine)
                }
                editing = nil
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: selected.contains(move.id) ? "checkmark.square.fill" : "square")
                    moveLabel(move)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(name(move))
            .accessibilityLabel(name(move))
        }
    }

    private func lockedRow(_ move: LearnableMove) -> some View {
        let price = store.tmPrice(power: move.power, isWeather: move.isWeather)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "lock.fill").foregroundStyle(.secondary)
                moveLabel(move)
            }
            HStack {
                Text("\(l.shopPriceLabel) \(TokenFormatter.compact(price))")
                    .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                Spacer()
                if store.canBuyTM(power: move.power, isWeather: move.isWeather) {
                    Button(l.buy) { store.buyTM(moveID: move.id, power: move.power, isWeather: move.isWeather) }
                        .buttonStyle(.bordered).controlSize(.small)
                        .help(buyHelp(move))
                } else {
                    Text(l.notEnoughTokens).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func buyHelp(_ move: LearnableMove) -> String { "\(l.buy) \(name(move))" }

    private func name(_ move: LearnableMove) -> String {
        MoveName.text(id: move.id, botName: move.name, language: store.language,
                      names: (injectedNames ?? .shared).names)
    }

    private func moveLabel(_ move: LearnableMove) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                MoveNameLabel(id: move.id, botName: move.name, language: store.language).font(.callout)
                TypeBadges(types: [move.type], language: store.language)
                Spacer()
                if let source = source(move) { Text(source).font(.caption2).foregroundStyle(.tertiary) }
            }
            Text(stats(move)).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            if let effects = effects(move) {
                Text(effects).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func source(_ move: LearnableMove) -> String? {
        if move.isEgg { return l.moveEggSource }
        if !move.isMachine { return "Lv\(move.level)" }
        return move.isStatus ? l.moveGroupMachine : nil
    }

    private func stats(_ move: LearnableMove) -> String {
        var parts = move.isStatus
            ? [l.moveStatusClass]
            : [move.damageClass == "physical" ? l.movePhysical : l.moveSpecial, l.movePowerLine(move.power)]
        parts.append("\(l.moveAccuracy) \(move.accuracy.map(String.init) ?? "—")")
        if let pp = move.pp { parts.append("PP \(pp)") }
        return parts.joined(separator: " · ")
    }

    private func effects(_ move: LearnableMove) -> String? {
        if move.isStatus { return l.statusMoveEffect(move.id) }
        var parts: [String] = []
        if let ailment = move.ailment, let chance = move.ailmentChance {
            parts.append("\(l.moveAilment(ailment)) \(chance)%")
        }
        if let drain = move.drain, drain != 0 { parts.append(drain > 0 ? l.moveDrain : l.moveRecoil) }
        if let low = move.minHits, let high = move.maxHits, high > 1 {
            parts.append(l.moveHits(low == high ? "\(low)" : "\(low)-\(high)"))
        }
        if let changes = move.statChanges, !changes.isEmpty, let chance = move.statChance {
            let arrows = changes.map { change in
                l.statName(change.stat) + String(repeating: change.change > 0 ? "↑" : "↓", count: abs(change.change))
            }.joined(separator: " ")
            let target = move.statTarget == "user" ? " (\(l.moveSelf))" : ""
            parts.append("\(arrows)\(target) \(chance)%")
        }
        if (move.critRate ?? 0) > 0 { parts.append(l.moveHighCrit) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func change(_ edit: () -> Void) {
        battleEntry.prune(owned: Set(BattleEntry.candidates(in: store.state).map(\.id)))
        edit()
        onChange()
    }
}

/// The move slots as separate cards, one under another.
@MainActor
struct MoveSlotStack<Card: View>: View {
    let count: Int
    @ViewBuilder let card: (Int) -> Card

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            ForEach(0..<count, id: \.self) { card($0) }
        }
    }
}

extension View {
    /// One move slot: a filled card, or the accent fill and a heavier accent border while its picker is open.
    func moveSlotCard(editing: Bool) -> some View {
        background(editing ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor),
                   in: RoundedRectangle(cornerRadius: Radius.chip))
            .overlay(RoundedRectangle(cornerRadius: Radius.chip)
                .strokeBorder(editing ? Color.accentColor : Color.secondary.opacity(0.5), lineWidth: editing ? 2 : 1))
    }
}
