import SwiftUI

/// "전체" + 항목이 있는 분류 칩 줄. 선택한 분류가 사라지면(예: 마지막 아이템을 씀) 전체로 돌아간다.
@MainActor
struct ItemCategoryChips: View {
    let categories: [ItemCategory]
    @Binding var selection: ItemCategory?
    let l: L

    var body: some View {
        if categories.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(l.categoryAll, isSelected: selection == nil) { selection = nil }
                    ForEach(categories, id: \.self) { category in
                        chip(l.categoryName(category), isSelected: selection == category) { selection = category }
                    }
                }
            }
            .onChange(of: categories) { _, now in
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
