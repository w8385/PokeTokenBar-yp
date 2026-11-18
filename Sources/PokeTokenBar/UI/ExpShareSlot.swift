import SwiftUI

/// The Exp. Share row on a Box page, separate from the battle held-item slot.
@MainActor
struct ExpShareSlot: View {
    let store: CompanionStore
    let individual: BoxIndividual
    @State private var picking = false

    private var l: L { store.l }

    var body: some View {
        let holds = store.holdsExpShare(individual.id)
        let canAttach = store.canAttachExpShare(to: individual.id)
        let sources = store.expShareMoveSources(to: individual.id)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                ItemIconView(kind: .expShare, size: 24)
                Text(l.itemName(.expShare)).font(.callout.weight(.semibold))
                Spacer(minLength: 4)
                if holds {
                    Button(l.expShareDetach) { store.detachExpShare(from: individual.id) }
                        .controlSize(.small)
                } else {
                    if !sources.isEmpty {
                        Button(l.expShareMoveHere) { picking = true }
                            .controlSize(.small)
                            .popover(isPresented: $picking, arrowEdge: .bottom) {
                                ExpShareMovePicker(store: store, targetID: individual.id) { picking = false }
                            }
                    }
                    if canAttach || sources.isEmpty {
                        Button(l.expShareAttach) { store.attachExpShare(to: individual.id) }
                            .controlSize(.small)
                            .disabled(!canAttach)
                            .help(canAttach ? "" : l.expShareNoneInBag)
                    }
                }
            }
            if let note = note(holds: holds, canAttach: canAttach) {
                Text(note.text).font(.caption2).foregroundStyle(note.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: Radius.panel))
        .accessibilityElement(children: .contain)
    }

    private func note(holds: Bool, canAttach: Bool) -> (text: String, color: Color)? {
        switch individual.role {
        case .raising, .parked: return holds ? (l.expShareIdleWhileRaised, .secondary) : nil
        case .stored: return holds ? (l.expShareStoredNote, .secondary) : canAttach ? nil : (l.expShareNoneInBag, .secondary)
        case .graduated, .friend: return holds ? (l.expShareHolding, .secondary) : canAttach ? nil : (l.expShareNoneInBag, .secondary)
        }
    }
}

/// The Pokémon holding an Exp. Share; tapping one moves its copy onto `targetID`.
@MainActor
struct ExpShareMovePicker: View {
    let store: CompanionStore
    let targetID: String
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(store.l.expShareMoveTitle).font(.caption.weight(.semibold))
            ForEach(store.expShareMoveSources(to: targetID)) { holder in
                Button {
                    store.moveExpShare(from: holder.id, to: targetID)
                    onDone()
                } label: {
                    HStack(spacing: 8) {
                        SpriteView(speciesID: holder.speciesID, size: 32, shiny: holder.entry.isShiny,
                                   form: holder.entry.form, female: holder.entry.profile?.gender == .female)
                            .frame(width: 32, height: 32)
                        Text(store.dexEntryName(holder.entry)).font(.callout).lineLimit(1)
                        Spacer(minLength: 8)
                        Text("Lv\(holder.level)").font(.caption.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(width: 240, alignment: .leading)
    }
}
