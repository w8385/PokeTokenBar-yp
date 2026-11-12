import AppKit
import Carbon.HIToolbox
import XCTest
@testable import PokeTokenBar

final class EditShortcutsTests: XCTestCase {
    func testCommandKeysMapToTheEditActions() {
        let cases: [(String, Int, NSEvent.ModifierFlags, String)] = [
            ("x", kVK_ANSI_X, .command, "cut:"),
            ("c", kVK_ANSI_C, .command, "copy:"),
            ("v", kVK_ANSI_V, .command, "paste:"),
            ("a", kVK_ANSI_A, .command, "selectAll:"),
            ("z", kVK_ANSI_Z, .command, "undo:"),
            ("Z", kVK_ANSI_Z, [.command, .shift], "redo:"),
            ("v", kVK_ANSI_V, [.command, .capsLock], "paste:"),
        ]
        for (characters, keyCode, modifiers, expected) in cases {
            let action = EditShortcuts.action(characters: characters, keyCode: keyCode, modifiers: modifiers)
            XCTAssertEqual(action.map(NSStringFromSelector), expected, characters)
        }
    }

    func testHangulInputUsesThePhysicalKey() {
        let action = EditShortcuts.action(characters: "ㅍ", keyCode: kVK_ANSI_V, modifiers: .command)
        XCTAssertEqual(action.map(NSStringFromSelector), "paste:")
    }

    func testOtherKeysPassThrough() {
        XCTAssertNil(EditShortcuts.action(characters: "v", keyCode: kVK_ANSI_V, modifiers: []))
        XCTAssertNil(EditShortcuts.action(characters: "v", keyCode: kVK_ANSI_V, modifiers: [.command, .option]))
        XCTAssertNil(EditShortcuts.action(characters: "w", keyCode: kVK_ANSI_W, modifiers: .command))
        XCTAssertNil(EditShortcuts.action(characters: ",", keyCode: kVK_ANSI_Comma, modifiers: .command))
    }

    @MainActor
    func testTheActionsReachATextField() {
        let editor = NSTextView()
        for key in ["x", "c", "v", "a"] {
            let action = EditShortcuts.action(characters: key, keyCode: 0, modifiers: .command)
            XCTAssertTrue(action.map(editor.responds(to:)) ?? false, key)
        }
    }
}
