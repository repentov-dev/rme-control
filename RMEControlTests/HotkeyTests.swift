import AppKit
import XCTest
@testable import RME_Control

@MainActor
final class HotkeyTests: XCTestCase {
    /// Все комбинации включены сразу после установки.
    func testDefaultsEnableEveryShortcut() {
        let t = TestStorage()
        let settings = AppSettings(storage: t.storage)

        let mono = settings.hotkey(for: .mono)
        XCTAssertTrue(mono.isEnabled)
        XCTAssertEqual(mono.keyCode, 46)
        XCTAssertEqual(mono.modifierFlags, [.command, .shift])
        XCTAssertEqual(mono.displayString, "⇧⌘M")

        let expected: [HotkeyAction: String] = [
            .volumeUp: "F12",
            .volumeDown: "F11",
            .mute: "F10",
            .nextOutput: "⌥↓",
            .previousOutput: "⌥↑"
        ]
        for (action, display) in expected {
            XCTAssertTrue(settings.hotkey(for: action).isAssigned)
            XCTAssertTrue(settings.hotkey(for: action).isEnabled, "\(action) must be enabled by default")
            XCTAssertEqual(settings.hotkey(for: action).displayString, display)
        }
    }

    func testAssignedHotkeyIsPersisted() {
        let t = TestStorage()
        let settings = AppSettings(storage: t.storage)
        settings.setHotkey(
            Hotkey(keyCode: 1, modifiers: [.command, .option], label: "S", isEnabled: true),
            for: .mono
        )

        XCTAssertNotNil(t.defaults.data(forKey: "hotkeys"))
        let reloaded = AppSettings(storage: t.storage)
        XCTAssertEqual(reloaded.hotkey(for: .mono).keyCode, 1)
        XCTAssertTrue(reloaded.hotkey(for: .mono).isEnabled)
    }

    func testClearedHotkeyStaysUnassigned() {
        let t = TestStorage()
        let settings = AppSettings(storage: t.storage)
        settings.setHotkey(Hotkey(keyCode: nil, modifiers: [], label: "", isEnabled: false), for: .mono)

        let reloaded = AppSettings(storage: t.storage)
        XCTAssertNil(reloaded.hotkey(for: .mono).keyCode)
        XCTAssertFalse(reloaded.hotkey(for: .mono).isEnabled)
    }

    func testResetRestoresDefaults() {
        let t = TestStorage()
        let settings = AppSettings(storage: t.storage)
        settings.setHotkey(Hotkey(keyCode: 1, modifiers: [], label: "S", isEnabled: true), for: .volumeUp)
        settings.setHotkey(Hotkey(keyCode: nil, modifiers: [], label: "", isEnabled: false), for: .mono)

        settings.resetHotkeys()

        XCTAssertEqual(settings.hotkey(for: .mono).keyCode, 46)
        XCTAssertTrue(settings.hotkey(for: .mono).isEnabled)
        XCTAssertEqual(settings.hotkey(for: .volumeUp).keyCode, 111)
        XCTAssertTrue(settings.hotkey(for: .volumeUp).isEnabled)
    }

    /// Пользователи старых версий включали F10–F12 и Option + ↑/↓ отдельными
    /// галочками — эти настройки должны стать включёнными комбинациями.
    func testLegacyKeySettingsBecomeHotkeys() {
        let t = TestStorage()
        t.defaults.set(true, forKey: "useFunctionKeys")
        t.defaults.set(true, forKey: "switchOutputWithArrowKeys")

        let settings = AppSettings(storage: t.storage)

        XCTAssertTrue(settings.hotkey(for: .volumeUp).isEnabled)
        XCTAssertTrue(settings.hotkey(for: .volumeDown).isEnabled)
        XCTAssertTrue(settings.hotkey(for: .mute).isEnabled)
        XCTAssertTrue(settings.hotkey(for: .nextOutput).isEnabled)
        XCTAssertTrue(settings.hotkey(for: .previousOutput).isEnabled)
    }

    func testHotkeyMatchingIgnoresUnrelatedFlags() {
        let hotkey = Hotkey(keyCode: 46, modifiers: [.command, .shift], label: "M", isEnabled: true)

        XCTAssertTrue(hotkey.matches(keyCode: 46, modifiers: [.command, .shift]))
        XCTAssertTrue(hotkey.matches(keyCode: 46, modifiers: [.command, .shift, .capsLock, .function]))
        XCTAssertFalse(hotkey.matches(keyCode: 46, modifiers: [.command]))
        XCTAssertFalse(hotkey.matches(keyCode: 45, modifiers: [.command, .shift]))

        var disabled = hotkey
        disabled.isEnabled = false
        XCTAssertFalse(disabled.matches(keyCode: 46, modifiers: [.command, .shift]))
    }

    func testCaptureRequiresModifierOrFunctionKey() {
        let plain = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "a", charactersIgnoringModifiers: "a",
            isARepeat: false, keyCode: 0
        )
        XCTAssertNil(Hotkey.capture(from: plain!))

        let command = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0,
            windowNumber: 0, context: nil, characters: "m", charactersIgnoringModifiers: "m",
            isARepeat: false, keyCode: 46
        )
        let captured = Hotkey.capture(from: command!)
        XCTAssertEqual(captured?.keyCode, 46)
        XCTAssertEqual(captured?.displayString, "⌘M")

        let function = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: 111
        )
        XCTAssertEqual(Hotkey.capture(from: function!)?.displayString, "F12")
    }

    func testPresetRestoresHotkeys() throws {
        let t = TestStorage()
        let settings = makeConfiguredSettings(t)
        settings.setHotkey(Hotkey(keyCode: 1, modifiers: [.command], label: "S", isEnabled: true), for: .mono)
        settings.savePreset(named: "Shortcut")

        settings.resetHotkeys()
        XCTAssertEqual(settings.hotkey(for: .mono).keyCode, 46)

        let preset = try XCTUnwrap(settings.presets.first)
        settings.apply(preset)
        XCTAssertEqual(settings.hotkey(for: .mono).keyCode, 1)
    }
}
