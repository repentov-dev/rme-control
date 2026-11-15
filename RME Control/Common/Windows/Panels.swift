import AppKit
import SwiftUI
import WebKit

extension WKWebView {
    /// `WKWebView` по умолчанию заливает себя белым до первой отрисовки страницы,
    /// из-за чего безрамочные панели мерцают белым при открытии. Отключаем
    /// собственную заливку, чтобы просвечивал чёрный фон контейнера/страницы.
    @MainActor
    func useTransparentBackground() {
        underPageBackgroundColor = .clear
        setValue(false, forKey: "drawsBackground")
    }
}

/// Хостинг SwiftUI-контента, за который можно перетаскивать безрамочное окно.
final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

/// SwiftUI-контент в nonactivating-панели: первый клик по элементам управления
/// должен доходить до них, но фон окна при этом не перетаскивается.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

/// Плавающая панель уровней входов. Может становиться key-окном,
/// чтобы в ней работало переименование входа по двойному клику.
final class MetersPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Делает панель уровней (если она открыта) key-окном и активирует приложение,
    /// чтобы текстовое поле могло получить фокус ввода.
    @MainActor
    static func activateForTextInput() {
        if let panel = NSApp.windows.first(where: { $0 is MetersPanel }) {
            panel.makeKeyAndOrderFront(nil)
        }
        NSApp.activate()
    }
}

/// Плавающее окно компрессора входа; может становиться key-окном,
/// чтобы ручки получали события мыши.
final class CompressorPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Плавающее окно эквалайзера канала; может становиться key-окном,
/// чтобы график и ручки получали события мыши.
final class EQPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Окно OSC-монитора: при закрытии выключает запись журнала.
final class OSCMonitorWindow: NSWindow {
    var onClose: (() -> Void)?

    override func close() {
        super.close()
        onClose?()
    }
}

/// Окно выбора каналов из TotalMix: при закрытии освобождает своё состояние.
final class ChannelDiscoveryWindow: NSWindow {
    var onClose: (() -> Void)?

    override func close() {
        super.close()
        onClose?()
    }
}

/// Окно мастера первого запуска: закрытие тоже завершает мастер.
final class SetupAssistantWindow: NSWindow {
    var onClose: (() -> Void)?

    override func close() {
        super.close()
        onClose?()
    }
}

/// Окно настроек: свободно меняет размер в пределах, заданных `WindowManager`.
final class SettingsWindow: NSWindow, NSWindowDelegate {
    static let minimumWidth: CGFloat = 550

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(width: max(frameSize.width, Self.minimumWidth), height: frameSize.height)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var rect = frameRect
        rect.size.width = max(rect.width, Self.minimumWidth)
        super.setFrame(rect, display: flag)
    }

    override func setContentSize(_ size: NSSize) {
        var adjusted = size
        adjusted.width = max(adjusted.width, Self.minimumWidth)
        super.setContentSize(adjusted)
    }
}


/// Создание прозрачных безрамочных панелей поверх всех окон и Spaces
/// (панель уровней, индикатор DIM).
@MainActor
enum PanelFactory {
    static func makeOverlayPanel<P: NSPanel>(_ type: P.Type, contentView: NSView, size explicitSize: NSSize? = nil) -> P {
        let size = explicitSize ?? contentView.fittingSize
        let panel = P(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 12
        contentView.layer?.cornerCurve = .continuous
        contentView.layer?.masksToBounds = true
        contentView.frame = NSRect(origin: .zero, size: size)
        panel.contentView = contentView
        if explicitSize != nil {
            panel.minSize = size
            panel.maxSize = size
        }
        return panel
    }
}
