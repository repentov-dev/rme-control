import Foundation

/// Тип входного канала: определяет, есть ли у него фантомное питание (+48V)
/// и инструментальный режим (Hi-Z), и показывается ли он в поповере.
enum InputType: String, Codable, CaseIterable, Identifiable {
    case line
    case micPhantom
    case instrument
    case micPhantomInstrument

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .line: return String(localized: "Line")
        case .micPhantom: return String(localized: "Mic +48V")
        case .instrument: return String(localized: "Inst")
        case .micPhantomInstrument: return String(localized: "Mic +48V + Inst")
        }
    }

    var hasPhantom: Bool { self == .micPhantom || self == .micPhantomInstrument }
    var hasInstrument: Bool { self == .instrument || self == .micPhantomInstrument }
    /// У входа есть кнопка компрессора (только комбо-входы Mic +48V + Inst).
    var showsCompressor: Bool { self == .micPhantomInstrument }
}

/// Пользовательская конфигурация входного канала: имя, OSC-адрес в TotalMix,
/// адрес индикатора уровня и где канал показывать.
/// Сохраняется в UserDefaults как JSON (ключ `StorageKey.inputs`).
struct InputConfig: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String = ""
    var oscAddress: String = ""
    var type: InputType = .line
    var showInMain: Bool = true
    var showInPopover: Bool = true

    /// Адрес уровня выводится из номера канала в OSC-адресе
    /// (`/input/8` → `/level/in/8`, `/input/21` → `/level/in/21`).
    var resolvedLevelAddress: String {
        OSCAddress.levelAddress(forChannelAddress: oscAddress, prefix: OSCAddress.levelInputPrefix)
    }

    init(id: UUID = UUID(), name: String = "", oscAddress: String = "", type: InputType = .line, showInMain: Bool = true, showInPopover: Bool = true) {
        self.id = id
        self.name = name
        self.oscAddress = oscAddress
        self.type = type
        self.showInMain = showInMain
        self.showInPopover = showInPopover
    }

    /// `hasPreamps` — устаревшее поле старых версий, читается только при декодировании.
    enum CodingKeys: String, CodingKey {
        case id, name, oscAddress, type, showInMain, showInPopover, hasPreamps
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        oscAddress = try c.decodeIfPresent(String.self, forKey: .oscAddress) ?? ""
        showInMain = try c.decodeIfPresent(Bool.self, forKey: .showInMain) ?? true
        showInPopover = try c.decodeIfPresent(Bool.self, forKey: .showInPopover) ?? true
        if let t = try? c.decode(InputType.self, forKey: .type) {
            type = t
        } else if let hp = try? c.decode(Bool.self, forKey: .hasPreamps) {
            type = hp ? .micPhantomInstrument : .line
        } else {
            type = .line
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(oscAddress, forKey: .oscAddress)
        try c.encode(type, forKey: .type)
        try c.encode(showInMain, forKey: .showInMain)
        try c.encode(showInPopover, forKey: .showInPopover)
    }
}
