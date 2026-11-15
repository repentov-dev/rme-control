import AppKit

/// Иконка приложения в строке меню. Левый клик вызывает `onLeftClick`
/// (открывает поповер), правый — меню с настройками, запуском при входе и выходом.
@MainActor
final class StatusBarController: NSObject {
    private(set) var statusItem: NSStatusItem!
    private var onLeftClick: (() -> Void)?
    /// Вызывается из контекстного меню: настройки должны быть доступны,
    /// даже если поповер оказался больше экрана.
    var onOpenSettings: (() -> Void)?

    func install(onLeftClick: @escaping () -> Void) {
        self.onLeftClick = onLeftClick
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let logo = NSImage(contentsOfFile: Bundle.main.path(forResource: "RME_Control_Tray", ofType: "png") ?? "") {
                logo.size = NSSize(width: 36, height: 6)
                logo.isTemplate = true
                button.image = logo
            } else {
                button.image = NSImage(systemSymbolName: "hifispeaker.2.fill", accessibilityDescription: "RME Control")
            }
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.appearance = NSApp.effectiveAppearance

            let settingsItem = NSMenuItem(title: String(localized: "Settings…"), action: #selector(openSettings), keyEquivalent: "")
            settingsItem.target = self
            menu.addItem(settingsItem)

            menu.addItem(.separator())

            let launchItem = NSMenuItem(title: String(localized: "Launch at Startup"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
            launchItem.target = self
            launchItem.state = LaunchAtLogin.isEnabled ? .on : .off
            menu.addItem(launchItem)

            menu.addItem(.separator())

            let quitItem = NSMenuItem(title: String(localized: "Quit"), action: #selector(quit), keyEquivalent: "")
            quitItem.target = self
            menu.addItem(quitItem)

            statusItem.menu = menu
            button.performClick(nil)
            statusItem.menu = nil
        } else {
            onLeftClick?()
        }
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLogin.toggle()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
