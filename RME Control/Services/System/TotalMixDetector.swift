import AppKit

/// Следит, запущен ли RME TotalMix FX. Список процессов перебирается один раз при создании,
/// дальше флаг обновляется по уведомлениям NSWorkspace о запуске и завершении приложений,
/// поэтому `isRunning` можно дёшево проверять на каждое нажатие клавиши.
@MainActor
final class TotalMixDetector {
    nonisolated static let bundleIdentifier = "com.rme.TotalMixFX"
    nonisolated static let appNames: Set<String> = ["TotalMix FX", "TotalMix"]

    nonisolated static func isTotalMix(_ app: NSRunningApplication) -> Bool {
        app.bundleIdentifier == bundleIdentifier || appNames.contains(app.localizedName ?? "")
    }

    private(set) var isRunning: Bool
    /// Вызывается, когда TotalMix запустился.
    var onLaunch: (() -> Void)?

    private let workspace: NSWorkspace
    private var observers: [NSObjectProtocol] = []

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
        isRunning = workspace.runningApplications.contains(where: Self.isTotalMix)

        let center = workspace.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard Self.isTotalMix(in: notification) else { return }
            MainActor.assumeIsolated {
                self?.isRunning = true
                self?.onLaunch?()
            }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard Self.isTotalMix(in: notification) else { return }
            MainActor.assumeIsolated { self?.refresh() }
        })
    }

    /// Перепроверяет список процессов (на случай нескольких копий TotalMix).
    func refresh() {
        isRunning = workspace.runningApplications.contains(where: Self.isTotalMix)
    }

    private nonisolated static func isTotalMix(in notification: Notification) -> Bool {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return false }
        return isTotalMix(app)
    }
}
