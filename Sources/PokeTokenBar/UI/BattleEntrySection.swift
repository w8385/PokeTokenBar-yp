import SwiftUI

/// Battle tab rows for picking up to six battle Pokémon (the first three fight in PvP) and their order; moves and item are set in the Box.
@MainActor
struct BattleEntrySection: View {
    @Environment(CompanionStore.self) private var companion
    @Environment(PopoverNavigation.self) private var navigation: PopoverNavigation?
    let entry: BattleEntryStore
    let uploader: PartyUploader
    let openPicker: (BattlePickerTarget) -> Void

    private var l: L { companion.l }

    var body: some View {
        let lineup = BattleEntry.lineup(state: companion.state, slots: entry.slots)
        let megaLead = lineup.firstIndex { companion.megaStone(of: $0.id, speciesID: speciesID(of: $0)) != nil }
        let duplicates = BattleEntry.duplicateItemHolders(state: companion.state, slots: entry.slots)
        if lineup.isEmpty {
            rentalRow
        } else {
            ForEach(Array(lineup.enumerated()), id: \.element.id) { index, fighter in
                entryRow(fighter: fighter, index: index, count: lineup.count, megaLead: megaLead)
                if duplicates.contains(fighter.id) {
                    Text(l.battleItemDuplicateWarning).font(.caption2).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12).padding(.bottom, 4)
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
                    .overlay(alignment: .bottomTrailing) {
                        if let held = companion.heldItemRef(of: fighter.id) { HeldItemBadge(ref: held, size: 22) }
                    }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(count > 1 ? "\(index + 1) · \(l.battleEntryLabel)" : l.battleEntryLabel)
                        Text(index < BattleEntry.pvpSlots ? l.battleSlotPvP : l.battleSlotGymOnly)
                            .foregroundStyle(index < BattleEntry.pvpSlots ? Color.accentColor : .orange)
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                    Text("\(mega.map { l.megaFormName(name, variant: $0.variantSuffix) } ?? name)\(fighter.member.shiny ? " ✨" : "")")
                        .font(.headline).lineLimit(1)
                    HStack(spacing: 6) {
                        Text("Lv\(level)").font(.callout).monospacedDigit()
                        if BattleEntry.isLevelCapped(level) {
                            Text(l.battleLevelCap(BattleEntry.battleLevel))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if fighter.isRaised {
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
                    }
                    Button { navigation?.openBoxDetail(id: fighter.id) } label: {
                        Label(l.battleTraining, systemImage: "figure.strengthtraining.traditional")
                    }
                    .buttonStyle(.borderless).font(.caption)
                    .help(l.battleTraining)                }
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
