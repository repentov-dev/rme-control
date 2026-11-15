import Foundation

/// Все ключи UserDefaults приложения в одном месте.
///
/// Raw value — фактическое имя ключа в plist. Его нельзя менять без миграции,
/// иначе пользователи потеряют сохранённые настройки после обновления.
enum StorageKey: String, CaseIterable {
    // MARK: OSC-подключение к TotalMix
    case oscHost = "oscHost"
    case oscSendPort = "oscSendPort"
    case oscRecvPort = "oscRecvPort"

    // MARK: OSC-адреса кнопок Control Room
    case speakerBAddress = "speakerBAddress"
    case dimAddress = "dimAddress"
    case monoAddress = "monoAddress"

    // MARK: Конфигурация каналов (JSON)
    case inputs = "inputs"
    case outputs = "outputs"
    case sends = "sends"

    // MARK: Отображение в поповере
    case showMuteButtons = "showMuteButtons"
    case showSpeakerB = "showSpeakerB"
    case showDim = "showDim"
    case showMono = "showMono"

    // MARK: Компрессор и эквалайзер в UI
    case showInputCompressor = "showInputCompressor"
    case showInputEQ = "showInputEQ"
    case showOutputCompressor = "showOutputCompressor"
    case showOutputEQ = "showOutputEQ"

    // MARK: Аппаратные клавиши
    case muteKeyAction = "muteKeyAction"
    case volumeStepDB = "volumeStepDB"
    case volumeKeyOutputID = "volumeKeyOutputID"
    case unmuteOnVolumeChange = "unmuteOnVolumeChange"
    case switchOutputWithArrowKeys = "switchOutputWithArrowKeys"
    case muteOtherOutputsOnSwitch = "muteOtherOutputsOnSwitch"
    case useFunctionKeys = "useFunctionKeys"

    // MARK: Настраиваемые горячие клавиши (JSON: действие → комбинация)
    case hotkeys = "hotkeys"

    // MARK: Первый запуск
    case setupCompleted = "setupCompleted"

    // MARK: Устройство
    case watchDeviceConnection = "watchDeviceConnection"

    // MARK: Пресеты настроек (JSON)
    case settingsPresets = "settingsPresets"

    // MARK: Язык интерфейса
    case language = "appLanguage"

    // MARK: Веб-пульт
    case webServerEnabled = "webServerEnabled"
    case webServerPort = "webServerPort"
    case webShowButtons = "webShowButtons"
    case webShowInputs = "webShowInputs"
    case webShowLevels = "webShowLevels"

    // MARK: Устаревшие ключи
    // Состояние пульта (Dim/Mono/Speaker B, +48V/Inst) больше не сохраняется:
    // TotalMix присылает его по `/sendall`. Ключи оставлены, чтобы их имена не переиспользовались.
    case legacySpeakerBOn = "speakerBOn"
    case legacyDimOn = "dimOn"
    case legacyMonoOn = "monoOn"
    case legacyPhantom = "phantom"
    case legacyInstrument = "instrument"

    // Читаются только при миграции со старых версий.
    case legacyInputNames = "inputNames"
    case legacyShowPhantom1 = "showPhantom1"
    case legacyShowPhantom2 = "showPhantom2"
    case legacyShowPhantom3 = "showPhantom3"
    case legacyShowPhantom4 = "showPhantom4"

    /// Устаревший ключ видимости входа по его номеру (1…4).
    static func legacyShowPhantom(number: Int) -> StorageKey? {
        StorageKey(rawValue: "showPhantom\(number)")
    }
}
