import SwiftUI

/// Точка входа. Приложение живёт в строке меню и не имеет обычных окон-сцен,
/// поэтому весь жизненный цикл передаётся в `AppDelegate`.
@main
struct RMEControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // До загрузки любых строк: язык интерфейса берётся из настроек, а не из системы.
        AppLanguage.applyAtLaunch()
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
