import SwiftUI

/// Every card the Settings screen can show. `SettingsView` renders them through an exhaustive switch,
/// so a new card cannot exist without a tab (`SettingsTab.sections`).
enum SettingsSection: CaseIterable {
    case general, difficulty, menuBar, trackedProviders, floatingPet, notifications
    case update, transfer, advanced, aboutSupport, ypoke
}

enum SettingsTab: String, CaseIterable {
    case general, usage, companion, notifications, ypoke, advanced

    var sections: [SettingsSection] {
        switch self {
        case .general: [.general, .update, .aboutSupport]
        case .usage: [.menuBar, .trackedProviders]
        case .companion: [.difficulty, .floatingPet]
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

extension L {
    func title(of tab: SettingsTab) -> String {
        switch tab {
        case .general: generalSectionTitle
        case .usage: settingsTabUsage
        case .companion: settingsTabCompanion
        case .notifications: notificationsSection
        case .ypoke: "YPoke"
        case .advanced: advancedSectionTitle
        }
    }

    var settingsTabUsage: String {
        t("사용량", "Usage", "使用量", "Uso", "Utilisation", "Uso", "Nutzung", "Использование")
    }

    var settingsTabCompanion: String {
        t("동반자", "Companion", "相棒", "Compañero", "Compagnon", "Companheiro", "Begleiter", "Спутник")
    }

    var ypokeBattleLinkLine: String {
        t("YPoke 연결 안 됨 · 설정에서 연결", "YPoke not connected · Connect in Settings",
          "YPoke未接続 · 設定でつなぐ", "YPoke sin conectar · Conectar en Ajustes",
          "YPoke non connecté · Connecter dans Réglages", "YPoke não conectado · Conectar nos Ajustes",
          "YPoke nicht verbunden · In den Einstellungen verbinden", "YPoke не подключён · Подключить в настройках")
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
                        Image(systemName: tab.symbol).font(.system(size: 13, weight: .semibold))
                        if selected {
                            Text(l.title(of: tab)).font(.callout.weight(.semibold)).lineLimit(1).fixedSize()
                        }
                    }
                    .padding(.horizontal, selected ? 10 : 0)
                    .frame(maxWidth: selected ? nil : .infinity, minHeight: 26)
                    .background(selected ? Color.accentColor.opacity(0.18) : .clear,
                                in: RoundedRectangle(cornerRadius: 7))
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
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
    }
}
