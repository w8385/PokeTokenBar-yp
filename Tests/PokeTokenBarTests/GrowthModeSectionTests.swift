import XCTest
import SwiftUI
@testable import PokeTokenBar

private struct GrowthModeProvider: PokeProviding {
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: []), rarity: .common, names: [:])
    }
}

@MainActor
final class GrowthModeSectionTests: XCTestCase {
    private func store() throws -> CompanionStore {
        var state = CompanionState()
        state.installBaselineSet = true
        state.growthMode = .token
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("growth-mode-\(UUID()).json")
        try JSONEncoder().encode(state).write(to: url)
        return CompanionStore(provider: GrowthModeProvider(), fileURL: url, dittoDisguiseRollingEnabled: false,
                              defaults: try XCTUnwrap(UserDefaults(suiteName: "growth-mode-\(UUID())")))
    }

    func testTheDraftDoesNotApplyUntilSave() throws {
        let s = try store()
        let since = s.state.tokenModeSince
        var draft = GrowthModeDraft(companion: s)
        draft.mode = .time
        XCTAssertTrue(draft.differs(from: s))
        XCTAssertEqual(s.growthMode, .token)
        XCTAssertEqual(s.state.tokenModeSince, since)
        XCTAssertFalse(GrowthModeDraft(companion: s).differs(from: s), "closing Settings discards the draft")
        draft.save(to: s)
        XCTAssertEqual(s.growthMode, .time)
        XCTAssertFalse(draft.differs(from: s))
    }

    func testTheSaveButtonAppearsOnlyForAnEditedDraftInEveryLanguage() throws {
        let s = try store()
        var draft = GrowthModeDraft(companion: s)
        draft.mode = .time
        for language in AppLanguage.allCases {
            s.setLanguage(language)
            let saved = LayoutMeasure.size(GrowthModeSection(companion: s), width: 300).height
            let edited = LayoutMeasure.size(GrowthModeSection(companion: s, draft: draft), width: 300).height
            XCTAssertGreaterThan(edited, saved + 20, language.rawValue)
        }
    }

    func testTheDifficultyCardIsGone() {
        XCTAssertEqual(SettingsTab.companion.sections, [.growthMode, .floatingPet])
    }
}
