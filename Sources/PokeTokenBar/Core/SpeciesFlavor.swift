import Foundation

/// Genus ("Seed Pokémon") and one Pokédex entry per language, as the Pokédex detail pages show them.
struct SpeciesFlavor: Codable, Sendable, Equatable {
    let genus: [String: String]
    let flavor: [String: String]

    func genus(in language: AppLanguage) -> String? { language.resolveName(genus) }
    func flavorText(in language: AppLanguage) -> String? { language.resolveName(flavor) }

    /// PokéAPI lists entries oldest game first, so the last entry of a language is its newest.
    init(genera: [GenusDTO], flavorEntries: [FlavorEntryDTO]) {
        var genus: [String: String] = [:]
        for entry in genera {
            let code = PokemonNameLocalization.languageCode(entry.language.name)
            let text = entry.genus.trimmingCharacters(in: .whitespacesAndNewlines)
            if !code.isEmpty && !text.isEmpty { genus[code] = text }
        }
        var flavor: [String: String] = [:]
        for entry in flavorEntries {
            let code = PokemonNameLocalization.languageCode(entry.language.name)
            let text = Self.normalize(entry.flavor_text, language: code)
            if !code.isEmpty && !text.isEmpty { flavor[code] = text }
        }
        self.genus = genus
        self.flavor = flavor
    }

    /// Game text is hard-wrapped with newlines, page breaks (form feed) and soft hyphens.
    /// Japanese and Chinese have no spaces between words, so lines join without one there.
    static func normalize(_ raw: String, language: String) -> String {
        let joiner = language.hasPrefix("ja") || language.hasPrefix("zh") ? "" : " "
        var text = raw.replacingOccurrences(of: "\u{00AD}\n", with: "")
            .replacingOccurrences(of: "\u{00AD}", with: "")
        if joiner == " " { text = text.replacingOccurrences(of: "-\n", with: "-") }
        text = text.replacingOccurrences(of: "\u{000C}", with: joiner)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: joiner)
        if joiner == " " {
            text = text.split(whereSeparator: { $0 == " " }).joined(separator: " ")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct GenusDTO: Decodable, Sendable { let genus: String; let language: NamedRef }
struct FlavorEntryDTO: Decodable, Sendable { let flavor_text: String; let language: NamedRef }

protocol SpeciesFlavorProviding: Sendable {
    /// nil while offline or when the species has no entry; the pages then simply omit the lines.
    func flavor(speciesID: Int) async -> SpeciesFlavor?
}

/// Memory → one disk file per species → PokéAPI `pokemon-species/{id}`. Fetched when a detail page
/// opens, never in bulk. The text does not change, so a cached file never expires.
actor SpeciesFlavorClient: SpeciesFlavorProviding {
    /// Offline under `swift test` and raw binaries, like the app's other network side effects.
    static let shared = SpeciesFlavorClient(fetch: { AppEnv.isBundledApp ? await CryStore.download($0) : nil })
    typealias Fetch = @Sendable (URL) async -> (Data, Int)?

    private struct SpeciesDTO: Decodable {
        let genera: [GenusDTO]
        let flavor_text_entries: [FlavorEntryDTO]
    }

    private let directory: URL
    private let fetch: Fetch
    private var memory: [Int: SpeciesFlavor] = [:]
    private var inFlight: [Int: Task<SpeciesFlavor?, Never>] = [:]

    init(directory: URL = AppStatePaths.directory().appendingPathComponent("species-flavor-v1", isDirectory: true),
         fetch: @escaping Fetch = CryStore.download) {
        self.directory = directory
        self.fetch = fetch
    }

    func flavor(speciesID: Int) async -> SpeciesFlavor? {
        if let cached = memory[speciesID] { return cached }
        if let task = inFlight[speciesID] { return await task.value }
        let task = Task { await load(speciesID) }
        inFlight[speciesID] = task
        let result = await task.value
        inFlight[speciesID] = nil
        if let result { memory[speciesID] = result }
        return result
    }

    private func load(_ id: Int) async -> SpeciesFlavor? {
        let file = directory.appendingPathComponent("\(id).json")
        if let data = try? Data(contentsOf: file), let cached = try? JSONDecoder().decode(SpeciesFlavor.self, from: data) {
            return cached
        }
        guard let (data, status) = await fetch(CryStore.speciesURL(speciesID: id)), status == 200,
              let dto = try? JSONDecoder().decode(SpeciesDTO.self, from: data) else { return nil }
        let flavor = SpeciesFlavor(genera: dto.genera, flavorEntries: dto.flavor_text_entries)
        guard !flavor.genus.isEmpty || !flavor.flavor.isEmpty else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let encoded = try? JSONEncoder().encode(flavor) { try? encoded.write(to: file, options: .atomic) }
        return flavor
    }
}
