import Foundation

/// Абстракция key-value хранилища настроек. Сервисы зависят от протокола,
/// а не от `UserDefaults`, поэтому в тестах можно подставить хранилище в памяти.
protocol StorageProtocol: AnyObject {
    func object(for key: StorageKey) -> Any?
    func string(for key: StorageKey) -> String?
    func bool(for key: StorageKey) -> Bool
    func integer(for key: StorageKey) -> Int
    func data(for key: StorageKey) -> Data?
    func array(for key: StorageKey) -> [Any]?

    /// Записывает значение; `nil` удаляет ключ.
    func set(_ value: Any?, for key: StorageKey)
    func remove(_ key: StorageKey)
}

extension StorageProtocol {
    /// Значение нужного типа или `defaultValue`, если ключа нет или тип не совпал.
    func value<T>(_ key: StorageKey, default defaultValue: T) -> T {
        object(for: key) as? T ?? defaultValue
    }

    /// Читает и декодирует JSON. `nil`, если ключа нет или данные не декодируются.
    func decodable<T: Decodable>(_ type: T.Type, for key: StorageKey) -> T? {
        guard let data = data(for: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Кодирует значение в JSON и сохраняет. При ошибке кодирования ничего не пишет.
    func setEncodable<T: Encodable>(_ value: T, for key: StorageKey) {
        if let data = try? JSONEncoder().encode(value) {
            set(data, for: key)
        }
    }
}
