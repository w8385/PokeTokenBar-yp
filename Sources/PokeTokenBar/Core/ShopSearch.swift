import Foundation

struct ShopSearchResults: Equatable {
    var entriesBeforeHeld: [ShopEntry] = []
    var battleSections: [BattleItemSection] = []
    var entriesAfterHeld: [ShopEntry] = []
    var evolutionItems: [ItemKind] = []
    var scoutPools: [ScoutPool] = []
    var megaStones: [ShopEntry] = []
    var machines: [MachineEntry] = []

    var isEmpty: Bool {
        entriesBeforeHeld.isEmpty && battleSections.isEmpty && entriesAfterHeld.isEmpty && evolutionItems.isEmpty
            && scoutPools.isEmpty && megaStones.isEmpty && machines.isEmpty
    }
}

enum ShopSearch {
    struct Needle {
        let name: String
        let words: String

        init(_ query: String) {
            name = ShopSearch.fold(query)
            words = ShopSearch.foldWords(query)
        }
    }

    static func fold(_ text: String) -> String {
        caseless(text).filter { !$0.isWhitespace && $0 != "-" }
    }

    static func foldWords(_ text: String) -> String {
        caseless(text).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func caseless(_ text: String) -> String {
        let kana = text.applyingTransform(.hiraganaToKatakana, reverse: false) ?? text
        return kana.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    static func isActive(_ query: String) -> Bool { !fold(query).isEmpty }

    static func matches(_ needle: Needle, names: (L) -> String, effects: [String]) -> Bool {
        AppLanguage.allCases.contains { fold(names(L($0))).contains(needle.name) }
            || effects.contains { foldWords($0).contains(needle.words) }
    }

    static func subTabGroups(_ sections: [BattleItemSection]) -> [BattleItemGroup] {
        BattleItemGroup.allCases.filter { group in sections.contains { $0.group == group && !$0.kinds.isEmpty } }
    }

    static func sections(_ sections: [BattleItemSection], in group: BattleItemGroup?) -> [BattleItemSection] {
        guard let group else { return sections }
        return sections.filter { $0.group == group }
    }
}

struct ShopScreen: Equatable {
    /// nil: no search, the selected chip's normal view.
    var results: ShopSearchResults?
    /// Empty: no sub-tab row.
    var subTabs: [BattleItemGroup]
    var shownSubTab: BattleItemGroup?
    var heldSections: [BattleItemSection]
    var hasMachineTab: Bool
    var showsMachineTab: Bool

    var showsEmptyLine: Bool { results?.isEmpty == true }
}

extension CompanionStore {
    func shopScreen(category: ItemCategory?, query: String, heldGroup: BattleItemGroup?) -> ShopScreen {
        let searching = ShopSearch.isActive(query)
        let held = category == .heldItem
        return ShopScreen(
            results: searching ? shopSearch(query) : nil,
            subTabs: held ? ShopSearch.subTabGroups(shopBattleSections) : [],
            shownSubTab: held && !searching ? heldGroup : nil,
            heldSections: ShopSearch.sections(shopBattleSections, in: held ? heldGroup : nil),
            hasMachineTab: category == .machine,
            showsMachineTab: category == .machine && !searching)
    }

    func shopSearch(_ query: String) -> ShopSearchResults {
        let needle = ShopSearch.Needle(query)
        guard !needle.name.isEmpty else { return ShopSearchResults() }
        let l = self.l

        func hit(_ kind: ItemKind) -> Bool {
            let note = l.itemAppNote(kind)
            let noteBody = note.range(of: ": ").map { String(note[$0.upperBound...]) } ?? note
            return ShopSearch.matches(needle, names: { $0.itemName(kind) }, effects: [l.itemDescription(kind), noteBody])
        }
        func hit(_ entry: ShopEntry) -> Bool {
            switch entry {
            case .item(let kind): return hit(kind)
            case .egg(let tier):
                return ShopSearch.matches(needle, names: { $0.eggName(tier) }, effects: [l.eggDescription(tier)])
            case .megaStone(let stone):
                return ShopSearch.matches(needle, names: { $0.megaStoneName(stone) }, effects: [l.megaStoneDescription(stone)])
            }
        }

        let entries = shopEntries(in: nil)
        let heldStart = entries.firstIndex { $0.category == .heldItem } ?? entries.endIndex
        let flat = { (slice: ArraySlice<ShopEntry>) in slice.filter { $0.category != .heldItem && hit($0) } }
        var results = ShopSearchResults()
        results.entriesBeforeHeld = flat(entries[..<heldStart])
        results.entriesAfterHeld = flat(entries[heldStart...])
        results.battleSections = shopBattleSections.compactMap { section in
            let kinds = section.kinds.filter(hit)
            return kinds.isEmpty ? nil : BattleItemSection(group: section.group, kinds: kinds)
        }
        results.evolutionItems = shopAllViewEvolutionItems.filter(hit)
        results.scoutPools = ScoutPool.all.filter { pool in
            ShopSearch.matches(needle, names: { $0.scoutTicketName(pool) }, effects: [l.scoutDescription(pool)])
        }
        results.megaStones = megaStoneShopEntries.filter { entry in
            if case .item(let kind) = entry, kind.battleGroup != nil { return false }
            return hit(entry)
        }
        results.machines = machineShopMoves(query: query)
        return results
    }
}
