import Foundation
@testable import RME_Control

/// Изолированное хранилище на отдельном домене UserDefaults — не трогает настройки приложения.
final class TestStorage {
    let suiteName = "rmecontrol.tests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let storage: UserDefaultsStorage

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
        storage = UserDefaultsStorage(defaults: defaults)
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

/// Фейковый OSC-транспорт: запоминает отправленные сообщения вместо сети.
@MainActor
final class FakeOSC: OSCSending {
    private(set) var sent: [(address: String, value: Float)] = []

    func send(_ address: String, _ value: Float) {
        sent.append((address, value))
    }

    var last: (address: String, value: Float)? { sent.last }
}

/// Настройки с каналами: на первом запуске каналов больше нет, поэтому тестам,
/// которым нужны готовые входы и выходы, их нужно создать явно.
@MainActor
func makeConfiguredSettings(_ testStorage: TestStorage) -> AppSettings {
    let settings = AppSettings(storage: testStorage.storage)
    if settings.inputs.isEmpty || settings.outputs.isEmpty {
        settings.resetToDefaults()
    }
    return settings
}

/// Граф сервисов как в AppCoordinator, но с изолированным хранилищем и фейковым OSC.
@MainActor
struct MixerFixture {
    let testStorage = TestStorage()
    let osc = FakeOSC()
    let settings: AppSettings
    let state = MixerState()
    let mixer: MixerService

    init() {
        settings = makeConfiguredSettings(testStorage)
        mixer = MixerService(osc: osc, settings: settings, state: state)
    }

    func outputID(_ index: Int) -> UUID { settings.outputs[index].id }
    func inputID(_ index: Int) -> UUID { settings.inputs[index].id }
}
