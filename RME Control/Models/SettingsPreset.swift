import Foundation

/// Именованный снимок настроек приложения: каналы, посылы, OSC-адреса
/// Control Room, внешний вид панели, клавиши и параметры веб-пульта.
struct SettingsPreset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var snapshot: Snapshot

    struct Snapshot: Codable, Equatable {
        var speakerBAddress: String
        var dimAddress: String
        var monoAddress: String
        var watchDeviceConnection: Bool

        var inputs: [InputConfig]
        var outputs: [OutputConfig]
        var sends: [SendConfig]

        var showMuteButtons: Bool
        var showSpeakerB: Bool
        var showDim: Bool
        var showMono: Bool
        var showInputCompressor: Bool
        var showInputEQ: Bool
        var showOutputCompressor: Bool
        var showOutputEQ: Bool
        /// Появилось вместе с Room EQ: в старых пресетах поля нет.
        var showOutputRoomEQ: Bool?

        var muteKeyAction: MuteKeyAction
        var volumeStepDB: Double
        var volumeKeyOutputID: UUID?
        var unmuteOnVolumeChange: Bool
        var switchOutputWithArrowKeys: Bool?
        var muteOtherOutputsOnSwitch: Bool?
        var useFunctionKeys: Bool

        var webServerEnabled: Bool
        var webServerPort: Int
        var webShowButtons: Bool
        var webShowInputs: Bool
        var webShowLevels: Bool

        /// Необязательное поле: пресеты, сохранённые до появления горячих клавиш,
        /// остаются читаемыми и просто не меняют комбинации.
        var hotkeys: [String: Hotkey]?

        /// Маршрутизация калибровщика.
        var calibrationRouting: CalibrationRoutingMode?
        var calibrationPlaybackPair: Int?
        /// Room EQ по OSC-адресам выходов: полосы, калибровка и служебные поля.
        var roomEQs: [String: RoomEQState]?
        /// Пресеты, сохранённые из замеров Room EQ.
        var roomEQUserPresets: [RoomEQUserPreset]?
        /// Настройки мастера замера.
        var roomCorrectionPreferences: RoomCorrectionPreferences?
    }
}
