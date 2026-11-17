import XCTest
@testable import PokeTokenBar

final class RarityNameTests: XCTestCase {
    private let names: [AppLanguage: [String]] = [
        .ko: ["기본", "희귀", "고급", "전설"],
        .en: ["Normal", "Rare", "Epic", "Legendary"],
        .ja: ["ノーマル", "レア", "エピック", "伝説"],
        .es: ["Normal", "Raro", "Épico", "Legendario"],
        .fr: ["Normal", "Rare", "Épique", "Légendaire"],
        .pt: ["Normal", "Raro", "Épico", "Lendário"],
        .de: ["Normal", "Selten", "Episch", "Legendär"],
        .ru: ["Обычный", "Редкий", "Эпический", "Легендарный"],
    ]

    func testEachLanguageNamesTheFourTiersFromLowToHigh() {
        XCTAssertEqual(Set(names.keys), Set(AppLanguage.allCases))
        for (language, expected) in names {
            let l = L(language)
            XCTAssertEqual([Rarity.common, .uncommon, .rare, .legendary].map(l.rarityLabel), expected, "\(language)")
        }
    }

    func testGradedEggsCarryTheirTierName() {
        XCTAssertEqual(L(.ko).eggName(.uncommon), "희귀 알")
        XCTAssertEqual(L(.ko).eggName(.rare), "고급 알")
        XCTAssertEqual(L(.en).eggName(.uncommon), "Rare Egg")
        XCTAssertEqual(L(.en).eggName(.rare), "Epic Egg")
        XCTAssertEqual(L(.ja).eggName(.rare), "エピックのタマゴ")
    }

    func testReadmesUseTheNewEggNames() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        func readme(_ name: String) throws -> String {
            try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
        }
        XCTAssertFalse(try readme("README.md").contains("Uncommon"))
        XCTAssertFalse(try readme("README.ja.md").contains("アンコモン"))
        let ko = try readme("README.ko.md")
        let rare = try XCTUnwrap(ko.range(of: "희귀 알")), epic = try XCTUnwrap(ko.range(of: "고급 알"))
        XCTAssertLessThan(rare.lowerBound, epic.lowerBound, "the shop lists the lower tier first")
    }
}
