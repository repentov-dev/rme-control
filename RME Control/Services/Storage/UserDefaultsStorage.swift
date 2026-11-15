import Foundation

/// Реализация `StorageProtocol` поверх `UserDefaults`.
/// Создаётся один раз в `AppCoordinator` и передаётся в сервисы через init.
final class UserDefaultsStorage: StorageProtocol {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func object(for key: StorageKey) -> Any? {
        defaults.object(forKey: key.rawValue)
    }

    func string(for key: StorageKey) -> String? {
        defaults.string(forKey: key.rawValue)
    }

    func bool(for key: StorageKey) -> Bool {
        defaults.bool(forKey: key.rawValue)
    }

    func integer(for key: StorageKey) -> Int {
        defaults.integer(forKey: key.rawValue)
    }

    func data(for key: StorageKey) -> Data? {
        defaults.data(forKey: key.rawValue)
    }

    func array(for key: StorageKey) -> [Any]? {
        defaults.array(forKey: key.rawValue)
    }

    func set(_ value: Any?, for key: StorageKey) {
        defaults.set(value, forKey: key.rawValue)
    }

    func remove(_ key: StorageKey) {
        defaults.removeObject(forKey: key.rawValue)
    }
}
