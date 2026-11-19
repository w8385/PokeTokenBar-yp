import SwiftUI

/// Every card the Settings screen can show. `SettingsView` renders them through an exhaustive switch,
/// so a new card cannot exist without a tab (`SettingsTab.sections`).
enum SettingsSection: CaseIterable {
    case general, growthMode, menuBar, trackedProviders, floatingPet, notifications
    case update, transfer, advanced, aboutSupport, ypoke
}

enum SettingsTab: String, CaseIterable {
    case general, usage, companion, notifications, ypoke, advanced

    var sections: [SettingsSection] {
        switch self {
        case .general: [.general, .update, .aboutSupport]
        case .usage: [.menuBar, .trackedProviders]
        case .companion: [.growthMode, .floatingPet]
        case .notifications: [.notifications]
        case .ypoke: [.ypoke]
        case .advanced: [.transfer, .advanced]
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .usage: "chart.bar"
        case .companion: "pawprint"
        case .notifications: "bell"
        case .ypoke: "link"
        case .advanced: "slider.horizontal.3"
        }
    }

    static let defaultsKey = "settingsTab"

    static func stored(in defaults: UserDefaults = .standard) -> SettingsTab {
        defaults.string(forKey: defaultsKey).flatMap(SettingsTab.init(rawValue:)) ?? .general
    }

    func store(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}

/// Six tabs do not fit as native segments in every language, so only the selected tab spells its name;
/// the rest are icons with a tooltip and an accessibility label.
@MainActor
struct SettingsTabPicker: View {
    @Binding var selection: SettingsTab
    let l: L

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                let selected = tab == selection
                Button { selection = tab } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.symbol).font(.ptb(.control, weight: .semibold))
                        if selected {
                            Text(l.title(of: tab)).font(.callout.weight(.semibold)).lineLimit(1).fixedSize()
                        }
                    }
                    .padding(.horizontal, selected ? 10 : 0)
                    .frame(maxWidth: selected ? nil : .infinity, minHeight: 26)
                    .background(selected ? Color.accentColor.opacity(0.18) : .clear,
                                in: RoundedRectangle(cornerRadius: Radius.chip))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selected ? Color.accentColor : .secondary)
                .help(l.title(of: tab))
                .accessibilityLabel(l.title(of: tab))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: Radius.card))
    }
}
