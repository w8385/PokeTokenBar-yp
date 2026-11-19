import SwiftUI

/// Local editing state. Discarding Settings discards this value without touching the store.
struct GrowthModeDraft: Equatable {
    var mode: GrowthMode

    @MainActor init(companion: CompanionStore) {
        mode = companion.growthMode
    }

    @MainActor func differs(from companion: CompanionStore) -> Bool {
        mode != companion.growthMode
    }

    @MainActor mutating func save(to companion: CompanionStore) {
        companion.setGrowthMode(mode)
        self = GrowthModeDraft(companion: companion)
    }
}

@MainActor
struct GrowthModeSection: View {
    let companion: CompanionStore
    @State var draft: GrowthModeDraft
    private var l: L { companion.l }

    init(companion: CompanionStore, draft: GrowthModeDraft? = nil) {
        self.companion = companion
        _draft = State(initialValue: draft ?? GrowthModeDraft(companion: companion))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(l.growthModeLabel)
                .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                .textCase(.uppercase).padding(.leading, 4)
            VStack(alignment: .leading, spacing: 4) {
                Picker(l.growthModeLabel, selection: $draft.mode) {
                    Text(l.growthModeToken).tag(GrowthMode.token)
                    Text(l.growthModeTime).tag(GrowthMode.time)
                }
                .pickerStyle(.segmented).labelsHidden()
                .accessibilityIdentifier("growthModePicker")
                Text(draft.mode == .time ? l.growthModeTimeHint : l.growthModeTokenHint)
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .ptbCard()
            if draft.differs(from: companion) {
                HStack {
                    Spacer()
                    Button(l.save) { draft.save(to: companion) }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("saveGrowthMode")
                }
            }
        }
    }
}
