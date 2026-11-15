import AppKit
import SwiftUI

/// Невидимая область, за которую можно перетаскивать безрамочную панель.
struct WindowDragHandle: NSViewRepresentable {
    var onSecondaryClick: (@MainActor () -> Void)? = nil

    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        view.onSecondaryClick = onSecondaryClick
        return view
    }

    func updateNSView(_ nsView: DragView, context: Context) {
        nsView.onSecondaryClick = onSecondaryClick
    }

    final class DragView: NSView {
        var onSecondaryClick: (@MainActor () -> Void)?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }

        override func rightMouseDown(with event: NSEvent) {
            guard onSecondaryClick != nil else {
                super.rightMouseDown(with: event)
                return
            }
            let menu = NSMenu()
            let item = NSMenuItem(title: "Close", action: #selector(close), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }

        @objc private func close() {
            onSecondaryClick?()
        }
    }
}

/// Красная кнопка закрытия в стиле macOS: крестик проявляется при наведении.
struct PanelCloseButton: View {
    var showGlyph: Bool = false
    let action: @MainActor () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color(nsColor: .systemRed))
                    .overlay(
                        Circle()
                            .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
                    )

                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color.black.opacity(showGlyph || hovered ? 0.6 : 0))
            }
            .frame(width: 13, height: 13)
            .frame(width: 20, height: 20)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("Close")
    }
}

extension View {
    /// Материал панели с тонкой обводкой как у нативного поповера.
    func panelSurface(cornerRadius: CGFloat = 12) -> some View {
        self
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color(nsColor: .windowBackgroundColor).opacity(0.18), lineWidth: 0.5)
            )
    }

    /// Фон как у главного поповера: материал `.popover` и та же тонкая обводка.
    func popoverSurface(cornerRadius: CGFloat = 12) -> some View {
        self
            .background(PopoverSurface(cornerRadius: cornerRadius))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color(nsColor: .windowBackgroundColor).opacity(0.18), lineWidth: 0.5)
            )
    }
}

/// Фон нативного поповера: визуальный материал AppKit с тем же видом,
/// что и главный поповер из строки меню.
struct PopoverSurface: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .withinWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.layer?.cornerRadius = cornerRadius
    }
}

/// Общие прозрачности для главного поповера и панелей: карточки,
/// кнопки-капсулы, сетка графика и обводка неактивных кнопок.
enum PanelOpacity {
    static let card = 0.1
    static let control = 0.2
    static let grid = 0.05
    static let outline = 0.45
}
