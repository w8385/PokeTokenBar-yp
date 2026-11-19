import SwiftUI

/// The Box detail's post button. It shows only while the bot offers miracle trades, nothing of this player's is
/// up yet, and the Pokémon is tradable.
@MainActor
struct MiraclePostButton: View {
    let model: MiracleTradeModel
    let individualID: String
    let refusal: TradeRefusal?
    let l: L

    var body: some View {
        if MiracleTradeModel.showsPostButton(availability: model.availability, offer: model.offer, refusal: refusal) {
            Button {
                Task { await model.post(individualID) }
            } label: {
                Label(l.miraclePostButton, systemImage: "sparkles")
            }
            .buttonStyle(.bordered).controlSize(.mini).fixedSize()
            .disabled(model.phase == .sending)
        }
    }
}

/// The open offer of this Pokémon with its take-down button, and the last post or take-down result.
@MainActor
struct MiracleOfferStatus: View {
    let model: MiracleTradeModel
    let individualID: String
    let l: L

    var body: some View {
        if model.isOffered(individualID) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(spacing: Spacing.sm) {
                    Label(l.miracleListed, systemImage: "sparkles")
                        .font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                    Spacer(minLength: Spacing.xs)
                    Button(l.miracleTakeDown) { Task { await model.cancel() } }
                        .buttonStyle(.bordered).controlSize(.mini).fixedSize()
                        .disabled(model.phase == .sending)
                }
                Text(l.miracleListedHint).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.md)
            .ptbPanel()
        }
        switch model.phase {
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
