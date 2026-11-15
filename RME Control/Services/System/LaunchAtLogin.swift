import ServiceManagement

/// Автозапуск приложения при входе в систему (обёртка над `SMAppService`).
@MainActor
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        if enabled {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
    }

    static func toggle() {
        setEnabled(!isEnabled)
    }
}
