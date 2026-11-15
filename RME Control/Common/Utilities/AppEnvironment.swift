import Foundation

/// Сведения об окружении, в котором запущено приложение.
enum AppEnvironment {
    /// Приложение запущено как хост для юнит-тестов.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Версия приложения из Info.plist (CFBundleShortVersionString).
    static var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
    }
}
