import AppKit

/// Файл, в котором macOS хранит настройки приложения (UserDefaults в виде plist).
/// Кнопка «Show Settings File» в настройках показывает именно его в Finder.
enum SettingsFile {
    /// Путь к plist домена приложения. В песочнице `libraryDirectory` уже указывает
    /// внутрь контейнера, поэтому путь остаётся корректным.
    static var url: URL? {
        let domain = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
        guard let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return nil
        }
        return library
            .appendingPathComponent("Preferences", isDirectory: true)
            .appendingPathComponent("\(domain).plist")
    }

    static var displayPath: String { url?.path ?? "" }

    /// Открывает файл в Finder. Если файла ещё нет (приложение ничего не сохраняло),
    /// открываем папку с настройками, чтобы пользователь видел, где он появится.
    @MainActor
    static func reveal() {
        guard let url else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }
}
