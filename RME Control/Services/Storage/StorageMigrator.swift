import Foundation

/// Чтение настроек, сохранённых старыми версиями приложения:
/// старые OSC-адреса кнопок (`/1/mainDim`…), имена входов (`inputNames`)
/// и видимость входов (`showPhantom1…4`). Ничего не перезаписывает — только
/// возвращает актуальные значения, которые потом сохраняет `AppSettings`.
struct StorageMigrator {
    let storage: StorageProtocol

    func speakerBAddress() -> String {
        resolvedAddress(.speakerBAddress, legacy: OSCAddress.Legacy.speakerB, fallback: OSCAddress.Defaults.speakerB)
    }

    func dimAddress() -> String {
        resolvedAddress(.dimAddress, legacy: OSCAddress.Legacy.dim, fallback: OSCAddress.Defaults.dim)
    }

    func monoAddress() -> String {
        resolvedAddress(.monoAddress, legacy: OSCAddress.Legacy.mono, fallback: OSCAddress.Defaults.mono)
    }

    /// В хранилище остались данные очень старой версии, где каналы ещё не
    /// сохранялись единым JSON: имена входов и видимость +48V по номерам.
    var hasLegacyInputs: Bool {
        if storage.array(for: .legacyInputNames) != nil { return true }
        return (1...4).contains { number in
            guard let key = StorageKey.legacyShowPhantom(number: number) else { return false }
            return storage.object(for: key) != nil
        }
    }

    /// Входы по умолчанию с именами и видимостью из устаревших ключей.
    /// Используется, когда JSON-конфигурации входов ещё нет.
    func legacyInputs() -> [InputConfig] {
        var defs = DefaultConfig.inputs()
        if let savedNames = storage.array(for: .legacyInputNames) as? [String] {
            for (i, name) in savedNames.enumerated() where i < defs.count {
                defs[i].name = name
            }
        }
        for i in 0..<defs.count {
            if let key = StorageKey.legacyShowPhantom(number: i + 1),
               let v = storage.object(for: key) as? Bool {
                defs[i].showInMain = v
            }
        }
        return defs
    }

    /// Пустое значение или адрес из старой версии заменяются на адрес по умолчанию.
    private func resolvedAddress(_ key: StorageKey, legacy: String, fallback: String) -> String {
        let stored = storage.string(for: key) ?? ""
        return (stored.isEmpty || stored == legacy) ? fallback : stored
    }
}
