import SwiftUI

@MainActor
struct BattleGroupChips: View {
    let groups: [BattleItemGroup]
    @Binding var selection: BattleItemGroup?
    let l: L

    var body: some View {
        if groups.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(l.categoryAll, isSelected: selection == nil) { selection = nil }
                    ForEach(groups, id: \.self) { group in
                        chip(l.battleItemGroupName(group), isSelected: selection == group) { selection = group }
                    }
                }
            }
            .onChange(of: groups) { _, now in
                if let selection, !now.contains(selection) { self.selection = nil }
            }
        }
    }

    private func chip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
