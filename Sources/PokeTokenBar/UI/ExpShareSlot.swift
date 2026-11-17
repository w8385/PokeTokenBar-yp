import SwiftUI

/// The Exp. Share row on a Box page, separate from the battle held-item slot.
@MainActor
struct ExpShareSlot: View {
    let store: CompanionStore
    let individual: BoxIndividual

    private var l: L { store.l }

    var body: some View {
        let holds = store.holdsExpShare(individual.id)
        let canAttach = store.canAttachExpShare(to: individual.id)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                ItemIconView(kind: .expShare, size: 24)
                Text(l.itemName(.expShare)).font(.callout.weight(.semibold))
                Spacer(minLength: 4)
                if holds {
                    Button(l.expShareDetach) { store.detachExpShare(from: individual.id) }
                        .controlSize(.small)
                } else {
                    Button(l.expShareAttach) { store.attachExpShare(to: individual.id) }
                        .controlSize(.small)
                        .disabled(!canAttach)
                        .help(canAttach ? "" : l.expShareNoneInBag)
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
