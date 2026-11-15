import AppKit

/// Перетаскивание безрамочной панели за фон React-страницы.
/// Страница присылает `dragStart`/`drag`/`dragEnd`, позиция окна считается
/// по смещению курсора в экранных координатах — курсор при этом не меняется.
@MainActor
final class WindowDragController {
    private weak var window: NSWindow?
    private var startMouse = NSPoint.zero
    private var startOrigin = NSPoint.zero
    private var active = false

    func start(for window: NSWindow?) {
        guard let window else { return }
        self.window = window
        startMouse = NSEvent.mouseLocation
        startOrigin = window.frame.origin
        active = true
    }

    func update() {
        guard active, let window else { return }
        let current = NSEvent.mouseLocation
        window.setFrameOrigin(NSPoint(
            x: startOrigin.x + (current.x - startMouse.x),
            y: startOrigin.y + (current.y - startMouse.y)
        ))
    }

    func end() {
        active = false
        window = nil
    }
}
