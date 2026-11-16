import SwiftUI

/// The Box page's battle slots, 1–3 for PvP and 4–6 for the gym: each shows who holds it, this Pokémon's own slot is highlighted.
@MainActor
struct BattleSlotControl: View {
    let store: CompanionStore
    let entry: DexEntry
    let battleEntry: BattleEntryStore
    /// Called once per change, so the bot's copy of the lineup follows.
    let onChange: () -> Void

    private var l: L { store.l }

    var body: some View {
        let lineup = BattleEntry.lineup(state: store.state, slots: battleEntry.slots)
        let mine = battleEntry.slotIndex(of: entry, in: store)
        let candidate = store.battleCandidate(for: entry)
        let locked = candidate.map { store.isTradeLocked($0.id) } ?? false
        VStack(alignment: .leading, spacing: 4) {
            slotRow(0..<BattleEntry.pvpSlots, caption: l.battleSlotPvP, symbol: "bolt.fill",
                    lineup: lineup, mine: mine, candidate: candidate, locked: locked)
            slotRow(BattleEntry.pvpSlots..<BattleEntry.maxSlots, caption: l.battleSlotGymOnly, symbol: "building.columns",
                    lineup: lineup, mine: mine, candidate: candidate, locked: locked)
        }
        .opacity(locked ? 0.5 : 1)
    }

    private func slotRow(_ range: Range<Int>, caption: String, symbol: String, lineup: [BattleCandidate], mine: Int?,
                         candidate: BattleCandidate?, locked: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.caption2).foregroundStyle(.secondary).frame(width: 14)
            ForEach(range, id: \.self) { index in
                let holder = index < lineup.count ? lineup[index] : nil
                let isMine = mine == index
                let last = isMine && lineup.count == 1
                let clash = !isMine && candidate.map {
                    BattleEntry.itemClash($0.id, replacing: holder?.id, among: lineup.map(\.id), state: store.state)
                } == true
                Button {
                    if battleEntry.place(entry, at: index, in: store) { onChange() }
                } label: {
                    slotLabel(index: index, holder: holder, isMine: isMine)
                }
                .buttonStyle(.plain)
                .disabled(locked || last || clash)
                .opacity(clash ? 0.4 : 1)
                .help(locked ? l.battleSlotLocked : clash ? l.battleItemClause : last ? l.battleSlotLast
                      : isMine ? l.battleSlotRemove(index + 1) : l.battleSlotPlace(index + 1))
                .accessibilityLabel(isMine ? l.battleSlotRemove(index + 1) : l.battleSlotPlace(index + 1))
            }
            Text(caption).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func slotLabel(index: Int, holder: BattleCandidate?, isMine: Bool) -> some View {
        let dex = holder.flatMap { store.dexEntry(for: $0) }
        return ZStack {
            if let holder, let dex {
                SpriteView(speciesID: dex.finalID, size: 26, shiny: holder.member.shiny, form: dex.form,
                           female: dex.profile?.gender == .female)
                    .frame(width: 26, height: 26)
            }
        }
        .frame(width: 34, height: 34)
        .background(RoundedRectangle(cornerRadius: Radius.chip).fill(isMine ? Color.accentColor.opacity(0.18) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: Radius.chip)
            .strokeBorder(isMine ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: isMine ? 1.5 : 1))
        .overlay(alignment: .topLeading) {
            Text("\(index + 1)").font(.ptb(.caption, weight: .bold)).monospacedDigit()
                .foregroundStyle(isMine ? Color.accentColor : Color.secondary)
                .padding(.leading, 3).padding(.top, 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: Radius.chip))
    }
}
