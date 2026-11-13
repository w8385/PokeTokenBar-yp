import SwiftUI

/// Battle tab rows for picking up to 3 owned Pokémon, their order, and each one's moves.
@MainActor
struct BattleEntrySection: View {
    @Environment(CompanionStore.self) private var companion
    let entry: BattleEntryStore
    let uploader: PartyUploader

    @State private var expandedID: String?
    @State private var learnable: [String: LearnableMoves] = [:]
    @State private var unavailable: Set<String> = []

    private var l: L { companion.l }

    var body: some View {
        let candidates = BattleEntry.candidates(in: companion.state)
        let chosen = entry.slots.compactMap { slot in
            candidates.first { $0.id == slot.instanceID }.map { (slot, $0) }
        }
        row {
            VStack(alignment: .leading, spacing: 1) {
                Text(l.battleEntryLabel)
                Text(l.battleEntryHint).font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Menu(l.battleEntryAdd) {
                ForEach(candidates.filter { !entry.contains($0.id) }) { candidate in
                    Button(label(candidate)) { change { entry.add(candidate.id) } }
                }
            }
            .fixedSize()
            .disabled(entry.isFull || candidates.allSatisfy { entry.contains($0.id) })
        }
        ForEach(Array(chosen.enumerated()), id: \.element.1.id) { index, pair in
            slotRow(index: index, slot: pair.0, candidate: pair.1, count: chosen.count)
            if expandedID == pair.1.id {
                moveList(slot: pair.0, member: pair.1.member, id: pair.1.id)
            }
        }
    }

    private func slotRow(index: Int, slot: BattleEntrySlot, candidate: BattleCandidate, count: Int) -> some View {
        row {
            Text("\(index + 1).").monospacedDigit().foregroundStyle(.secondary)
            Text(label(candidate)).lineLimit(1)
            if candidate.dexEntry == nil {
                Text(l.battleEntryRaising).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                expandedID = expandedID == candidate.id ? nil : candidate.id
            } label: {
                HStack(spacing: 2) {
                    Text(l.battleEntryMoves)
                    Image(systemName: expandedID == candidate.id ? "chevron.up" : "chevron.down")
                }
            }
            Button { change { entry.move(candidate.id, by: -1) } } label: { Image(systemName: "arrow.up") }
                .disabled(index == 0)
            Button { change { entry.move(candidate.id, by: 1) } } label: { Image(systemName: "arrow.down") }
                .disabled(index == count - 1)
            Button { change { entry.remove(candidate.id) } } label: { Image(systemName: "xmark") }
        }
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private func moveList(slot: BattleEntrySlot, member: PartyMember, id: String) -> some View {
        let key = "\(member.pokemonID)-\(member.level)"
        VStack(alignment: .leading, spacing: 4) {
            if let moves = learnable[key] {
                let custom = slot.pokemonID == member.pokemonID && !slot.moves.isEmpty
                let selected = custom ? slot.moves : moves.default
                Button(l.battleEntryAutoMoves) { change { entry.resetMoves(for: id) } }
                    .buttonStyle(.borderless).font(.caption)
                    .disabled(!custom)
                ForEach(moves.moves.reversed()) { move in
                    let isOn = selected.contains(move.id)
                    Button {
                        change {
                            entry.toggleMove(move.id, for: id, pokemonID: member.pokemonID, current: selected)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isOn ? "checkmark.square.fill" : "square")
                            Text(move.name)
                            Text("\(move.type) · \(move.power)").foregroundStyle(.tertiary)
                            Spacer()
                            Text("Lv\(move.level)").foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless).font(.caption)
                    .disabled(!isOn && selected.count >= BattleEntry.maxMoves)
                }
            } else if unavailable.contains(key) {
                Text(l.battleEntryMovesUnavailable).font(.caption2).foregroundStyle(.orange)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 32).padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: key) {
            guard learnable[key] == nil else { return }
            unavailable.remove(key)
            if let moves = await uploader.learnableMoves(pokemonID: member.pokemonID, level: member.level) {
                learnable[key] = moves
            } else {
                unavailable.insert(key)
            }
        }
    }

    private func label(_ candidate: BattleCandidate) -> String {
        let name = candidate.dexEntry.map(companion.dexEntryName) ?? companion.displayName
        return "\(name) Lv\(candidate.member.level)\(candidate.member.shiny ? " ✨" : "")"
    }

    private func change(_ edit: () -> Void) {
        edit()
        Task { await uploader.tick() }
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10) { content() }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(minHeight: 38)
    }
}
