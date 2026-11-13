import SwiftUI

/// Battle tab rows for picking up to three battle Pokémon, their order and their moves.
@MainActor
struct BattleEntrySection: View {
    @Environment(CompanionStore.self) private var companion
    let entry: BattleEntryStore
    let uploader: PartyUploader
    let openPicker: (BattlePickerTarget) -> Void

    @State private var learnable: [String: LearnableMoves] = [:]
    @State private var unavailable: Set<String> = []
    @State private var expanded: String?

    private var l: L { companion.l }

    var body: some View {
        let lineup = BattleEntry.lineup(state: companion.state, slots: entry.slots)
        if lineup.isEmpty {
            rentalRow
        } else {
            ForEach(Array(lineup.enumerated()), id: \.element.id) { index, fighter in
                entryRow(fighter: fighter, index: index, count: lineup.count)
                if lineup.count == 1 || expanded == fighter.id { moveList(fighter) }
            }
            if lineup.count < BattleEntry.maxSlots {
                Button { openPicker(.add) } label: {
                    Label(l.battleAddMember, systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 12).padding(.vertical, 4)
            }
            VStack(alignment: .leading, spacing: 2) {
                if entry.slots.isEmpty {
                    Text(l.battleEntryAutoPick).foregroundStyle(Color.accentColor)
                }
                Text(l.battleEntryHint).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption2)
            .padding(.horizontal, 12).padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var rentalRow: some View {
        row {
            VStack(alignment: .leading, spacing: 1) {
                Text(l.battleRentalLabel)
                Text(l.battleRentalHint).font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Picker(l.battleRentalLabel, selection: Binding(
                get: { entry.rentalSpeciesID },
                set: { id in change { entry.chooseRental(id) } })) {
                ForEach(BattleEntry.rentalSpeciesIDs, id: \.self) { id in
                    Text(l.rentalStarterName(id)).tag(id)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    private func entryRow(fighter: BattleCandidate, index: Int, count: Int) -> some View {
        let dexEntry = companion.dexEntry(for: fighter)
        let speciesID = dexEntry?.finalID ?? fighter.member.pokemonID
        let level = fighter.member.level
        return VStack(alignment: .leading, spacing: 4) {
            row {
                SpriteView(speciesID: speciesID, size: 56, animated: true, shiny: fighter.member.shiny,
                           form: dexEntry?.form, female: dexEntry?.profile?.gender == .female)
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(count > 1 ? "\(index + 1) · \(l.battleEntryLabel)" : l.battleEntryLabel)
                        .font(.caption2).foregroundStyle(.secondary)
                    Text("\(dexEntry.map(companion.dexEntryName) ?? companion.displayName)\(fighter.member.shiny ? " ✨" : "")")
                        .font(.headline).lineLimit(1)
                    HStack(spacing: 6) {
                        Text("Lv\(level)").font(.callout).monospacedDigit()
                        if BattleEntry.isLevelCapped(level) {
                            Text(l.battleLevelCap(BattleEntry.battleLevel))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if fighter.dexEntry == nil {
                            Text(l.battleEntryRaising).font(.caption2).foregroundStyle(Color.accentColor)
                        }
                    }
                    if let details = companion.pokemonDetailsByID[speciesID] {
                        TypeBadges(types: details.types, language: companion.language)
                    }
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 4) {
                    Button(l.battleChange) { openPicker(.slot(fighter.id)) }
                        .controlSize(.small)
                    if count > 1 {
                        HStack(spacing: 2) {
                            iconButton("chevron.up", l.battleMoveEarlier, disabled: index == 0) {
                                change { entry.move(fighter.id, by: -1) }
                            }
                            iconButton("chevron.down", l.battleMoveLater, disabled: index == count - 1) {
                                change { entry.move(fighter.id, by: 1) }
                            }
                            iconButton("xmark", l.battleRemoveMember, disabled: false) {
                                change { entry.remove(fighter.id) }
                            }
                        }
                        Button(l.battleEntryMoves) {
                            expanded = expanded == fighter.id ? nil : fighter.id
                        }
                        .buttonStyle(.borderless).font(.caption)
                    }
                }
            }
        }
        .task(id: speciesID) { await companion.loadPokemonDetails(speciesID: speciesID) }
    }

    private func iconButton(_ symbol: String, _ label: String, disabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 18, height: 18) }
            .buttonStyle(.borderless)
            .help(label)
            .accessibilityLabel(label)
            .disabled(disabled)
    }

    @ViewBuilder
    private func moveList(_ fighter: BattleCandidate) -> some View {
        let member = fighter.member
        let key = "\(member.pokemonID)-\(member.level)"
        VStack(alignment: .leading, spacing: 6) {
            if let moves = learnable[key] {
                let slot = entry.slot(for: fighter.id)
                let custom = slot?.pokemonID == member.pokemonID && slot?.moves.isEmpty == false
                let selected = custom ? slot?.moves ?? [] : moves.default
                HStack {
                    Text(l.battleEntryMoves).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                    Spacer()
                    Button(l.battleEntryAutoMoves) { change { entry.resetMoves(for: fighter.id) } }
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
        entry.prune(owned: Set(BattleEntry.candidates(in: companion.state).map(\.id)))
        edit()
        Task { await uploader.tick() }
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10) { content() }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(minHeight: 38)
    }
}
