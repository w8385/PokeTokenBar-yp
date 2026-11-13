import Foundation
import Observation

/// One party slot in the YPoke bot's `POST /v1/party` body (`bot/API.md`).
struct PartyMember: Encodable, Equatable, Sendable {
    let pokemonID: Int
    let level: Int
    let shiny: Bool
    let ivs: PokemonIVs?
    /// PokéAPI move ids; nil lets the bot pick the 4 most recently learned.
    var moves: [Int]? = nil
    /// True only for the loaner sent before the first hatch; the bot then sets its level. Nil is left out of the JSON.
    var rental: Bool? = nil
    /// Lowercase `PokemonNature` name; nil is left out of the JSON and the bot treats it as neutral.
    var nature: String? = nil
}

struct PartyPayload: Encodable, Equatable, Sendable {
    let appVersion: String?
    let party: [PartyMember]

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(self)
    }
}

enum PartyBuilder {
    /// The Pokémon being raised now, sent when no battle entry is chosen; an egg has none.
    static func party(from state: CompanionState) -> [PartyMember] {
        guard let active = state.active else { return [] }
        let raised = member(speciesID: active.currentID, form: active.form,
                            shiny: active.displaysShiny, profile: active.profile, nature: active.nature)
        return isAcceptedPokemonID(raised.pokemonID) ? [raised] : []
    }

    static func member(speciesID: Int, form: PokemonForm?, shiny: Bool, profile: PokemonProfile?,
                       nature: PokemonNature? = nil) -> PartyMember {
        let resolved = PokemonForm.resolved(speciesID: speciesID, form: form)
        let variety = PokemonForm.entries(speciesID: speciesID).first { $0.form == resolved }?.pokemonID
        return PartyMember(pokemonID: variety ?? speciesID,
                           level: min(100, max(1, profile?.level ?? 1)),
                           shiny: shiny,
                           ivs: profile?.ivs,
                           nature: nature?.rawValue)
    }

    static func isAcceptedPokemonID(_ id: Int) -> Bool {
        (1...1025).contains(id) || (10001...10999).contains(id)
    }
}

/// `poketokenbar://ypoke-register?token=…&server=…`, the link the bot DMs on `/포켓몬연결`.
struct PartyRegistrationLink: Sendable {
    static let host = "ypoke-register"

    let token: String
    /// Nil when the link has no valid `server`; the app then keeps the server it has.
    let server: String?

    init?(url: URL) {
        guard url.scheme?.lowercased() == AgentActivityEvent.scheme,
              url.host?.lowercased() == Self.host,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let token = items.first(where: { $0.name == "token" })?.value.flatMap(PartyTokenStore.normalize)
        else { return nil }
        self.token = token
        server = items.first(where: { $0.name == "server" })?.value
            .flatMap { PartyUploader.baseURL($0) != nil ? $0.trimmingCharacters(in: .whitespacesAndNewlines) : nil }
    }
}

/// Upload token file, owner-only (0600). Not an app-owned Keychain item: those prompt after every
/// re-sign (see `SessionKeyStore`).
struct PartyTokenStore: Sendable {
    let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? AppStatePaths.directory().appendingPathComponent("party-upload-token")
    }

    func load() -> String? {
        guard let data = try? Data(contentsOf: fileURL),
              let token = String(data: data, encoding: .utf8), !token.isEmpty
        else { return nil }
        return token
    }

    func save(_ token: String) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: fileURL)
        FileManager.default.createFile(
            atPath: fileURL.path, contents: nil,
            attributes: [.posixPermissions: NSNumber(value: Int16(0o600))])
        try Data(token.utf8).write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))], ofItemAtPath: fileURL.path)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    static func normalize(_ raw: String) -> String? {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, token.count <= 512,
              !token.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0) || CharacterSet.whitespaces.contains($0)
              })
        else { return nil }
        return token
    }
}

/// Posts the party to the YPoke bot while a token is set. Every failure is silent; the bot keeps the last party.
@MainActor
@Observable
final class PartyUploader {
    static let serverURLDefaultsKey = "partyUploadServerURL"
    static let lastSuccessDefaultsKey = "partyUploadLastSuccessAt"
    static let checkInterval: TimeInterval = 60
    nonisolated static let resendInterval: TimeInterval = 300

    typealias Send = @Sendable (URLRequest) async throws -> Int
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, Int)

    private(set) var hasToken: Bool
    private(set) var lastSuccessAt: Date? {
        didSet { defaults.set(lastSuccessAt, forKey: Self.lastSuccessDefaultsKey) }
    }
    /// The latest attempt got no answer or an error other than 401; cleared by the next success.
    private(set) var lastAttemptFailed = false
    private(set) var tokenRejected = false
    var serverURL: String {
        didSet {
            defaults.set(serverURL, forKey: Self.serverURLDefaultsKey)
            resetThrottle()
        }
    }

    @ObservationIgnored private let tokenStore: PartyTokenStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let send: Send
    @ObservationIgnored private let fetch: Fetch
    @ObservationIgnored private let appVersion: String?
    @ObservationIgnored private let partySource: @MainActor () -> [PartyMember]
    @ObservationIgnored private var lastAttemptAt: Date?
    @ObservationIgnored private var lastAttemptBody: Data?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private(set) var isSending = false

    init(tokenStore: PartyTokenStore = PartyTokenStore(),
         defaults: UserDefaults = .standard,
         appVersion: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
         send: @escaping Send = PartyUploader.urlSessionSend,
         fetch: @escaping Fetch = PartyUploader.urlSessionFetch,
         partySource: @escaping @MainActor () -> [PartyMember]) {
        self.tokenStore = tokenStore
        self.defaults = defaults
        self.appVersion = appVersion
        self.send = send
        self.fetch = fetch
        self.partySource = partySource
        hasToken = tokenStore.load() != nil
        serverURL = defaults.string(forKey: Self.serverURLDefaultsKey) ?? ""
        lastSuccessAt = hasToken ? defaults.object(forKey: Self.lastSuccessDefaultsKey) as? Date : nil
    }

    var hasServer: Bool { Self.baseURL(serverURL) != nil }

    func register(_ link: PartyRegistrationLink) -> Bool {
        guard saveToken(link.token) else { return false }
        if let server = link.server { serverURL = server }
        return true
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(nanoseconds: UInt64(Self.checkInterval * 1_000_000_000))
            }
        }
    }

    /// False when the token is invalid; the stored token is left as it was.
    @discardableResult
    func saveToken(_ raw: String) -> Bool {
        guard let token = PartyTokenStore.normalize(raw), (try? tokenStore.save(token)) != nil else { return false }
        hasToken = true
        tokenRejected = false
        lastAttemptFailed = false
        lastSuccessAt = nil
        resetThrottle()
        return true
    }

    func clearToken() {
        tokenStore.clear()
        hasToken = false
        tokenRejected = false
        lastAttemptFailed = false
        lastSuccessAt = nil
        resetThrottle()
    }

    func tick(now: Date = Date()) async {
        guard let token = tokenStore.load() else { return }
        let party = partySource()
        guard !party.isEmpty,
              let body = try? PartyPayload(appVersion: appVersion, party: party).encoded(),
              Self.shouldSend(body: body, lastBody: lastAttemptBody, lastAttemptAt: lastAttemptAt, now: now),
              let request = Self.request(serverURL: serverURL, token: token, body: body)
        else { return }
        lastAttemptAt = now
        lastAttemptBody = body
        isSending = true
        defer { isSending = false }
        guard let status = try? await send(request) else {
            lastAttemptFailed = true
            return
        }
        switch status {
        case 200: lastSuccessAt = now; tokenRejected = false; lastAttemptFailed = false
        case 401: tokenRejected = true; lastAttemptFailed = false
        default: lastAttemptFailed = true
        }
    }

    /// Nil when there is no token or server, or the bot cannot answer.
    func learnableMoves(pokemonID: Int, level: Int) async -> LearnableMoves? {
        guard let token = tokenStore.load(),
              let request = Self.movesRequest(serverURL: serverURL, token: token, pokemonID: pokemonID, level: level),
              let (data, status) = try? await fetch(request), status == 200
        else { return nil }
        return try? LearnableMoves.decode(data)
    }

    private func resetThrottle() {
        lastAttemptAt = nil
        lastAttemptBody = nil
    }

    nonisolated static func shouldSend(body: Data, lastBody: Data?, lastAttemptAt: Date?, now: Date) -> Bool {
        guard let lastAttemptAt, body == lastBody else { return true }
        return now.timeIntervalSince(lastAttemptAt) >= resendInterval
    }

    nonisolated static func baseURL(_ serverURL: String) -> URL? {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let base = URL(string: trimmed), let scheme = base.scheme?.lowercased(),
              scheme == "http" || scheme == "https", base.host?.isEmpty == false
        else { return nil }
        return base
    }

    nonisolated static func request(serverURL: String, token: String, body: Data) -> URLRequest? {
        guard let base = baseURL(serverURL) else { return nil }
        var request = URLRequest(url: base.appending(path: "v1/party"), timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        return request
    }

    nonisolated static func movesRequest(serverURL: String, token: String, pokemonID: Int, level: Int) -> URLRequest? {
        guard let base = baseURL(serverURL) else { return nil }
        let url = base.appending(path: "v1/moves").appending(queryItems: [
            URLQueryItem(name: "pokemon_id", value: String(pokemonID)),
            URLQueryItem(name: "level", value: String(level)),
        ])
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    static let urlSessionSend: Send = { request in
        let (_, response) = try await session.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    }

    static let urlSessionFetch: Fetch = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

/// `GET /v1/moves`: attacking level-up moves learnable at a level, oldest first.
struct LearnableMoves: Decodable, Equatable, Sendable {
    let moves: [LearnableMove]
    let `default`: [Int]

    static func decode(_ data: Data) throws -> LearnableMoves {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(LearnableMoves.self, from: data)
    }
}

struct LearnableMove: Decodable, Equatable, Sendable, Identifiable {
    let id: Int
    let name: String
    let type: String
    let power: Int
    let damageClass: String
    let accuracy: Int?
    let level: Int
    /// The fields below are nil from bots older than yp8.
    var pp: Int? = nil
    var critRate: Int? = nil
    var ailment: String? = nil
    var ailmentChance: Int? = nil
    var statChanges: [StatChange]? = nil
    var statTarget: String? = nil
    var statChance: Int? = nil

    struct StatChange: Decodable, Equatable, Sendable {
        let stat: String
        let change: Int
    }
}
