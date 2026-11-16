import SwiftUI

/// The Box page's move training: the four moves a Pokémon takes into battle, each swapped from the list
/// the bot says it can use now: level-up moves up to its level, and TM moves at any level once the TM is owned.
/// An unowned TM is listed locked with its price and an inline buy button.
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
    @State private var buying: Int?

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
    private var fetchKey: String { "\(member.pokemonID)-\(member.level)" }

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
            buying = nil
            unavailable = false
            if loadedSpecies != member.pokemonID { learnable = nil }
            if let moves = await uploader.learnableMoves(pokemonID: member.pokemonID, level: member.level) {
                learnable = moves
                loadedSpecies = member.pokemonID
            } else {
                learnable = nil
                unavailable = true
            }
        }
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
            ForEach(0..<BattleEntry.maxMoves, id: \.self) { index in
                slotRow(index: index, move: index < selected.count ? moves.moves.first { $0.id == selected[index] } : nil)
            }
            if let editing {
                picker(moves, editing: editing, selected: selected)
            } else {
                Text(l.moveTrainingHint).font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func slotRow(index: Int, move: LearnableMove?) -> some View {
        let isEditing = editing == index
        return Button {
            editing = isEditing ? nil : index
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(index + 1)").font(.caption2.weight(.bold)).foregroundStyle(.secondary).frame(width: 12)
                if let move {
                    moveLabel(move)
                } else {
                    Text(l.moveSlotEmpty).font(.callout).foregroundStyle(Color.accentColor)
                    Spacer()
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: Radius.chip).fill(isEditing ? Color.accentColor.opacity(0.15) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: Radius.chip)
                .strokeBorder(isEditing ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func picker(_ moves: LearnableMoves, editing index: Int, selected: [Int]) -> some View {
        group(l.moveGroupLevelUp, moves.levelUpMoves.reversed(), index: index, selected: selected, moves: moves)
        group(l.moveGroupMachine, moves.machineMoves, index: index, selected: selected, moves: moves)
    }

    @ViewBuilder
    private func group(_ title: String, _ list: [LearnableMove], index: Int, selected: [Int],
                       moves: LearnableMoves) -> some View {
        if !list.isEmpty {
            Text(title).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary).padding(.top, 2)
            ForEach(list) { move in
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
                    .help(move.name)
                    .accessibilityLabel(move.name)                }
            }
        }
    }

    private func lockedRow(_ move: LearnableMove) -> some View {
        let price = store.tmPrice(power: move.power, isWeather: move.isWeather)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "lock.fill").foregroundStyle(.secondary)
                moveLabel(move)
            }
            if buying == move.id {
                HStack(spacing: 8) {
                    Text(l.buyConfirm("\(l.moveGroupMachine) \(move.name)"))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button(l.buy) {
                        buying = nil
                        store.buyTM(moveID: move.id, power: move.power, isWeather: move.isWeather)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .help(buyHelp(move))
                    Button(l.cancel) { buying = nil }
                        .buttonStyle(.borderless).controlSize(.small)
                        .help(l.cancel)
                }
            } else {
                HStack {
                    Text("\(l.shopPriceLabel) \(TokenFormatter.compact(price))")
                        .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                    Spacer()
                    if store.canBuyTM(power: move.power, isWeather: move.isWeather) {
                        Button(l.buy) { buying = move.id }
                            .buttonStyle(.bordered).controlSize(.small)
                            .help(buyHelp(move))                    } else {
                        Text(l.notEnoughTokens).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private func buyHelp(_ move: LearnableMove) -> String { "\(l.buy) \(move.name)" }

    private func moveLabel(_ move: LearnableMove) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(move.name).font(.callout)
                TypeBadges(types: [move.type], language: store.language)
                Spacer()
                if !move.isMachine { Text("Lv\(move.level)").font(.caption2).foregroundStyle(.tertiary) }
            }
            Text(stats(move)).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            if let effects = effects(move) {
                Text(effects).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func stats(_ move: LearnableMove) -> String {
        var parts = [move.damageClass == "physical" ? l.movePhysical : l.moveSpecial,
                     "\(l.movePower) \(move.power)",
                     "\(l.moveAccuracy) \(move.accuracy.map(String.init) ?? "—")"]
        if let pp = move.pp { parts.append("PP \(pp)") }
        return parts.joined(separator: " · ")
    }

    private func effects(_ move: LearnableMove) -> String? {
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
