import SwiftUI

/// The Box page's 1 · 2 · 3 battle slots: each shows who holds it, this Pokémon's own slot is highlighted.
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
        let locked = store.battleCandidate(for: entry).map { store.isTradeLocked($0.id) } ?? false
        HStack(spacing: 4) {
            Image(systemName: "bolt.fill").font(.caption2).foregroundStyle(.secondary)
            ForEach(0..<BattleEntry.maxSlots, id: \.self) { index in
                let holder = index < lineup.count ? lineup[index] : nil
                let isMine = mine == index
                let last = isMine && lineup.count == 1
                Button {
                    if battleEntry.place(entry, at: index, in: store) { onChange() }
                } label: {
                    slotLabel(index: index, holder: holder, isMine: isMine)
                }
                .buttonStyle(.plain)
                .disabled(locked || last)
                .help(locked ? l.battleSlotLocked : last ? l.battleSlotLast
                      : isMine ? l.battleSlotRemove(index + 1) : l.battleSlotPlace(index + 1))
                .accessibilityLabel(isMine ? l.battleSlotRemove(index + 1) : l.battleSlotPlace(index + 1))
            }
        }
        .opacity(locked ? 0.5 : 1)
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
        .background(RoundedRectangle(cornerRadius: 7).fill(isMine ? Color.accentColor.opacity(0.18) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 7)
            .strokeBorder(isMine ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: isMine ? 1.5 : 1))
        .overlay(alignment: .topLeading) {
            Text("\(index + 1)").font(.system(size: 9, weight: .bold)).monospacedDigit()
                .foregroundStyle(isMine ? Color.accentColor : Color.secondary)
                .padding(.leading, 3).padding(.top, 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 7))
    }
}
