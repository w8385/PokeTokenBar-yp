import SwiftUI

/// Battle tab: the battle entry and the recent battles. The YPoke link lives in Settings; this tab only
/// points there while it is missing. Trade and the coworkers list live on the Coworkers tab.
@MainActor
struct BattleView: View {
    let store: CompanionStore
    let navigation: PopoverNavigation
    @Environment(PartyUploader.self) private var uploader: PartyUploader?
    @Environment(BattleEntryStore.self) private var entry: BattleEntryStore?

    private let initialPickerQuery: String

    private var l: L { store.l }

    init(store: CompanionStore, navigation: PopoverNavigation, initialPickerQuery: String = "") {
        self.store = store
        self.navigation = navigation
        self.initialPickerQuery = initialPickerQuery
    }

    var body: some View {
        if let target = navigation.battlePicker, let entry, let uploader {
            let lineup = BattleEntry.lineup(state: store.state, slots: entry.slots)
            let current = currentID(of: target)
            BattleFighterPicker(
                store: store,
                current: current,
                excluding: Set(lineup.map(\.id)).subtracting(current.map { [$0] } ?? []),
                allowsAuto: lineup.count <= 1 && target != .add,
                initialQuery: initialPickerQuery,
                onPick: { id in
                    pick(id, target: target, entry: entry)
                    navigation.battlePicker = nil
                    Task { await uploader.tick() }
                },
                onBack: { navigation.battlePicker = nil })
            .frame(height: 520)
        } else {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let uploader {
                            if uploader.hasToken, uploader.hasServer, let entry {
                                section(nil) {
                                    BattleEntrySection(entry: entry, uploader: uploader) {
                                        navigation.battlePicker = $0
                                    }
                                }
                            }
                            if uploader.hasToken, uploader.hasServer {
                                BattleInfoSections(info: uploader.battleInfo, l: l, parts: [.recent])
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .reservesScrollerLane()
                }
                if Self.needsConnection(uploader) {
                    Button { navigation.openYPokeSettings() } label: {
                        Text(l.ypokeBattleLinkLine).font(.caption2).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                }
            }
            .frame(height: 520)
        }
    }

    /// Not linked, link rejected, or no server address: nothing else on this tab can work yet.
    static func needsConnection(_ uploader: PartyUploader?) -> Bool {
        guard let uploader else { return false }
        return !uploader.hasToken || uploader.tokenRejected || !uploader.hasServer
    }

    private func currentID(of target: BattlePickerTarget) -> String? {
        if case .slot(let id) = target { id } else { nil }
    }

    /// A nil pick is "follow the Pokémon being raised": it drops the one slot being changed.
    private func pick(_ id: String?, target: BattlePickerTarget, entry: BattleEntryStore) {
        entry.prune(owned: Set(BattleEntry.candidates(in: store.state).map(\.id)))
        switch (target, id) {
        case (.add, let id?): entry.add(id, pinning: BattleEntry.autoFighter(state: store.state)?.id)
        case (.slot(let old), let id?): entry.replace(old, with: id)
        case (.slot(let old), nil): entry.remove(old)
        case (.add, nil): break
        }
    }

    private func section<Content: View>(_ title: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                    .textCase(.uppercase).padding(.leading, 4)
            }
            VStack(spacing: 0) { content() }
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1))
        }
    }
}
