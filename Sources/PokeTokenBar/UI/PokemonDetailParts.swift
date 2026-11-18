import SwiftUI

/// Pieces shared by the Pokédex species page and the Box individual page.

extension View {
    func detailCard() -> some View {
        self.padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ptbPanel()
    }
}

@MainActor
struct DetailTitle: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.callout.weight(.semibold)).foregroundStyle(.secondary)
    }
}

@MainActor
struct DetailValuePair: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.ptb(.body)).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.semibold))
        }
    }
}

@MainActor
struct PokemonStatRow: View {
    let l: L
    let name: String
    let value: Int
    let iv: Int?
    let scaleMaximum: Int
    /// Raises this IV to the maximum with a Bottle Cap; nil hides the button.
    var onCap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            Text(l.statLabel(name)).frame(width: 74, alignment: .leading)
            ProgressView(value: Double(value), total: Double(scaleMaximum)).tint(Color.accentColor)
            Text("\(value)").monospacedDigit().frame(width: 30, alignment: .trailing)
            if let iv { Text("IV \(iv)").foregroundStyle(.secondary).frame(width: 38, alignment: .trailing) }
            if let onCap {
                Button(action: onCap) { ItemIconView(kind: .bottleCap, size: 14) }
                    .buttonStyle(.borderless)
                    .help(l.bottleCapUse(l.statLabel(name)))
                    .accessibilityLabel(l.bottleCapUse(l.statLabel(name)))
            }
        }
        .font(.ptb(.label))
    }
}

/// What the PokéAPI call for a species' details is doing: nothing to show yet, failed with a retry, or loading.
@MainActor
struct PokemonDetailsPlaceholder: View {
    let store: CompanionStore
    let speciesID: Int

    var body: some View {
        if store.failedPokemonDetailIDs.contains(speciesID) {
            VStack(spacing: 8) {
                Text(store.l.pokemonDetailsUnavailable).foregroundStyle(.secondary)
                Button(store.l.retry) { Task { await store.loadPokemonDetails(speciesID: speciesID) } }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 24)
        } else {
            HStack { Spacer(); ProgressView(); Text(store.l.loadingPokemonDetails); Spacer() }
                .foregroundStyle(.secondary).padding(.vertical, 30)
        }
    }
}
