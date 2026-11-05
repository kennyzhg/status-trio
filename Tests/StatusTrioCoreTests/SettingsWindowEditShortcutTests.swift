import AppKit
import XCTest
@testable import StatusTrioCore

/// The Settings window handles editing shortcuts itself, because the app has
/// no Edit menu (and no main menu at all as a menu-bar accessory).
@MainActor
final class SettingsWindowEditShortcutTests: XCTestCase {
    func testCommandShortcutsMapToTheStandardEditActions() {
        XCTAssertEqual(SettingsWindow.editAction(characters: "v", modifiers: .command), #selector(NSText.paste(_:)))
        XCTAssertEqual(SettingsWindow.editAction(characters: "c", modifiers: .command), #selector(NSText.copy(_:)))
        XCTAssertEqual(SettingsWindow.editAction(characters: "x", modifiers: .command), #selector(NSText.cut(_:)))
        XCTAssertEqual(SettingsWindow.editAction(characters: "a", modifiers: .command), #selector(NSText.selectAll(_:)))
        XCTAssertEqual(SettingsWindow.editAction(characters: "z", modifiers: .command), Selector(("undo:")))
        XCTAssertEqual(SettingsWindow.editAction(characters: "z", modifiers: [.command, .shift]), Selector(("redo:")))
    }

    func testOtherCombinationsAreLeftAlone() {
        XCTAssertNil(SettingsWindow.editAction(characters: "v", modifiers: []))
        XCTAssertNil(SettingsWindow.editAction(characters: "v", modifiers: [.command, .option]))
        XCTAssertNil(SettingsWindow.editAction(characters: "w", modifiers: .command))
        XCTAssertNil(SettingsWindow.editAction(characters: ",", modifiers: .command))
    }

    func testEventsAreReadIgnoringCapsLock() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command, .capsLock],
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "V", charactersIgnoringModifiers: "V", isARepeat: false, keyCode: 9
        ))
        XCTAssertEqual(SettingsWindow.editAction(for: event), #selector(NSText.paste(_:)))
    }
}
