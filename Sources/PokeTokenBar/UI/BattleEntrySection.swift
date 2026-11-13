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
        let megaLead = lineup.firstIndex { companion.megaStone(of: $0.id, speciesID: speciesID(of: $0)) != nil }
        if lineup.isEmpty {
            rentalRow
        } else {
            ForEach(Array(lineup.enumerated()), id: \.element.id) { index, fighter in
                entryRow(fighter: fighter, index: index, count: lineup.count, megaLead: megaLead)
                if lineup.count == 1 || expanded == fighter.id {
                    heldItemRow(fighter)
                    moveList(fighter)
                }
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

    private func speciesID(of fighter: BattleCandidate) -> Int {
        companion.dexEntry(for: fighter)?.finalID ?? fighter.member.pokemonID
    }

    private func entryRow(fighter: BattleCandidate, index: Int, count: Int, megaLead: Int?) -> some View {
        let dexEntry = companion.dexEntry(for: fighter)
        let speciesID = speciesID(of: fighter)
        let level = fighter.member.level
        let mega = companion.megaStone(of: fighter.id, speciesID: speciesID)
        let megaSprite = mega?.spriteID
        let name = fighterName(fighter)
        return VStack(alignment: .leading, spacing: 4) {
            row {
                SpriteView(speciesID: megaSprite ?? speciesID, size: 56, animated: true, shiny: fighter.member.shiny,
                           form: megaSprite == nil ? dexEntry?.form : nil,
                           female: megaSprite == nil && dexEntry?.profile?.gender == .female)
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(count > 1 ? "\(index + 1) · \(l.battleEntryLabel)" : l.battleEntryLabel)
                        .font(.caption2).foregroundStyle(.secondary)
                    Text("\(mega.map { l.megaFormName(name, variant: $0.variantSuffix) } ?? name)\(fighter.member.shiny ? " ✨" : "")")
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
                    if let mega {
                        TypeBadges(types: mega.types, language: companion.language)
                    } else if let details = companion.pokemonDetailsByID[speciesID] {
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
            if let mega {
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.megaStatLine(mega.stats)).monospacedDigit()
                    if let ability = mega.abilityName(in: companion.language) {
                        Text("\(l.megaAbilityLabel): \(ability)")
                    }
                    if let megaLead, megaLead != index {
                        Text(l.megaOncePerBattle).foregroundStyle(.orange)
                    }
                }
                .font(.caption2).foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
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

    private func fighterName(_ fighter: BattleCandidate) -> String {
        companion.dexEntry(for: fighter).map(companion.dexEntryName) ?? companion.displayName
    }

    private func heldItemRow(_ fighter: BattleCandidate) -> some View {
        let held = companion.heldItem(of: fighter.id)
        let heldStone = companion.heldMegaStone(of: fighter.id)
        let spare = companion.ownedItems(in: .heldItem)
        let spareStones = companion.ownedMegaStones()
        let speciesID = companion.dexEntry(for: fighter)?.finalID ?? fighter.member.pokemonID
        return VStack(alignment: .leading, spacing: 4) {
            row {
                if let held {
                    ItemIconView(kind: held, size: 28)
                } else if let heldStone {
                    ItemIconView(stone: heldStone, size: 28)
                } else {
                    Image(systemName: "bag").frame(width: 28, height: 28).foregroundStyle(.tertiary)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.heldItemLabel).font(.caption2).foregroundStyle(.secondary)
                    Text(held.map(l.itemName) ?? heldStone.map(l.megaStoneName) ?? l.heldItemNone)
                        .font(.callout.weight(.semibold))
                }
                Spacer(minLength: 4)
                if held != nil || heldStone != nil {
                    Button(l.heldItemRemove) { change { companion.unequip(from: fighter.id) } }
                        .controlSize(.small)
                }
                if !spare.isEmpty || !spareStones.isEmpty {
                    Menu(l.heldItemEquip) {
                        ForEach(spare, id: \.kind) { item in
                            Button("\(l.itemName(item.kind)) ×\(item.count)") {
                                change { companion.equip(item.kind, to: fighter.id) }
                            }
                        }
                        ForEach(spareStones, id: \.stone) { item in
                            Button("\(l.megaStoneName(item.stone)) ×\(item.count)") {
                                change { companion.equip(item.stone, to: fighter.id) }
                            }
                        }
                    }
                    .controlSize(.small).fixedSize()
                }
            }
            if let held {
                Text(l.heldItemEffect(held)).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12).padding(.bottom, 6)
            } else if let heldStone {
                let matches = heldStone.speciesID == speciesID
                Text(matches ? l.megaStoneEffect
                             : l.megaStoneWrongHolder(l.megaStoneName(heldStone), fighterName(fighter)))
                    .font(.caption2).foregroundStyle(matches ? Color.secondary : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12).padding(.bottom, 6)
            } else if spare.isEmpty && spareStones.isEmpty {
                Text(l.heldItemNoneOwned).font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12).padding(.bottom, 6)
            }
        }
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
