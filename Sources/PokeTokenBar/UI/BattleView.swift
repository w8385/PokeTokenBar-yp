import SwiftUI

/// Battle tab, in three sub-tabs: the entry, the gyms and the recent battles. The YPoke link lives in Settings;
/// this tab only points there while it is missing. Trade and the coworkers list live on the Coworkers tab.
@MainActor
struct BattleView: View {
    let store: CompanionStore
    let navigation: PopoverNavigation
    @Environment(PartyUploader.self) private var uploader: PartyUploader?
    @Environment(BattleEntryStore.self) private var entry: BattleEntryStore?

    private let initialPickerQuery: String
    /// One gym service for the whole tab, so a result on screen survives a trip to another sub-tab.
    @State private var gym = GymServiceHolder()

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
                blocked: BattleEntry.itemBlockedCandidates(state: store.state, slots: entry.slots, replacing: current),
                sameSpecies: BattleEntry.speciesBlockedCandidates(state: store.state, slots: entry.slots,
                                                                  replacing: current),
                allowsAuto: lineup.count <= 1 && target != .add,
                initialQuery: initialPickerQuery,
                onPick: { id in
                    pick(id, target: target, entry: entry)
                    navigation.closeBattlePicker()
                    Task { await uploader.tick() }
                },
                onBack: { navigation.closeBattlePicker() })
            .frame(height: 520)
        } else {
            let layout = Self.layout(navigation.battleSubTab, uploader: uploader, hasEntry: entry != nil)
            VStack(spacing: 0) {
                Picker(l.battle, selection: Bindable(navigation).battleSubTab) {
                    ForEach(BattleSubTab.allCases, id: \.self) { Text(l.title(of: $0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.bottom, Spacing.md)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(layout.sections, id: \.self) { content(of: $0) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .reservesScrollerLane()
                }
                .id(navigation.battleSubTab)
                if layout.bottomLinkLine {
                    linkLine.padding(.top, 6)
                }
            }
            .frame(height: 520)
        }
    }

    struct Layout: Equatable {
        let sections: [BattleSection]
        let bottomLinkLine: Bool
    }

    static func layout(_ tab: BattleSubTab, uploader: PartyUploader?, hasEntry: Bool) -> Layout {
        guard let uploader else { return Layout(sections: [], bottomLinkLine: false) }
        let sections = tab.sections(linked: uploader.hasToken && uploader.hasServer, hasEntry: hasEntry)
        return Layout(sections: sections, bottomLinkLine: needsConnection(uploader) && !sections.contains(.linkLine))
    }

    @ViewBuilder
    private func content(of section: BattleSection) -> some View {
        switch section {
        case .entry:
            if let entry, let uploader {
                self.section(nil) {
                    BattleEntrySection(entry: entry, uploader: uploader) { navigation.battlePicker = $0 }
                }
            }
        case .gyms:
            if let entry, let uploader {
                self.section(l.gymSectionTitle) {
                    GymSection(store: store, uploader: uploader, entry: entry,
                               service: gym.resolve { GymSection.makeService(store: store, uploader: uploader) })
                }
            }
        case .recent:
            if let uploader {
                BattleInfoSections(info: uploader.battleInfo, l: l, parts: [.recent])
            }
        case .linkLine:
            linkLine
        }
    }

    private var linkLine: some View {
        Button { navigation.openYPokeSettings() } label: {
            Text(l.ypokeBattleLinkLine).font(.caption2).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                .ptbCard()
        }
    }
}

@MainActor
final class GymServiceHolder {
    private var service: GymService?

    func resolve(_ make: () -> GymService) -> GymService {
        if let service { return service }
        let made = make()
        service = made
        return made
    }
}
