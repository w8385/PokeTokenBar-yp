import SwiftUI

/// Genus, one Pokédex entry and a cry button for a Pokédex detail page. The text arrives lazily;
/// offline or before the first response only the cry button shows.
@MainActor
struct SpeciesFlavorCard: View {
    let speciesID: Int
    var form: PokemonForm?
    let language: AppLanguage
    var provider: SpeciesFlavorProviding = SpeciesFlavorClient.shared
    var cryPlayer: CryPlayer = .shared
    @State private var flavor: SpeciesFlavor?
    @AppStorage(CryPlayer.enabledKey) private var cryEnabled = true

    var body: some View {
        let genus = flavor?.genus(in: language)
        let text = flavor?.flavorText(in: language)
        Group {
            if genus != nil || text != nil || cryEnabled {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        if let genus { Text(genus).font(.callout.weight(.semibold)) }
                        Spacer(minLength: 4)
                        if cryEnabled { cryButton }
                    }
                    if let text {
                        Text(text).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
            }
        }
        .task(id: speciesID) { flavor = await provider.flavor(speciesID: speciesID) }
    }

    private var cryButton: some View {
        Button {
            cryPlayer.play(speciesID: speciesID, form: form)
        } label: {
            Image(systemName: "speaker.wave.2.fill")
        }
        .buttonStyle(.borderless)
        .help(L(language).dexPlayCry)
        .accessibilityLabel(L(language).dexPlayCry)
    }
}
