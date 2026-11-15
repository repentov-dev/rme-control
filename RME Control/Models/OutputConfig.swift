import Foundation

/// Иконка выходного канала в UI.
enum OutputIcon: String, Codable, CaseIterable, Identifiable {
    case speaker
    case headphones
    case output
    case mixer

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .speaker: return String(localized: "Speaker")
        case .headphones: return String(localized: "Headphones")
        case .output: return String(localized: "Audio output")
        case .mixer: return String(localized: "Mixer")
        }
    }

    var symbolName: String {
        switch self {
        case .speaker: return "hifispeaker.fill"
        case .headphones: return "headphones"
        case .output: return "cable.connector"
        case .mixer: return "slider.horizontal.3"
        }
    }
}

/// Пользовательская конфигурация выходного канала (Main, Phones…):
/// имя, OSC-адрес в TotalMix, адрес индикатора уровня, иконка и видимость в поповере.
/// Сохраняется в UserDefaults как JSON (ключ `StorageKey.outputs`).
struct OutputConfig: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String = ""
    var oscAddress: String = ""
    var icon: OutputIcon = .speaker
    var showInMain: Bool = true

    /// Адрес уровня выводится из номера канала в OSC-адресе
    /// (`/output/8` → `/level/out/8`, `/output/21` → `/level/out/21`).
    var resolvedLevelAddress: String {
        OSCAddress.levelAddress(forChannelAddress: oscAddress, prefix: OSCAddress.levelOutputPrefix)
    }

    init(id: UUID = UUID(), name: String = "", oscAddress: String = "", icon: OutputIcon = .speaker, showInMain: Bool = true) {
        self.id = id
        self.name = name
        self.oscAddress = oscAddress
        self.icon = icon
        self.showInMain = showInMain
    }

    enum CodingKeys: String, CodingKey {
        case id, name, oscAddress, icon, showInMain
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        oscAddress = try c.decodeIfPresent(String.self, forKey: .oscAddress) ?? ""
        icon = (try? c.decode(OutputIcon.self, forKey: .icon)) ?? .speaker
        showInMain = try c.decodeIfPresent(Bool.self, forKey: .showInMain) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(oscAddress, forKey: .oscAddress)
        try c.encode(icon, forKey: .icon)
        try c.encode(showInMain, forKey: .showInMain)
    }
}
