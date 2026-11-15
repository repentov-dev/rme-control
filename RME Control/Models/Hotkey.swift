import AppKit

/// Одна комбинация клавиш, которую пользователь назначил действию.
/// Хранится как код клавиши и модификаторы — так комбинация не зависит от раскладки
/// при срабатывании; подпись сохраняется для показа в настройках.
struct Hotkey: Codable, Equatable, Hashable {
    /// `nil` — комбинация не назначена.
    var keyCode: UInt16?
    /// Только Command/Option/Control/Shift: остальные флаги события не учитываем.
    var modifiers: UInt
    var label: String
    var isEnabled: Bool

    static let modifierMask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    init(keyCode: UInt16?, modifiers: NSEvent.ModifierFlags, label: String, isEnabled: Bool) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.modifierMask).rawValue
        self.label = label
        self.isEnabled = isEnabled
    }

    var isAssigned: Bool { keyCode != nil }

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers).intersection(Self.modifierMask)
    }

    /// Подпись для настроек, например «⇧⌘M» или «F12».
    var displayString: String {
        guard isAssigned else { return String(localized: "Not set") }
        var result = ""
        if modifierFlags.contains(.control) { result += "⌃" }
        if modifierFlags.contains(.option) { result += "⌥" }
        if modifierFlags.contains(.shift) { result += "⇧" }
        if modifierFlags.contains(.command) { result += "⌘" }
        return result + label
    }

    /// Совпадает ли комбинация с нажатием. `modifiers` — уже приведённые к `modifierMask`.
    func matches(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard isEnabled, let ownKeyCode = self.keyCode, ownKeyCode == keyCode else { return false }
        return modifiers.intersection(Self.modifierMask) == modifierFlags
    }

    /// Та же клавиша и те же модификаторы (для поиска конфликтов в настройках).
    func usesSameCombination(as other: Hotkey) -> Bool {
        keyCode != nil && keyCode == other.keyCode && modifierFlags == other.modifierFlags
    }

    // MARK: - Запись с клавиатуры

    /// Коды функциональных клавиш: их можно назначать без модификаторов.
    static let functionKeyCodes: Set<UInt16> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101,
        109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90
    ]

    private static let functionKeyNames: [UInt16: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18",
        80: "F19", 90: "F20"
    ]

    private static let specialKeyNames: [UInt16: String] = [
        123: "←", 124: "→", 125: "↓", 126: "↑",
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "Esc", 117: "⌦",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟", 76: "⌤"
    ]

    /// Собирает комбинацию из события клавиатуры.
    /// Возвращает `nil`, если такую комбинацию нельзя использовать как глобальную:
    /// без модификаторов разрешены только функциональные клавиши, иначе любая
    /// буква перехватывалась бы во всех приложениях.
    static func capture(from event: NSEvent) -> Hotkey? {
        let modifiers = event.modifierFlags.intersection(modifierMask)
        let isFunctionKey = functionKeyCodes.contains(event.keyCode)
        guard isFunctionKey || !modifiers.isEmpty else { return nil }
        guard isFunctionKey || modifiers.contains(.command) || modifiers.contains(.control) || modifiers.contains(.option) else {
            return nil
        }
        return Hotkey(
            keyCode: event.keyCode,
            modifiers: modifiers,
            label: label(for: event),
            isEnabled: true
        )
    }

    private static func label(for event: NSEvent) -> String {
        if let function = functionKeyNames[event.keyCode] { return function }
        if let special = specialKeyNames[event.keyCode] { return special }
        if let characters = event.charactersIgnoringModifiers, !characters.isEmpty {
            return characters.uppercased()
        }
        return String(localized: "Key \(event.keyCode)")
    }
}

/// Действия, которые можно повесить на горячие клавиши.
/// Аппаратные клавиши громкости работают всегда; эти комбинации — дополнительные.
enum HotkeyAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case volumeUp
    case volumeDown
    case mute
    case nextOutput
    case previousOutput
    case mono

    var id: String { rawValue }

    var title: String {
        switch self {
        case .volumeUp: return String(localized: "Volume Up")
        case .volumeDown: return String(localized: "Volume Down")
        case .mute: return String(localized: "Mute")
        case .nextOutput: return String(localized: "Next Output")
        case .previousOutput: return String(localized: "Previous Output")
        case .mono: return String(localized: "Mono")
        }
    }

    var detail: String {
        switch self {
        case .volumeUp:
            return String(localized: "Increase the selected output volume by one step.")
        case .volumeDown:
            return String(localized: "Decrease the selected output volume by one step.")
        case .mute:
            return String(localized: "Mute the selected output, or toggle Dim — see the hardware keys below.")
        case .nextOutput:
            return String(localized: "Switch the volume keys to the next output.")
        case .previousOutput:
            return String(localized: "Switch the volume keys to the previous output.")
        case .mono:
            return String(localized: "Toggle Mono on the control room.")
        }
    }

    var symbol: String {
        switch self {
        case .volumeUp: return "speaker.wave.3.fill"
        case .volumeDown: return "speaker.wave.1.fill"
        case .mute: return "speaker.slash.fill"
        case .nextOutput: return "arrow.up.circle"
        case .previousOutput: return "arrow.down.circle"
        case .mono: return "waveform"
        }
    }

    /// Действия с громкостью и переключением выходов требуют подключённого TotalMix.
    var requiresConnection: Bool { self != .mono }

    /// Комбинация по умолчанию: все действия включены сразу.
    var defaultHotkey: Hotkey {
        switch self {
        case .volumeUp:
            return Hotkey(keyCode: 111, modifiers: [], label: "F12", isEnabled: true)
        case .volumeDown:
            return Hotkey(keyCode: 103, modifiers: [], label: "F11", isEnabled: true)
        case .mute:
            return Hotkey(keyCode: 109, modifiers: [], label: "F10", isEnabled: true)
        case .nextOutput:
            return Hotkey(keyCode: 125, modifiers: [.option], label: "↓", isEnabled: true)
        case .previousOutput:
            return Hotkey(keyCode: 126, modifiers: [.option], label: "↑", isEnabled: true)
        case .mono:
            return Hotkey(keyCode: 46, modifiers: [.command, .shift], label: "M", isEnabled: true)
        }
    }
}
