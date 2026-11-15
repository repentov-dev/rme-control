import Foundation

/// Конфигурация каналов по умолчанию: используется при явном сбросе настроек
/// и при миграции очень старой версии, где каналы ещё не сохранялись списком.
/// На первом запуске каналов нет — их выбирают в мастере настройки.
enum DefaultConfig {
    static func inputs() -> [InputConfig] {
        [
            InputConfig(name: "Mic 1", oscAddress: "/input/8", type: .micPhantomInstrument),
            InputConfig(name: "Mic 2", oscAddress: "/input/9", type: .micPhantomInstrument),
            InputConfig(name: "Mic 3", oscAddress: "/input/10", type: .micPhantomInstrument),
            InputConfig(name: "Guitar", oscAddress: "/input/11", type: .instrument)
        ]
    }

    static func outputs() -> [OutputConfig] {
        [
            OutputConfig(name: "Main", oscAddress: "/output/0", icon: .speaker, showInMain: true),
            OutputConfig(name: "Phones 1", oscAddress: "/output/8", icon: .headphones, showInMain: true),
            OutputConfig(name: "Phones 2", oscAddress: "/output/10", icon: .headphones, showInMain: true)
        ]
    }

    static let volumeStepDB: Double = 2
    static let webServerPort = 8080
    /// Адрес, который получает новый вход, добавленный в настройках.
    static let newInputAddress = "/input/12"
}
