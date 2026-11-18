import Foundation

/// What the Battle tab can show. `BattleView` renders them through an exhaustive switch.
enum BattleSection: Equatable {
    case entry, gyms, recent, linkLine
}

enum BattleSubTab: String, CaseIterable {
    case entry, battle, history

    /// `linked` is a saved token and a server address; a rejected token still counts, as it did before sub-tabs.
    func sections(linked: Bool, hasEntry: Bool) -> [BattleSection] {
        switch self {
        case .entry: linked ? (hasEntry ? [.entry] : []) : [.linkLine]
        case .battle: hasEntry ? [.gyms] : []
        case .history: linked ? [.recent] : [.linkLine]
        }
    }

    static let defaultsKey = "battleSubTab"

    static func stored(in defaults: UserDefaults = .standard) -> BattleSubTab {
        defaults.string(forKey: defaultsKey).flatMap(BattleSubTab.init(rawValue:)) ?? .entry
    }

    func store(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}
