import AppKit

/// Системные уведомления, на которые подписывается приложение.
@MainActor
enum SystemNotifications {
    /// Экран подключили/отключили или изменили его разрешение.
    static func observeScreenParameterChanges(_ handler: @escaping @MainActor () -> Void) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { handler() }
        }
    }
}
