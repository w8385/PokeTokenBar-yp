import AppKit
import Carbon.HIToolbox

/// ⌘X/⌘C/⌘V/⌘A/⌘Z/⌘⇧Z for every text field. A menu-bar accessory app has no Edit menu,
/// and AppKit only turns these keys into editing actions through that menu.
enum EditShortcuts {
    @MainActor static func install() {
        _ = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let action = action(characters: event.charactersIgnoringModifiers,
                                      keyCode: Int(event.keyCode), modifiers: event.modifierFlags),
                  NSApp.sendAction(action, to: nil, from: nil)
            else { return event }
            return nil
        }
    }

    static func action(characters: String?, keyCode: Int, modifiers: NSEvent.ModifierFlags) -> Selector? {
        let flags = modifiers.intersection([.command, .shift, .option, .control])
        switch (flags, key(characters: characters, keyCode: keyCode)) {
        case (.command, "x"): return #selector(NSText.cut(_:))
        case (.command, "c"): return #selector(NSText.copy(_:))
        case (.command, "v"): return #selector(NSText.paste(_:))
        case (.command, "a"): return #selector(NSResponder.selectAll(_:))
        case (.command, "z"): return Selector(("undo:"))
        case ([.command, .shift], "z"): return Selector(("redo:"))
        default: return nil
        }
    }

    /// Non-Latin layouts can report a non-ASCII character, so the physical key decides there.
    private static func key(characters: String?, keyCode: Int) -> String? {
        if let lower = characters?.lowercased(), lower.count == 1, lower.first?.isASCII == true { return lower }
        return [kVK_ANSI_X: "x", kVK_ANSI_C: "c", kVK_ANSI_V: "v", kVK_ANSI_A: "a", kVK_ANSI_Z: "z"][keyCode]
    }
}
