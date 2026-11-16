import Foundation

struct MachineEntry: Identifiable, Hashable, Sendable {
    let id: Int
    let type: String
    let power: Int
    let weather: String
    let ko: String
    let en: String
    let ja: String

    var isWeather: Bool { !weather.isEmpty }

    /// Korean and Japanese have their own names; every other language shows the English one.
    func name(_ language: AppLanguage) -> String {
        switch language {
        case .ko: ko
        case .ja: ja
        default: en
        }
    }
}

/// The shop's TM list. It is parsed from `MachineCatalogTable`, which `scripts/generate-tm-catalog.py` writes.
enum MachineCatalog {
    static let moves: [MachineEntry] = MachineCatalogTable.moves.split(separator: "\n").compactMap { line in
        let fields = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 7, let id = Int(fields[0]), let power = Int(fields[2]) else { return nil }
        return MachineEntry(id: id, type: fields[1], power: power, weather: fields[3], ko: fields[4], en: fields[5], ja: fields[6])
    }

    static let learnersBySpecies: [Int: Set<Int>] = Dictionary(
        MachineCatalogTable.learners.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: ":")
            guard parts.count == 2, let species = Int(parts[0]) else { return nil }
            return (species, Set(parts[1].split(separator: ",").compactMap { Int($0) }))
        }, uniquingKeysWith: { $0.union($1) })

    /// Species in `owned` that learn the move by machine.
    static func learners(of moveID: Int, among owned: Set<Int>) -> Set<Int> {
        owned.filter { learnersBySpecies[$0]?.contains(moveID) == true }
    }

    /// Case, width, accent, kana and space insensitive containment over all three names and the type id.
    static func matches(_ move: MachineEntry, query: String) -> Bool {
        let needle = fold(query)
        if needle.isEmpty { return true }
        return [move.ko, move.en, move.ja, move.type].contains { fold($0).contains(needle) }
    }

    private static func fold(_ text: String) -> String {
        let kana = text.applyingTransform(.hiraganaToKatakana, reverse: false) ?? text
        return kana.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .filter { !$0.isWhitespace && $0 != "-" }
    }
}

extension CompanionStore {
    /// The shop list for the TM category: unowned first, then moves one of my Pokémon learns, then cheaper first.
    func machineShopMoves(query: String = "", type: String? = nil, learnableOnly: Bool = false) -> [MachineEntry] {
        let mine = state.ownedSpeciesIDs
        func isMine(_ move: MachineEntry) -> Bool { !MachineCatalog.learners(of: move.id, among: mine).isEmpty }
        return MachineCatalog.moves
            .filter { type == nil || $0.type == type }
            .filter { MachineCatalog.matches($0, query: query) }
            .filter { !learnableOnly || isMine($0) }
            .sorted { a, b in
                let key: (MachineEntry) -> [Int] = {
                    [self.ownsTM($0.id) ? 1 : 0, isMine($0) ? 0 : 1, self.tmPrice(power: $0.power, isWeather: $0.isWeather), $0.id]
                }
                return key(a).lexicographicallyPrecedes(key(b))
            }
    }
}
