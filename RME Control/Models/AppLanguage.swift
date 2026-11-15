import Foundation

/// Язык интерфейса. Выбирается вручную в настройках и не зависит от языка системы;
/// если язык ещё не выбран — английский.
enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case russian = "ru"
    case german = "de"
    case french = "fr"
    case spanish = "es"
    case italian = "it"
    case portuguese = "pt"
    case dutch = "nl"
    case polish = "pl"
    case ukrainian = "uk"
    case turkish = "tr"
    case chineseSimplified = "zh-Hans"
    case japanese = "ja"
    case korean = "ko"

    static let `default`: AppLanguage = .english

    var id: String { rawValue }

    /// Название языка на нём самом — не переводится.
    var displayName: String {
        switch self {
        case .english: return "English"
        case .russian: return "Русский"
        case .german: return "Deutsch"
        case .french: return "Français"
        case .spanish: return "Español"
        case .italian: return "Italiano"
        case .portuguese: return "Português"
        case .dutch: return "Nederlands"
        case .polish: return "Polski"
        case .ukrainian: return "Українська"
        case .turkish: return "Türkçe"
        case .chineseSimplified: return "简体中文"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        }
    }

    /// Язык, с которым запущен текущий процесс. Меняется только перезапуском.
    nonisolated(unsafe) private(set) static var launchLanguage: AppLanguage = .default

    /// Читает сохранённый язык и подменяет `AppleLanguages` в домене приложения,
    /// чтобы Bundle искал строки в нужном `.lproj`, а не по языку системы.
    /// Вызывается при старте до первого обращения к локализованным строкам.
    static func applyAtLaunch(defaults: UserDefaults = .standard) {
        let saved = defaults.string(forKey: StorageKey.language.rawValue).flatMap(AppLanguage.init) ?? .default
        launchLanguage = saved
        saved.applyOverride(defaults: defaults)
    }

    /// Записывает язык в `AppleLanguages` приложения; вступает в силу при следующем запуске.
    func applyOverride(defaults: UserDefaults = .standard) {
        defaults.set([rawValue], forKey: "AppleLanguages")
    }
}
