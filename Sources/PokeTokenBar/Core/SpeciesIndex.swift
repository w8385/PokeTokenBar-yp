import Foundation

struct SpeciesIndexEntry: Codable, Sendable, Equatable {
    let id: Int
    let names: [String: String]
    let types: [String]
    let captureRate: Int
    let isLegendary: Bool
    let isMythical: Bool
    let evolvesFromID: Int?
}

/// Every supported species, so the Pokédex can show ones the user does not own yet.
struct SpeciesIndex: Sendable {
    enum Acquisition: Equatable, Sendable {
        case hatch(Rarity)
        case evolve(fromID: Int)
        case ditto
        case unavailable
    }

    private let entries: [Int: SpeciesIndexEntry]

    init(entries: [SpeciesIndexEntry]) {
        self.entries = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    }

    var all: [SpeciesIndexEntry] { entries.values.sorted { $0.id < $1.id } }
    var count: Int { entries.count }
    func entry(_ id: Int) -> SpeciesIndexEntry? { entries[id] }

    /// Start of the evolution line, or nil when the line leaves the index.
    func baseID(of id: Int) -> Int? {
        var current = entries[id]
        var seen: Set<Int> = []
        while let entry = current {
            guard let parent = entry.evolvesFromID else { return entry.id }
            guard seen.insert(entry.id).inserted else { return nil }
            current = entries[parent]
        }
        return nil
    }

    /// A line has the rarity of its base, like the hatched individual.
    func rarity(of id: Int) -> Rarity? {
        guard let base = baseID(of: id).flatMap({ entries[$0] }) else { return nil }
        return Rarity.from(captureRate: base.captureRate, isLegendary: base.isLegendary, isMythical: base.isMythical)
    }

    func acquisition(of id: Int) -> Acquisition {
        guard let entry = entries[id], let rarity = rarity(of: id) else { return .unavailable }
        if id == PokemonOdds.dittoSpeciesID { return .ditto }
        if let parent = entry.evolvesFromID { return .evolve(fromID: parent) }
        return .hatch(rarity)
    }

    /// One straight path: base → … → this species → onward while there is a single next form.
    /// A branch ends the path with a mystery marker, as on the home line.
    func lineItems(of id: Int) -> [EvoLineItemContent] {
        var path: [Int] = []
        var seen: Set<Int> = []
        var current = entries[id]
        while let entry = current, seen.insert(entry.id).inserted {
            path.append(entry.id)
            current = entry.evolvesFromID.flatMap { entries[$0] }
        }
        guard !path.isEmpty else { return [] }
        var items = path.reversed().map(EvoLineItemContent.species)
        var tip = id
        while true {
            let next = entries.values.filter { $0.evolvesFromID == tip }.map(\.id).sorted()
            if next.count > 1 { items.append(.mystery); break }
            guard let only = next.first, seen.insert(only).inserted else { break }
            items.append(.species(only))
            tip = only
        }
        return items
    }
}

protocol SpeciesIndexProviding: Sendable {
    func speciesIndex() async throws -> SpeciesIndex
}

/// Memory → 30-day disk cache → GraphQL → stale disk → REST. Nothing is bundled.
actor SpeciesIndexClient {
    static let shared = SpeciesIndexClient()

    private struct Snapshot: Codable {
        let fetchedAt: Date
        let maxSpeciesID: Int
        let entries: [SpeciesIndexEntry]
    }

    private struct GraphQLResponse: Decodable {
        struct Row: Decodable {
            struct Pokemon: Decodable {
                struct Slot: Decodable { struct Kind: Decodable { let name: String }; let type: Kind }
                let pokemontypes: [Slot]
            }
            let id: Int
            let capture_rate: Int
            let is_legendary: Bool
            let is_mythical: Bool
            let evolves_from_species_id: Int?
            let pokemonspeciesnames: [NameDTO]
            let pokemons: [Pokemon]
        }
        struct DataBox: Decodable { let pokemonspecies: [Row] }
        let data: DataBox
    }

    private struct RESTSpecies: Decodable {
        let id: Int
        let capture_rate: Int
        let is_legendary: Bool
        let is_mythical: Bool
        let names: [NameDTO]
        let evolves_from_species: NamedRef?
    }

    private struct RESTType: Decodable {
        struct Slot: Decodable {
            struct Mon: Decodable { let url: String }
            let slot: Int
            let pokemon: Mon
        }
        let pokemon: [Slot]
    }

    private let file: URL
    private let now: @Sendable () -> Date
    private let fetch: @Sendable (URLRequest) async throws -> Data
    private let maxID: Int
    private let minimumCount: Int
    private var cache: SpeciesIndex?
    private var inFlight: Task<SpeciesIndex, Error>?

    init(file: URL = AppStatePaths.directory().appendingPathComponent("species-index-v1.json"),
         now: @escaping @Sendable () -> Date = Date.init,
         maxSpeciesID: Int = PokemonAssets.supportedSpeciesIDs.upperBound,
         minimumCount: Int = PokemonAssets.supportedSpeciesIDs.count * 9 / 10,
         fetch: @escaping @Sendable (URLRequest) async throws -> Data = SpeciesIndexClient.download) {
        self.file = file
        self.now = now
        self.maxID = maxSpeciesID
        self.minimumCount = minimumCount
        self.fetch = fetch
    }

    static func download(_ request: URLRequest) async throws -> Data {
        var request = request
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    func index() async throws -> SpeciesIndex {
        if let cache { return cache }
        if let inFlight { return try await inFlight.value }
        let task = Task { try await load() }
        inFlight = task
        defer { inFlight = nil }
        let result = try await task.value
        cache = result
        return result
    }

    private func load() async throws -> SpeciesIndex {
        let disk = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
        let usable = disk.flatMap { $0.maxSpeciesID == maxID && $0.entries.count >= minimumCount ? $0 : nil }
        if let usable, now().timeIntervalSince(usable.fetchedAt) < 30 * 86400 {
            return SpeciesIndex(entries: usable.entries)
        }
        do {
            return try save(try await fetchGraphQL())
        } catch {
            AppLog.write("species index (GraphQL) failed: \(error)")
            if let usable { return SpeciesIndex(entries: usable.entries) }
            return try save(try await fetchREST())
        }
    }

    private func save(_ entries: [SpeciesIndexEntry]) throws -> SpeciesIndex {
        guard entries.count >= minimumCount else { throw URLError(.cannotParseResponse) }
        let snapshot = Snapshot(fetchedAt: now(), maxSpeciesID: maxID, entries: entries)
        if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: file, options: .atomic) }
        return SpeciesIndex(entries: entries)
    }

    private func fetchGraphQL() async throws -> [SpeciesIndexEntry] {
        guard let url = URL(string: "https://graphql.pokeapi.co/v1beta2") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let query = "{ pokemonspecies(where: {id: {_lte: \(maxID)}}, order_by: {id: asc}) { id capture_rate is_legendary is_mythical evolves_from_species_id pokemonspeciesnames { name language { name } } pokemons(where: {is_default: {_eq: true}}) { pokemontypes(order_by: {slot: asc}) { type { name } } } } }"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])
        let decoded = try JSONDecoder().decode(GraphQLResponse.self, from: try await fetch(request))
        return decoded.data.pokemonspecies.map { row in
            SpeciesIndexEntry(id: row.id,
                              names: PokemonNameLocalization.collect(row.pokemonspeciesnames),
                              types: row.pokemons.first?.pokemontypes.map(\.type.name) ?? [],
                              captureRate: row.capture_rate,
                              isLegendary: row.is_legendary, isMythical: row.is_mythical,
                              evolvesFromID: row.evolves_from_species_id)
        }
    }

    /// pokemon-species/{id} for every species plus one request per type for the type slots.
    private func fetchREST() async throws -> [SpeciesIndexEntry] {
        guard let base = URL(string: "https://pokeapi.co/api/v2") else { throw URLError(.badURL) }
        let fetch = self.fetch
        let maxID = self.maxID
        let decoder = JSONDecoder()
        var typesByID: [Int: [(slot: Int, name: String)]] = [:]
        for type in PokemonType.allCases {
            let dto = try decoder.decode(RESTType.self, from: try await fetch(URLRequest(url: base.appendingPathComponent("type/\(type.rawValue)"))))
            for member in dto.pokemon {
                let id = PokeAPIClient.id(from: member.pokemon.url)
                if (1...maxID).contains(id) { typesByID[id, default: []].append((member.slot, type.rawValue)) }
            }
        }
        let typeNames = typesByID.mapValues { $0.sorted { $0.slot < $1.slot }.map(\.name) }
        var entries: [SpeciesIndexEntry] = []
        var start = 1
        while start <= maxID {
            let ids = start...min(start + 7, maxID)
            let batch = await withTaskGroup(of: SpeciesIndexEntry?.self) { group -> [SpeciesIndexEntry] in
                for id in ids {
                    group.addTask {
                        guard let data = try? await fetch(URLRequest(url: base.appendingPathComponent("pokemon-species/\(id)"))),
                              let dto = try? decoder.decode(RESTSpecies.self, from: data) else { return nil }
                        return SpeciesIndexEntry(
                            id: dto.id,
                            names: PokemonNameLocalization.collect(dto.names),
                            types: typeNames[dto.id] ?? [],
                            captureRate: dto.capture_rate,
                            isLegendary: dto.is_legendary, isMythical: dto.is_mythical,
                            evolvesFromID: dto.evolves_from_species?.url.map(PokeAPIClient.id(from:)))
                    }
                }
                return await group.reduce(into: []) { if let entry = $1 { $0.append(entry) } }
            }
            entries.append(contentsOf: batch)
            start += 8
        }
        return entries.sorted { $0.id < $1.id }
    }
}

extension PokeAPIClient: SpeciesIndexProviding {
    func speciesIndex() async throws -> SpeciesIndex { try await SpeciesIndexClient.shared.index() }
}
