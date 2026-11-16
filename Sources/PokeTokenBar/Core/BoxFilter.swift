import Foundation

/// One shop purchase that can still be taken back.
struct PurchaseReceipt: Equatable, Identifiable {
    static let window: TimeInterval = 5

    let id = UUID()
    let inventoryKey: String
    let count: Int
    let cost: Int
    let expiresAt: Date
}

enum BoxLevelFilter: String, Codable, CaseIterable, Sendable {
    case any, fiftyPlus, underFifty

    func admits(_ level: Int) -> Bool {
        switch self {
        case .any: true
        case .fiftyPlus: level >= 50
        case .underFifty: level < 50
        }
    }
}

/// Everything the Box toolbar narrows or orders by, except the search text.
struct BoxFilter: Codable, Equatable {
    var sort: BoxSortOption = .recent
    var shinyOnly = false
    var hasItemOnly = false
    var types: Set<PokemonType> = []
    var rarity: Rarity?
    var inLineupOnly = false
    var tradableOnly = false
    var level: BoxLevelFilter = .any

    /// Filters inside the filter menu that are switched on (the toolbar toggles and the sort show themselves).
    var menuActiveCount: Int {
        (types.isEmpty ? 0 : 1) + (rarity == nil ? 0 : 1) + (inLineupOnly ? 1 : 0)
            + (tradableOnly ? 1 : 0) + (level == .any ? 0 : 1)
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sort = (try? c.decodeIfPresent(BoxSortOption.self, forKey: .sort)) ?? .recent
        shinyOnly = (try? c.decodeIfPresent(Bool.self, forKey: .shinyOnly)) ?? false
        hasItemOnly = (try? c.decodeIfPresent(Bool.self, forKey: .hasItemOnly)) ?? false
        types = (try? c.decodeIfPresent(Set<PokemonType>.self, forKey: .types)) ?? []
        rarity = try? c.decodeIfPresent(Rarity.self, forKey: .rarity)
        inLineupOnly = (try? c.decodeIfPresent(Bool.self, forKey: .inLineupOnly)) ?? false
        tradableOnly = (try? c.decodeIfPresent(Bool.self, forKey: .tradableOnly)) ?? false
        level = (try? c.decodeIfPresent(BoxLevelFilter.self, forKey: .level)) ?? .any
    }
}

/// The Box's list state. The filter is kept per viewer in UserDefaults; the search text only lives as long as the
/// popover's navigation, so it survives a tab switch but not a relaunch.
@MainActor
@Observable
final class BoxFilterStore {
    static let defaultsKey = "boxFilter"

    var filter: BoxFilter {
        didSet { defaults.set(try? JSONEncoder().encode(filter), forKey: Self.defaultsKey) }
    }
    var searchText = ""

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        filter = defaults.data(forKey: Self.defaultsKey).flatMap { try? JSONDecoder().decode(BoxFilter.self, from: $0) }
            ?? BoxFilter()
    }

    func clear() {
        filter = BoxFilter()
        searchText = ""
    }
}
