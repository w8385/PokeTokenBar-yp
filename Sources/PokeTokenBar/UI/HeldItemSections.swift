import SwiftUI

/// Battle items under their effect-group headers. The shop and the bag supply the card.
@MainActor
struct HeldItemSections<Card: View>: View {
    let sections: [BattleItemSection]
    let l: L
    @ViewBuilder let card: (ItemKind) -> Card

    var body: some View {
        ForEach(sections, id: \.group) { section in
            ItemSectionHeader(title: l.battleItemGroupName(section.group))
            ForEach(section.kinds, id: \.self) { kind in
                card(kind)
            }
        }
    }
}

@MainActor
struct ItemSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            .padding(.top, 4)
    }
}
