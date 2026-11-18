import SwiftUI

/// The Box page's training items for one Pokémon: Ability Capsule and Patch, Gold Bottle Cap and the form key
/// items. Only owned items show. The per-stat Bottle Cap sits on each stat row.
@MainActor
struct BoxTrainingControls: View {
    let store: CompanionStore
    let individualID: String
    let speciesID: Int
    @Binding var message: String?
    let onChange: () -> Void

    private var l: L { store.l }

    var body: some View {
        if let individual = store.trainable(id: individualID) {
            let capsule = store.itemCount(.abilityCapsule) > 0
            let patch = store.itemCount(.abilityPatch) > 0
            let gold = store.itemCount(.goldBottleCap) > 0
            let formTool = store.ownedFormTool(speciesID: speciesID)
            if capsule || patch || gold || formTool != nil {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    WrappingHStack(spacing: Spacing.sm, lineSpacing: Spacing.sm) {
                        if capsule {
                            itemButton(.abilityCapsule, enabled: store.capsuleTarget(of: individual) != nil) {
                                store.useAbilityCapsule(on: individualID)
                            }
                        }
                        if patch {
                            itemButton(.abilityPatch, enabled: store.patchTarget(of: individual) != nil) {
                                store.useAbilityPatch(on: individualID)
                            }
                        }
                        if gold {
                            let maxed = PokemonStatCalculator.order.allSatisfy {
                                individual.profile.ivs[$0] == BottleCap.maxIV
                            }
                            itemButton(.goldBottleCap, enabled: !maxed) { store.useGoldBottleCap(on: individualID) }
                        }
                    }
                    if let formTool { formPicker(formTool, current: individual.form) }
                    if (capsule || patch), store.abilityOptions(of: individual) != nil,
                       store.capsuleTarget(of: individual) == nil, store.patchTarget(of: individual) == nil {
                        note(l.abilityNothingToSwitch)
                    }
                    if let message { note(message) }
                }
            }
        }
    }

    private func itemButton(_ kind: ItemKind, enabled: Bool, use: @escaping () -> TrainingResult) -> some View {
        Button {
            message = nil
            switch use() {
            case .changed: onChange()
            case .unchanged, .unavailable, .short: message = l.trainingUnavailable
            }
        } label: {
            Label { Text("\(l.itemName(kind)) ×\(store.itemCount(kind))") } icon: { ItemIconView(kind: kind, size: 14) }
        }
        .buttonStyle(.bordered).controlSize(.mini).fixedSize()
        .disabled(!enabled)
        .help(l.trainingItemHelp(kind))
    }

    private func formPicker(_ tool: ItemKind, current: PokemonForm?) -> some View {
        let selection = Binding<PokemonForm?>(
            get: { PokemonForm.resolved(speciesID: speciesID, form: current) },
            set: { form in
                message = nil
                if let form, store.changeForm(of: individualID, to: form) == .changed { onChange() }
            })
        return HStack(spacing: Spacing.sm) {
            ItemIconView(kind: tool, size: 18).help(l.trainingItemHelp(tool))
            Picker(l.itemName(tool), selection: selection) {
                ForEach(PokemonForm.forms(speciesID: speciesID), id: \.self) { form in
                    Text(formLabel(form)).tag(Optional(form))
                }
            }
            .pickerStyle(.segmented).labelsHidden().controlSize(.small)
        }
    }

    private func formLabel(_ form: PokemonForm) -> String {
        PokemonForm.label(speciesID: speciesID, form: form, language: store.language) ?? form.rawValue
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
