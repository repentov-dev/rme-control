import AppKit

/// Панель выбора файла листом к ключевому окну. В отличие от `runModal()`
/// не запускает собственный runloop и не блокирует главный поток.
@MainActor
enum FilePanel {
    static func present(_ panel: NSSavePanel, completion: @escaping (URL?) -> Void) {
        guard let window = NSApp.keyWindow, window.isVisible else {
            completion(panel.runModal() == .OK ? panel.url : nil)
            return
        }
        panel.beginSheetModal(for: window) { response in
            completion(response == .OK ? panel.url : nil)
        }
    }
}
