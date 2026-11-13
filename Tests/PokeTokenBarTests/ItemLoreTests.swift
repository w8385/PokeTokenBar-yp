import Foundation
import XCTest
@testable import PokeTokenBar

final class ItemLoreTests: XCTestCase {
    private let officialLanguages: [AppLanguage] = [.ko, .en, .ja, .es, .fr, .de]

    func testEveryItemHasADescriptionInEveryLanguage() {
        for lang in AppLanguage.allCases {
            let l = L(lang)
            for kind in ItemKind.allCases {
                XCTAssertFalse(l.itemDescription(kind).isEmpty, "\(kind) \(lang)")
                XCTAssertFalse(l.itemName(kind).isEmpty, "\(kind) \(lang)")
            }
            for stone in MegaStone.all {
                XCTAssertFalse(l.megaStoneDescription(stone).isEmpty, "\(stone.slug) \(lang)")
            }
        }
    }

    func testDescriptionsAreOneLineWithoutGameLineBreaks() {
        for entry in ItemLoreTable.entries.values {
            for text in entry.texts.values {
                XCTAssertFalse(text.contains("\n") || text.contains("\u{c}") || text.contains("\u{ad}"), text)
            }
        }
    }

    func testAppOriginalItemsAreFlaggedAndOfficialOnesAreNot() {
        XCTAssertTrue(ItemLore.isAppOriginal(ItemKind.mint.loreSlug))
        for kind in ItemKind.allCases where kind != .mint {
            XCTAssertFalse(ItemLore.isAppOriginal(kind.loreSlug), "\(kind)")
        }
        XCTAssertFalse(ItemLore.isAppOriginal("venusaurite"), "a Gen 6 Mega Stone has official text")
        let flagged = ItemLoreTable.entries.filter(\.value.appOriginal).keys
        let known = Set(MegaStone.all.map(\.slug)).union([ItemKind.mint.loreSlug])
        XCTAssertTrue(Set(flagged).isSubset(of: known), "an official item was flagged app-original")
    }

    func testLanguagesPokeAPILacksFallBackToEnglish() {
        let slug = ItemKind.rareCandy.loreSlug
        XCTAssertFalse(ItemLore.text(slug, in: .en).isEmpty)
        XCTAssertEqual(ItemLore.text(slug, in: .pt), ItemLore.text(slug, in: .en))
        XCTAssertEqual(ItemLore.text(slug, in: .ru), ItemLore.text(slug, in: .en))
        XCTAssertNotEqual(ItemLore.text(slug, in: .ko), ItemLore.text(slug, in: .en))
        XCTAssertNil(ItemLoreTable.entries[slug]?.texts["pt"])
        XCTAssertNil(ItemLoreTable.entries[slug]?.texts["ru"])
    }

    func testRareCandyKoreanIsTheOfficialText() {
        XCTAssertEqual(L(.ko).itemDescription(.rareCandy),
                       "에너지가 가득한 사탕. 먹이면 포켓몬 1마리의 레벨이 1만큼 올라간다.")
    }

    func testItemNamesMatchTheOfficialNames() {
        for lang in officialLanguages {
            let l = L(lang)
            for kind in ItemKind.allCases where kind != .mint {
                XCTAssertEqual(l.itemName(kind), ItemLore.officialName(kind.loreSlug, in: lang), "\(kind) \(lang)")
            }
            for stone in MegaStone.all {
                XCTAssertEqual(l.megaStoneName(stone), ItemLore.officialName(stone.loreSlug, in: lang), "\(stone.slug) \(lang)")
            }
        }
    }

    func testAppNoteStaysOnOneLineAndAppOriginalItemsHaveNone() {
        for lang in AppLanguage.allCases {
            let l = L(lang)
            XCTAssertEqual(l.itemAppNote(.mint), "", "\(lang)")
            for kind in ItemKind.allCases where kind != .mint {
                let note = l.itemAppNote(kind)
                XCTAssertFalse(note.isEmpty, "\(kind) \(lang)")
                XCTAssertFalse(note.contains("\n"), note)
            }
        }
    }
}
