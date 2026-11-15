import AppKit

/// Делегат приложения — только жизненный цикл: создаёт `AppCoordinator`,
/// который собирает зависимости и запускает сервисы, и останавливает его при выходе.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // В юнит-тестах приложение служит только хостом: не открываем сокеты,
        // не перехватываем клавиши и не показываем алерты.
        guard !AppEnvironment.isRunningTests else { return }
        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        coordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
    }
}
