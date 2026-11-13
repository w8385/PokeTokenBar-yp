import AVFoundation
import Foundation

/// Species cries from Pokémon Showdown, fetched at runtime and cached on disk. Showdown names
/// files by species (`mrmime.mp3`) and adds a form only where the cry differs (`shaymin-sky.mp3`),
/// so a form tries its own file first and falls back to the species.
actor CryStore {
    static let shared = CryStore()
    typealias Fetch = @Sendable (URL) async -> (Data, Int)?

    nonisolated let directory: URL
    private let fetch: Fetch
    private var loggedFailure = false

    init(directory: URL? = nil, fetch: @escaping Fetch = CryStore.download) {
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PokeTokenBar/cries", isDirectory: true)
        self.fetch = fetch
    }

    static func download(_ url: URL) async -> (Data, Int)? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    static func speciesURL(speciesID: Int) -> URL {
        URL(string: "https://pokeapi.co/api/v2/pokemon-species/\(speciesID)")!
    }

    /// PokéAPI species identifiers (`nidoran-f`, `type-null`) minus punctuation are Showdown ids.
    static func showdownID(_ identifier: String) -> String {
        String(String.UnicodeScalarView(identifier.lowercased().unicodeScalars.filter {
            ("a"..."z").contains($0) || ("0"..."9").contains($0)
        }))
    }

    static func cryURLs(identifier: String, speciesID: Int, form: PokemonForm?) -> [URL] {
        let base = "https://play.pokemonshowdown.com/audio/cries/\(showdownID(identifier))"
        var names = [base]
        if let form = PokemonForm.resolved(speciesID: speciesID, form: form),
           !PokemonForm.isDefault(form, speciesID: speciesID) {
            names.insert("\(base)-\(showdownID(form.rawValue))", at: 0)
        }
        return names.map { URL(string: "\($0).mp3")! }
    }

    func data(speciesID: Int, form: PokemonForm?) async -> Data? {
        let file = directory.appendingPathComponent("\(PokemonForm.assetName(speciesID: speciesID, form: form)).mp3")
        if let cached = try? Data(contentsOf: file), !cached.isEmpty { return cached }
        guard let identifier = await identifier(speciesID: speciesID) else { return failed(speciesID) }
        for url in Self.cryURLs(identifier: identifier, speciesID: speciesID, form: form) {
            guard let (data, status) = await fetch(url) else { return failed(speciesID) }
            guard status == 200, !data.isEmpty else { continue }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
            return data
        }
        return failed(speciesID)
    }

    private struct SpeciesName: Decodable { let name: String }

    private func identifier(speciesID: Int) async -> String? {
        guard let (data, status) = await fetch(Self.speciesURL(speciesID: speciesID)), status == 200 else { return nil }
        return (try? JSONDecoder().decode(SpeciesName.self, from: data))?.name
    }

    private func failed(_ speciesID: Int) -> Data? {
        if !loggedFailure {
            loggedFailure = true
            AppLog.write("cry: no sound for #\(speciesID) (offline or not found)")
        }
        return nil
    }
}

/// Plays one cry at a time: a new cry stops the one still playing.
@MainActor
final class CryPlayer {
    /// Silent under `swift test` and raw binaries, like the app's other network side effects.
    static let shared = CryPlayer(isEnabled: { AppEnv.isBundledApp && isEnabledInSettings() })
    static let enabledKey = "crySoundsEnabled"

    static func isEnabledInSettings(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? true
    }

    private let store: CryStore
    private let isEnabled: () -> Bool
    private let output: @MainActor (Data) -> Void
    private var pending: Task<Void, Never>?

    init(store: CryStore = .shared, isEnabled: @escaping () -> Bool,
         output: (@MainActor (Data) -> Void)? = nil) {
        self.store = store
        self.isEnabled = isEnabled
        let speaker = CrySpeaker()
        self.output = output ?? { speaker.play($0) }
    }

    /// An egg (`speciesID == nil`) has no cry.
    @discardableResult
    func play(speciesID: Int?, form: PokemonForm?) -> Task<Void, Never>? {
        guard let speciesID, isEnabled() else { return nil }
        pending?.cancel()
        let task = Task { [store, output] in
            guard let data = await store.data(speciesID: speciesID, form: form), !Task.isCancelled else { return }
            output(data)
        }
        pending = task
        return task
    }
}

@MainActor
final class CrySpeaker {
    private var player: AVAudioPlayer?

    func play(_ data: Data) {
        player?.stop()
        player = try? AVAudioPlayer(data: data)
        player?.volume = 0.5
        player?.play()
    }
}
