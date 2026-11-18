import SwiftUI

private struct PokemonNameProviderKey: EnvironmentKey {
    static let defaultValue: any PokemonNameProviding = PokemonNameClient.shared
}

private struct PokemonNameStoreKey: EnvironmentKey {
    static let defaultValue: PokemonNameDisplayStore? = nil
}

extension EnvironmentValues {
    var pokemonNameProvider: any PokemonNameProviding {
        get { self[PokemonNameProviderKey.self] }
        set { self[PokemonNameProviderKey.self] = newValue }
    }

    /// Nil means `PokemonNameDisplayStore.shared`.
    var pokemonNameStore: PokemonNameDisplayStore? {
        get { self[PokemonNameStoreKey.self] }
        set { self[PokemonNameStoreKey.self] = newValue }
    }
}

/// A move the bot names in Korean, shown in the app language by its PokéAPI id. The bot's name stands in until the
/// translation loads, when it fails, and when the id is missing.
enum MoveName {
    static func resource(id: Int?) -> PokemonNameResource? {
        guard let id, id > 0 else { return nil }
        return PokemonNameResource(kind: .move, name: String(id))
    }

    static func text(id: Int?, botName: String, language: AppLanguage,
                     names: [PokemonNameResource: [String: String]]) -> String {
        guard let resource = resource(id: id), let translations = names[resource] else { return botName }
        return language.resolveName(translations) ?? botName
    }

    static func load(ids: some Sequence<Int>, store: PokemonNameDisplayStore,
                     provider: any PokemonNameProviding) async {
        let resources = Set(ids.compactMap { resource(id: $0) })
        await withTaskGroup(of: Void.self) { group in
            for resource in resources {
                group.addTask { _ = await store.load(resource, provider: provider) }
            }
        }
    }
}

@MainActor
struct MoveNameLabel: View {
    let id: Int
    let botName: String
    let language: AppLanguage
    @Environment(\.pokemonNameProvider) private var provider
    @Environment(\.pokemonNameStore) private var injectedStore

    var body: some View {
        let store = injectedStore ?? .shared
        Text(MoveName.text(id: id, botName: botName, language: language, names: store.names))
            .task(id: id) { await MoveName.load(ids: [id], store: store, provider: provider) }
    }
}
