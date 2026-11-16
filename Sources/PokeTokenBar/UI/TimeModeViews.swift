import SwiftUI

/// Small tag next to the wallet and today's total: income comes from active time, not from tokens.
@MainActor
struct TimeModeBadge: View {
    let store: CompanionStore

    var body: some View {
        if store.growthMode == .time {
            Label(store.l.timeModeBadge, systemImage: "clock")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12), in: Capsule())
                .accessibilityIdentifier("timeModeBadge")
        }
    }
}

/// One dismissible line on Home for a token-mode player with no usage for days.
@MainActor
struct IdleTokenHintBanner: View {
    let store: CompanionStore

    var body: some View {
        if store.showsIdleTokenHint {
            HStack(spacing: 8) {
                Image(systemName: "clock").foregroundStyle(.secondary)
                Text(store.l.idleTokenHint)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button { store.dismissIdleTokenHint() } label: {
                    Image(systemName: "xmark").font(.caption2.weight(.bold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(store.l.close)
            }
            .padding(8)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier("idleTokenHint")
        }
    }
}
