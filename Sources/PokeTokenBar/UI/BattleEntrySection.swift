import SwiftUI

/// Battle tab rows for picking the one battle Pokémon and its moves.
@MainActor
struct BattleEntrySection: View {
    @Environment(CompanionStore.self) private var companion
    let entry: BattleEntryStore
    let uploader: PartyUploader

    @State private var learnable: [String: LearnableMoves] = [:]
    @State private var unavailable: Set<String> = []

    private var l: L { companion.l }

    var body: some View {
        let candidates = BattleEntry.candidates(in: companion.state)
        let fighter = BattleEntry.fighter(state: companion.state, slot: entry.slot)
        row {
            VStack(alignment: .leading, spacing: 1) {
                Text(l.battleEntryLabel)
                Text(l.battleEntryHint).font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Menu(entry.slot == nil ? l.battleEntryAutoPick : fighter.map(label) ?? l.battleEntryAutoPick) {
                Button(l.battleEntryAutoPick) { change { entry.choose(nil) } }
                Divider()
                ForEach(candidates) { candidate in
                    Button(label(candidate)) { change { entry.choose(candidate.id) } }
                }
            }
            .fixedSize()
            .disabled(candidates.isEmpty)
        }
        if let fighter {
            moveList(fighter)
        } else {
            Text(l.battleEntryEgg)
                .font(.caption2).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private func moveList(_ fighter: BattleCandidate) -> some View {
        let member = fighter.member
        let key = "\(member.pokemonID)-\(member.level)"
        VStack(alignment: .leading, spacing: 6) {
            if let moves = learnable[key] {
                let slot = entry.slot
                let custom = slot?.instanceID == fighter.id && slot?.pokemonID == member.pokemonID
                    && slot?.moves.isEmpty == false
                let selected = custom ? slot?.moves ?? [] : moves.default
                HStack {
                    Text(l.battleEntryMoves).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                    Spacer()
                    Button(l.battleEntryAutoMoves) { change { entry.resetMoves() } }
                        .buttonStyle(.borderless).font(.caption)
                        .disabled(!custom)
                }
                ForEach(moves.moves.reversed()) { move in
                    let isOn = selected.contains(move.id)
                    Button {
                        change {
                            entry.toggleMove(move.id, for: fighter.id, pokemonID: member.pokemonID, current: selected)
                        }
                    } label: {
                        moveRow(move, isOn: isOn)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!isOn && selected.count >= BattleEntry.maxMoves)
                }
            } else if unavailable.contains(key) {
                Text(l.battleEntryMovesUnavailable).font(.caption2).foregroundStyle(.orange)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 12).padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: key) {
            guard learnable[key] == nil else { return }
            unavailable.remove(key)
            if let moves = await uploader.learnableMoves(pokemonID: member.pokemonID, level: member.level) {
                learnable[key] = moves
            } else {
                unavailable.insert(key)
            }
        }
    }

    private func moveRow(_ move: LearnableMove, isOn: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: isOn ? "checkmark.square.fill" : "square")
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(move.name).font(.callout)
                    TypeBadges(types: [move.type], language: companion.language)
                    Spacer()
                    Text("Lv\(move.level)").font(.caption2).foregroundStyle(.tertiary)
                }
                Text(stats(move)).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                if let effects = effects(move) {
                    Text(effects).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
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
            parts.append("\(ailment == "burn" ? l.moveBurn : l.moveParalysis) \(chance)%")
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

    private func label(_ candidate: BattleCandidate) -> String {
        let name = candidate.dexEntry.map(companion.dexEntryName) ?? companion.displayName
        let raising = candidate.dexEntry == nil ? " · \(l.battleEntryRaising)" : ""
        return "\(name) Lv\(candidate.member.level)\(candidate.member.shiny ? " ✨" : "")\(raising)"
    }

    private func change(_ edit: () -> Void) {
        edit()
        Task { await uploader.tick() }
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10) { content() }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(minHeight: 38)
    }
}
