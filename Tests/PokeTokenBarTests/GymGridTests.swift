import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct ColumnWidths: PreferenceKey {
    static let defaultValue: [CGFloat] = []
    static func reduce(value: inout [CGFloat], nextValue: () -> [CGFloat]) { value += nextValue() }
}

@MainActor
private final class WidthBox {
    var values: [CGFloat] = []
}

/// The Battle sub-tab's eight gyms as a two-column grid.
@MainActor
final class GymGridTests: XCTestCase {
    private let cardWidth = PopoverMetrics.scrollContentWidth
    private var columnWidth: CGFloat { (cardWidth - Spacing.lg * 2 - Spacing.md) / 2 }

    /// Kanto with each gym's name and types replaced; the longest real names are "8. Kerrigan" and "7. ウィンズロー".
    private func gyms(names: [(String, String)], types: [[String]]) throws -> [GymOpponent] {
        var region = GymFixtures.region("kanto")
        region["gyms"] = names.indices.map { index in
            var gym = GymFixtures.opponent("kanto-\(index + 1)", kind: "gym", index: 8, types: types[index % types.count],
                                           trainer: names[index])
            var trainer = gym["trainer"] as? [String: Any] ?? [:]
            trainer["name"] = ["ko": names[index].0, "en": names[index].1, "ja": "ウィンズロー"]
            gym["trainer"] = trainer
            return gym
        }
        let data = try JSONSerialization.data(withJSONObject: ["ok": true, "regions": [region]])
        return try XCTUnwrap(GymCatalog.decode(data).region("kanto")).gyms
    }

    private static func card(_ gym: GymOpponent, _ language: AppLanguage, earned: Bool = true, fighting: Bool = false) -> some View {
        GymOpponentCard(opponent: gym, language: language, l: L(language), earned: earned, fighting: fighting,
                        disabled: false) {}
            .environment(\.locale, language.displayLocale)
    }

    func testTheEightGymsLayOutAsFourRowsOfTwoInIndexOrder() throws {
        let kanto = try XCTUnwrap(GymFixtures.catalog().region("kanto"))
        XCTAssertEqual(GymGrid<EmptyView>.rows(kanto.gyms).map { $0.map(\.index) }, [[1, 2], [3, 4], [5, 6], [7, 8]])
    }

    func testTheGridIsMuchShorterThanOneColumnOfTheSameGyms() throws {
        let kanto = try XCTUnwrap(GymFixtures.catalog().region("kanto"))
        for language in [AppLanguage.ko, .en, .de] {
            let grid = LayoutMeasure.size(GymGrid(gyms: kanto.gyms) { Self.card($0, language) }, width: cardWidth)
            let column = LayoutMeasure.size(
                VStack(alignment: .leading, spacing: Spacing.lg) { ForEach(kanto.gyms) { Self.card($0, language) } }
                    .padding(.horizontal, Spacing.lg).padding(.vertical, Spacing.md),
                width: cardWidth)
            XCTAssertLessThan(grid.height, column.height * 0.6, "\(language.rawValue): grid \(grid.height)pt, one column \(column.height)pt")
        }
    }

    func testBothColumnsGetTheSameWidth() async throws {
        let kanto = try XCTUnwrap(GymFixtures.catalog().region("kanto"))
        let widths = WidthBox()
        let grid = GymGrid(gyms: kanto.gyms) { gym in
            Self.card(gym, .de, earned: gym.index.isMultiple(of: 2))
                .background(GeometryReader { Color.clear.preference(key: ColumnWidths.self, value: [$0.size.width]) })
        }
        .onPreferenceChange(ColumnWidths.self) { value in MainActor.assumeIsolated { widths.values = value } }
        .frame(width: cardWidth)
        let host = OffscreenRender.host(grid, size: CGSize(width: cardWidth, height: 600), appearance: .aqua)
        try await OffscreenRender.settle(host) { widths.values.count == 8 }
        for width in widths.values { XCTAssertEqual(width, columnWidth, accuracy: 0.5, "\(widths.values)") }
    }

    func testNoCardOverflowsItsColumnForAnyTypeOrButtonStateInEveryLanguage() throws {
        let names = [("관장관장", "Kerrigan")]
        let single = try gyms(names: Array(repeating: names[0], count: PokemonType.allCases.count),
                              types: PokemonType.allCases.map { [$0.rawValue] })
        for language in AppLanguage.allCases {
            for gym in single {
                for (earned, fighting) in [(false, false), (true, false), (false, true)] {
                    let ideal = LayoutMeasure.size(Self.card(gym, language, earned: earned, fighting: fighting).fixedSize())
                    XCTAssertLessThanOrEqual(ideal.width, columnWidth + 0.5,
                                             "\(language.rawValue) \(gym.types) earned=\(earned) fighting=\(fighting)")
                }
            }
        }
    }

    /// Every language with the longest names, a dual-type gym, and one gym of each button state.
    ///
    ///     PTB_GYM_GRID_SHOT_DIR=/tmp/shots swift test --filter GymGridTests
    func testCaptureTheGridInEveryLanguage() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_GYM_GRID_SHOT_DIR"] else {
            throw XCTSkip("Set PTB_GYM_GRID_SHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let types = [["electric", "fighting"], ["water"], ["psychic"], ["fairy"], ["ground"], ["steel"], ["fire"], ["dragon"]]
        let stress = try gyms(names: Array(repeating: ("관장관장", "Kerrigan"), count: 8), types: types)
        for language in AppLanguage.allCases {
            let grid = GymGrid(gyms: stress) { gym in
                GymOpponentCard(opponent: gym, language: language, l: L(language), earned: gym.id.hasSuffix("-1"),
                                fighting: gym.id.hasSuffix("-2"), disabled: gym.id.hasSuffix("-2")) {}
            }
            .frame(width: cardWidth).ptbCard()
            .padding(Spacing.md).background(Color.white)
            .environment(\.colorScheme, .light).environment(\.locale, language.displayLocale)
            _ = try await OffscreenRender.capture(grid, size: CGSize(width: cardWidth + Spacing.md * 2, height: 420),
                                                  appearance: .aqua,
                                                  to: directory.appendingPathComponent("gym-grid-\(language.rawValue).png"))
        }
    }

    func testADualTypeGymStacksItsChipsInsteadOfOverflowingInEveryLanguage() throws {
        let dual = try XCTUnwrap(gyms(names: [("관장관장", "Kerrigan")], types: [["electric", "fighting"]]).first)
        for language in AppLanguage.allCases {
            let offered = LayoutMeasure.size(Self.card(dual, language), width: columnWidth)
            XCTAssertLessThanOrEqual(offered.width, columnWidth + 0.5, language.rawValue)
        }
    }
}
