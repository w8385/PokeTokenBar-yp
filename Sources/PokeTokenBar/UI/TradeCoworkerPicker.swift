import SwiftUI

/// The linked coworkers as a pick list, with the loading and unreachable states. Shared by the Friends tab
/// offer screen and the Box detail panel.
@MainActor
struct TradeCoworkerPicker: View {
    let model: TradeOfferModel
    let l: L

    var body: some View {
        if let coworkers = model.coworkers {
            if coworkers.isEmpty {
                Text(l.tradeNoCoworkers).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(coworkers) { coworker in
                        row(coworker)
                        if coworker != coworkers.last { Divider() }
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1))
            }
        } else if model.loadFailed {
            Text(l.tradeCoworkersUnavailable).font(.caption).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(l.tradeLoadingCoworkers).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ coworker: TradeCoworker) -> some View {
        let selected = model.target == coworker.id
        return Button { model.pickTarget(coworker.id) } label: {
            HStack {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                Text(coworker.name).font(.callout)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The outcome line under a send button; nothing while idle or sending.
@MainActor
struct TradePhaseLine: View {
    let phase: TradeOfferModel.Phase
    let l: L

    var body: some View {
        switch phase {
        case .sent(let name):
            Text(l.tradeOfferSent(name)).font(.caption).foregroundStyle(.green)
                .fixedSize(horizontal: false, vertical: true)
        case .refused(let message):
            Text(message).font(.caption).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        case .failed:
            Text(l.tradeSendFailed).font(.caption).foregroundStyle(.orange)
        case .idle, .sending:
            EmptyView()
        }
    }
}
