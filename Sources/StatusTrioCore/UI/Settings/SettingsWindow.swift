import AppKit

/// The Settings window, with the standard text-editing shortcuts.
///
/// ⌘X/⌘C/⌘V/⌘A/⌘Z normally reach a text field through the Edit menu's key
/// equivalents. The app has no Edit menu, and while it runs as a menu-bar
/// accessory it has no main menu at all, so without this a pasted API key or
/// host would have to be typed by hand.
final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        guard let action = Self.editAction(for: event) else { return false }
        return NSApp.sendAction(action, to: nil, from: self)
    }

    /// The responder-chain action for an editing shortcut, or `nil`.
    static func editAction(for event: NSEvent) -> Selector? {
        guard event.type == .keyDown,
              let characters = event.charactersIgnoringModifiers?.lowercased() else {
            return nil
        }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        return editAction(characters: characters, modifiers: modifiers)
    }

    static func editAction(characters: String, modifiers: NSEvent.ModifierFlags) -> Selector? {
        switch (characters, modifiers) {
        case ("x", .command): #selector(NSText.cut(_:))
        case ("c", .command): #selector(NSText.copy(_:))
        case ("v", .command): #selector(NSText.paste(_:))
        case ("a", .command): #selector(NSText.selectAll(_:))
        case ("z", .command): Selector(("undo:"))
        case ("z", [.command, .shift]): Selector(("redo:"))
        default: nil
        }
    }
}
