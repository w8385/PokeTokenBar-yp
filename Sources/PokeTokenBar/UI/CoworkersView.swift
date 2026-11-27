import SwiftUI

/// Coworkers tab: the linked coworkers' lead Pokémon and trading with them. The bot connection itself
/// is in Settings; without it this tab only points there.
@MainActor
struct CoworkersView: View {
    let store: CompanionStore
    let navigation: PopoverNavigation
    @Environment(PartyUploader.self) private var uploader: PartyUploader?
    @Environment(BattleEntryStore.self) private var entry: BattleEntryStore?
    @State private var tower = ServiceHolder<TowerService>()

    private var l: L { store.l }
    private var connected: Bool { (uploader?.hasToken ?? false) && (uploader?.hasServer ?? false) }

    var body: some View {
        if navigation.showingTradeOffer, connected, let entry, let uploader {
            TradeOfferView(
                store: store, uploader: uploader,
                fightingIDs: TradePool.fightingIDs(state: store.state, slots: entry.slots),
                initialGive: navigation.tradeGiveID,
                onBack: { navigation.showingTradeOffer = false })
            .frame(height: 520)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if connected, let uploader {
                        if entry != nil { tradeSection }
                        BattleInfoSections(info: uploader.battleInfo, l: l, parts: [.coworkers],
                                           trophies: store.state.coworkerTrophies)
                        TowerRankingCard(service: tower.resolve { TowerSection.makeService(store: store, uploader: uploader) },
                                         l: l)
                    } else {
                        notConnected
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .reservesScrollerLane()
            }
            .frame(height: 520)
        }
    }

    private var tradeSection: some View {
        card(l.tradeSectionTitle) {
            HStack(spacing: 10) {
                Text(l.tradeSectionHint).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button(l.tradeOfferButton) { navigation.openTradeOffer(giving: nil) }
                    .controlSize(.small)
            }
        }
    }

    private var notConnected: some View {
        card(l.friendsTitle) {
            VStack(alignment: .leading, spacing: 8) {
                Text(l.coworkersNotConnected).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(l.coworkersOpenConnection) { navigation.openYPokeSettings() }
                    .controlSize(.small)
            }
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                .textCase(.uppercase).padding(.leading, 4)
            content()
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ptbCard()
        }
    }
}
