import AppKit
import ApplicationServices

/// Разрешение «Специальные возможности», без которого не работает перехват клавиш громкости.
@MainActor
enum AccessibilityPermission {
    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Показывает алерт с предложением открыть системные настройки.
    static func prompt() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Accessibility Permission")
        alert.informativeText = String(localized: "To control Main volume with the macOS volume keys, RME Control needs the Accessibility permission. Open System Settings → Privacy & Security → Accessibility, add RME Control, then restart the app.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Open Settings"))
        alert.addButton(withTitle: String(localized: "Later"))
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openSystemSettings()
        }
    }

    /// Открывает раздел «Специальные возможности» в системных настройках.
    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
