import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct PikachuOnly: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 25, tree: EvoNode(speciesID: 25, children: []), rarity: .common,
                names: [25: ["en": "Pikachu", "ko": "피카츄", "ja": "ピカチュウ"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// The README "small reactions" board: four frozen floating-pet states drawn by the production `FloatingPetView`.
/// Writes `screenshot-pet-interactions{,-ko,-ja}.png` into `PTB_README_SHOT_DIR`; skipped when it is not set.
@MainActor
final class PetInteractionsBoardTests: XCTestCase {
    enum Cell: CaseIterable { case prayer, stroke, sulk, waiting }

    struct Copy {
        let title: String
        let subtitle: String
        let cards: [(title: String, caption: String)]
        let footer: String
    }

    static let boardSize = CGSize(width: 720, height: 828)

    static func copy(_ language: AppLanguage) -> Copy {
        switch language {
        case .ko:
            Copy(title: "데스크톱 위의 작은 반응", subtitle: "기도 · 쓰다듬기 · 삐짐 · 에이전트 상태",
                 cards: [("알에게 기도", "클릭하면 기도 횟수를 기록해요"), ("쓰다듬기", "좌우로 쓰다듬으면 하트가 떠요"),
                         ("등을 돌린 친구", "사용량 없이 3시간이 지나면 삐져요"), ("에이전트 대기", "도구가 보낸 상태를 말풍선으로")],
                 footer: "서로 다른 샘플 상태 · 실제 UI 컴포넌트의 정지 렌더")
        case .ja:
            Copy(title: "デスクトップの小さな反応", subtitle: "お祈り・なでる・すねる・エージェント状態",
                 cards: [("タマゴにお祈り", "クリックでお祈り回数を記録"), ("なでる", "左右になでるとハートが浮かびます"),
                         ("背中を向ける仲間", "使用量がないまま3時間ですねます"), ("エージェント待機", "ツールから届いた状態を吹き出しに")],
                 footer: "別々のサンプル状態・実際の UI 部品の静止レンダー")
        default:
            Copy(title: "Small reactions on your desktop", subtitle: "Prayer · stroking · sulking · agent status",
                 cards: [("Pray over an egg", "A click records a prayer"),
                         ("Stroke your companion", "Move side to side for a heart"),
                         ("A companion turns away", "After 3 hours without token usage"),
                         ("An agent is waiting", "A status sent by your coding tool")],
                 footer: "Separate sample states · frozen native UI component renders")
        }
    }

    func testDrawPetInteractionsBoard() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_README_SHOT_DIR"] else {
            throw XCTSkip("PTB_README_SHOT_DIR not set")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("pet-board-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let sprites = SpriteStore(directory: scratch.appendingPathComponent("sprites"))
        let front = await sprites.data(speciesID: 25, animated: false)
        let back = await sprites.data(speciesID: 25, animated: false, back: true)
        let egg = await SpriteLoader.eggImage()
        XCTAssertNotNil(front); XCTAssertNotNil(back); XCTAssertNotNil(egg)

        for (language, suffix) in [(AppLanguage.en, ""), (.ko, "-ko"), (.ja, "-ja")] {
            var cells: [AnyView] = []
            for cell in Cell.allCases {
                cells.append(try await pet(cell, language: language, sprites: sprites, scratch: scratch))
            }
            let board = Board(copy: Self.copy(language), cells: cells)
                .frame(width: Self.boardSize.width, height: Self.boardSize.height, alignment: .topLeading)
                .background(Color(white: 0.106))
                .environment(\.colorScheme, .dark)
                .environment(\.locale, language.displayLocale)
            let host = OffscreenRender.host(board, size: Self.boardSize, appearance: .darkAqua)
            try await OffscreenRender.settle(host)
            try OffscreenRender.writePNG(of: host,
                                         to: directory.appendingPathComponent("screenshot-pet-interactions\(suffix).png"))
        }
    }

    private func pet(_ cell: Cell, language: AppLanguage, sprites: SpriteStore, scratch: URL) async throws -> AnyView {
        let suite = "pet-board-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        var state = CompanionState()
        state.language = language
        state.installBaselineSet = true
        if cell == .prayer {
            state.eggUsage = 1_000_000
            state.eggPrayers = PrayerRecord(count: 1)
        } else {
            state.active = MonState(baseID: 25, pathIDs: [25], plannedPathIDs: [25], stageIndex: 0, usedAtStage: 0,
                                    rarity: .common, totalForms: 1,
                                    profile: PokemonProfile.generate(seed: 5, instanceID: "board"))
        }
        let file = scratch.appendingPathComponent("state-\(UUID()).json")
        try JSONEncoder().encode(state).write(to: file)
        let companion = CompanionStore(provider: PikachuOnly(), fileURL: file, defaults: defaults)
        try await waitUntil("the board's subject") {
            companion.representativeSubject.speciesID == (cell == .prayer ? nil : 25)
        }
        companion.alwaysFacesBack = cell == .sulk
        let usage = UsageStore(providers: [], statusProvider: NoProviderStatus(), autoRefresh: false, defaults: defaults)
        let crowd = PetCrowd(settle: .seconds(120))
        crowd.configure(order: [0], motionAllowed: true, active: false)
        let agent = FloatingPetAgentModel()
        switch cell {
        case .prayer: crowd.touched(slot: 0, with: .prayer)
        case .stroke: crowd.touched(slot: 0)
        case .sulk: break
        case .waiting:
            agent.summary.waiting = .init(label: nil, message: nil)
            crowd.speechOnMain = true
        }
        let speaking = cell == .waiting
        let panel = FloatingPetController.panelSize(petSize: CGFloat(usage.floatingPetSize), showingBubble: speaking)
        return AnyView(FloatingPetView(animated: false, agent: agent, spriteStore: sprites, crowd: crowd)
            .environment(usage).environment(companion)
            .frame(width: panel.width, height: panel.height))
    }
}

private struct Board: View {
    let copy: PetInteractionsBoardTests.Copy
    let cells: [AnyView]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(copy.title).font(.system(size: 25, weight: .bold))
            Text(copy.subtitle).font(.system(size: 14.5)).foregroundStyle(.secondary).padding(.top, 9)
            Grid(horizontalSpacing: 15, verticalSpacing: 19) {
                GridRow { card(0); card(1) }
                GridRow { card(2); card(3) }
            }
            .padding(.top, 20)
            Text(copy.footer).font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 20)
            Spacer(minLength: 0)
        }
        .padding(.leading, 29)
        .padding(.top, 29)
    }

    private func card(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(copy.cards[index].title).font(.system(size: 16, weight: .semibold))
            Text(copy.cards[index].caption).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            cells[index].frame(maxWidth: .infinity)
        }
        .padding(16)
        .padding(.top, 2)
        .padding(.bottom, 44)
        .frame(width: 324, height: 320, alignment: .topLeading)
        .background(Color(white: 0.165), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(white: 0.21), lineWidth: 1))
    }
}
