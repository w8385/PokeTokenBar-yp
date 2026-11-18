import SwiftUI

/// Picks a nature for one Pokémon on the classic 5×5 chart, then asks once before using or buying a Mint.
@MainActor
struct NaturePicker: View {
    let store: CompanionStore
    let individualID: String
    let pokemonName: String
    let current: PokemonNature?
    let onClose: () -> Void
    /// Called after the nature changed, so the bot's copy of the party follows.
    let onChange: () -> Void

    @State private var picked: PokemonNature?
    @State private var refusal: String?

    private var l: L { store.l }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text(l.naturePickerTitle).font(.callout.weight(.semibold))
                Spacer()
                Button(l.close, action: onClose).buttonStyle(.borderless).controlSize(.small)
            }
            grid
            if let picked, picked != current { confirm(picked) }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1))
    }

    private var grid: some View {
        Grid(horizontalSpacing: Spacing.xxs, verticalSpacing: Spacing.xxs) {
            ForEach(NatureGrid.rows.indices, id: \.self) { row in
                GridRow {
                    ForEach(NatureGrid.rows[row], id: \.self) { nature in
                        cell(nature)
                    }
                }
            }
        }
    }

    enum Mark { case current, picked, none }

    static func mark(_ nature: PokemonNature, current: PokemonNature?, picked: PokemonNature?) -> Mark {
        nature == current ? .current : nature == picked ? .picked : .none
    }

    private func cell(_ nature: PokemonNature) -> some View {
        let mark = Self.mark(nature, current: current, picked: picked)
        let isCurrent = mark == .current
        let isPicked = mark == .picked
        return Button {
            refusal = nil
            picked = isCurrent ? nil : nature
        } label: {
            VStack(spacing: 1) {
                Text(nature.name(store.language)).font(.ptb(.small, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(Self.changeLabel(nature, l: l)).font(.ptb(.tiny)).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, minHeight: 34)
            .padding(.horizontal, 1)
            .background(isPicked ? Color.accentColor.opacity(0.25) : isCurrent ? Color.green.opacity(0.18)
                        : Color.secondary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: Radius.chip))
            .overlay(RoundedRectangle(cornerRadius: Radius.chip)
                .strokeBorder(isCurrent ? Color.green : isPicked ? Color.accentColor : .clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(nature.name(store.language))
        .accessibilityValue(isCurrent ? l.natureCurrent : isPicked ? l.naturePicked : "")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    static func changeLabel(_ nature: PokemonNature, l: L) -> String {
        guard let change = NatureGrid.change(of: nature) else { return "—" }
        return "↑\(shortStat(change.up, l: l)) ↓\(shortStat(change.down, l: l))"
    }

    private static func shortStat(_ stat: String, l: L) -> String {
        l.statName(stat.replacingOccurrences(of: "-", with: "_"))
    }

    private func confirm(_ nature: PokemonNature) -> some View {
        let payment = store.mintPayment
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(l.mintConfirmLine(pokemonName, from: current?.name(store.language) ?? "—",
                                   to: nature.name(store.language)))
                .font(.callout.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(l.mintPaymentLine(payment)).font(.caption)
                .foregroundStyle(paymentIsShort(payment) ? Color.orange : .secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let refusal {
                Text(refusal).font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button(l.cancel) { picked = nil }.controlSize(.small)
                Button(l.mintConfirmButton(payment)) { apply(nature) }
                    .controlSize(.small).buttonStyle(.borderedProminent)
                    .disabled(paymentIsShort(payment))
            }
        }
        .padding(.top, Spacing.xs)
    }

    private func paymentIsShort(_ payment: MintPayment) -> Bool {
        if case .short = payment { return true }
        return false
    }

    private func apply(_ nature: PokemonNature) {
        switch store.changeNature(of: individualID, to: nature) {
        case .changed:
            picked = nil
            onChange()
            onClose()
        case .unchanged: picked = nil
        case .short: refusal = l.mintPaymentLine(store.mintPayment)
        case .unavailable: refusal = l.trainingUnavailable
        }
    }
}
