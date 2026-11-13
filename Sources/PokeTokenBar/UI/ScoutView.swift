import SwiftUI

/// 상점의 스카우트 구역 — 지역마다·전국 티켓 한 줄. 같은 가격. 인라인 확인(.sheet/.alert 금지, ShopView 주석과 같은 이유).
@MainActor
struct ShopScoutSection: View {
    let store: CompanionStore
    @State private var confirming: ScoutPool?

    var body: some View {
        let l = store.l
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(l.scoutSection).font(.callout.weight(.semibold))
                Text(l.scoutShopHint).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(ScoutPool.all, id: \.self) { pool in
                row(pool, l)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func row(_ pool: ScoutPool, _ l: L) -> some View {
        HStack(spacing: 8) {
            ScoutTicketIcon(size: 22)
            if confirming == pool {
                Text(l.buyConfirm(l.scoutTicketName(pool)))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                Spacer(minLength: 4)
                Button(l.buy) { buy(pool) }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                Button(l.cancel) { confirming = nil }
                    .buttonStyle(.borderless).controlSize(.small)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(l.scoutTicketName(pool)).font(.caption.weight(.semibold))
                        let owned = store.scoutTicketCount(pool)
                        if owned > 0 {
                            Text(l.ownedCount(owned)).font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    Text("\(l.shopPriceLabel) \(TokenFormatter.compact(store.scoutPrice))")
                        .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                }
                Spacer(minLength: 4)
                if store.canBuyScoutTicket {
                    Button(l.buy) { confirming = pool }
                        .buttonStyle(.bordered).controlSize(.small)
                } else {
                    Text(l.notEnoughTokens).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func buy(_ pool: ScoutPool) {
        confirming = nil
        store.buyScoutTicket(pool)
    }
}

struct ScoutTicketIcon: View {
    let size: CGFloat
    var body: some View {
        Text("🎟️").font(.system(size: size * 0.8))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// 가방의 티켓 카드 — 후보 보기로 스카우트 화면을 연다.
@MainActor
struct ScoutTicketCard: View {
    let store: CompanionStore
    let pool: ScoutPool
    let count: Int
    let onOpen: () -> Void

    var body: some View {
        let l = store.l
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                ScoutTicketIcon(size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(l.scoutTicketName(pool)).font(.callout.weight(.semibold))
                        Text("×\(count)").font(.caption.weight(.bold))
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                    Text(l.scoutDescription(pool))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Spacer()
                Button(l.scoutViewPicks, action: onOpen)
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// 스카우트 화면 — 후보 10종 중 하나를 골라 그 종의 알을 받는다. 가방 안에서 내용을 갈아끼운다(시트 아님).
/// 후보는 store 가 영속하므로 닫았다 다시 열어도 같다. 티켓은 고를 때만 쓴다.
@MainActor
struct ScoutPickerView: View {
    let store: CompanionStore
    let pool: ScoutPool
    let onPicked: () -> Void
    let onBack: () -> Void

    @State private var ids: [Int]?
    @State private var failed = false
    @State private var stage: Stage = .idle
    private enum Stage: Equatable { case idle, confirm(Int), preciousConfirm(Int) }

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

    var body: some View {
        let l = store.l
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button(action: onBack) { Label(l.back, systemImage: "chevron.left") }
                    .buttonStyle(.borderless)
                Spacer()
                Text(l.scoutTicketName(pool)).font(.callout.weight(.semibold))
            }
            Text(store.canPickScout ? l.scoutPickHint : l.scoutPickLocked)
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            content(l)
            if case .idle = stage {} else { confirmBar(l) }
        }
        .task { await load() }
        .onChange(of: store.scoutTicketCount(pool)) { _, count in
            if count == 0 { onBack() }
        }
    }

    @ViewBuilder
    private func content(_ l: L) -> some View {
        if failed {
            VStack(spacing: 8) {
                Spacer()
                Text(l.scoutLoadFailed).font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(l.retry) { Task { await load() } }
                    .buttonStyle(.bordered).controlSize(.small)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let ids, store.speciesIndex != nil {
            ScrollView {
                LazyVGrid(columns: Self.columns, spacing: 4) {
                    ForEach(store.scoutPicks(ids)) { pick in
                        VStack(spacing: 2) {
                            DexSpeciesCell(store: store, species: pick.species,
                                           isSelected: selectedID == pick.id, isRepresentative: false,
                                           formCount: nil, isScoutPick: true) {
                                if store.canPickScout { stage = .confirm(pick.id) }
                            }
                            TypeBadges(types: pick.types, language: store.language)
                        }
                    }
                }
                .reservesScrollerLane()
            }
        } else {
            VStack(spacing: 8) {
                Spacer()
                ProgressView().controlSize(.small)
                Text(l.scoutLoading).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var selectedID: Int? {
        switch stage {
        case .idle: return nil
        case .confirm(let id), .preciousConfirm(let id): return id
        }
    }

    @ViewBuilder
    private func confirmBar(_ l: L) -> some View {
        if let id = selectedID, let pick = store.scoutPicks(ids ?? []).first(where: { $0.id == id }) {
            HStack(spacing: 8) {
                if case .preciousConfirm = stage {
                    Text(store.rarity == .legendary ? l.freshEggLegendaryWarning : l.freshEggShinyWarning)
                        .font(.caption2.weight(.semibold)).foregroundStyle(.orange).lineLimit(2)
                } else {
                    Text(l.scoutPickConfirm(store.displayName, pick.species.name))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 4)
                Button(l.scoutPick) {
                    if case .confirm = stage, store.isHighValueCompanion { stage = .preciousConfirm(id) }
                    else { commit(id) }
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
                Button(l.cancel) { stage = .idle }
                    .buttonStyle(.borderless).controlSize(.small)
            }
            .padding(8)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func commit(_ id: Int) {
        stage = .idle
        if store.pickScout(pool, speciesID: id) { onPicked() }
    }

    private func load() async {
        failed = false
        await store.loadSpeciesIndexIfNeeded()
        let drawn = await store.drawScout(pool)
        if drawn == nil || store.speciesIndex == nil { failed = true }
        ids = drawn
    }
}
