import AppKit
import SwiftUI
import WebKit

/// Панель уровней входов, отрисованная React-страницей в `WKWebView`.
/// Ширина фиксирована, высота зависит от числа входов; кнопка CLOSE показывается
/// по правому клику по панели и возвращается через message handler.
struct LevelsWebView: NSViewRepresentable {
    private static let rowHeight: CGFloat = 8
    private static let rowGap: CGFloat = 8
    private static let padding: CGFloat = 12
    private static let columnGap: CGFloat = 8
    /// Фиксированная длина индикатора: окно меняет ширину, а не полоски.
    static let meterWidth: CGFloat = 96

    static func nameWidth(for viewModel: MixerViewModel) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 7.5, weight: .heavy),
            .kern: 0.6
        ]
        let widest = viewModel.levelInputs.reduce(CGFloat(0)) { result, input in
            let text = viewModel.inputLabel(for: input.id) as NSString
            return max(result, ceil(text.size(withAttributes: attributes).width))
        }
        return max(24, min(140, widest + 2))
    }

    static func valueWidth() -> CGFloat {
        let font = NSFont.monospacedSystemFont(ofSize: 7.5, weight: .heavy)
        let text = "00000" as NSString
        let width = text.size(withAttributes: [.font: font, .kern: 0.3]).width
        return ceil(width) + 1
    }

    static func contentSize(for viewModel: MixerViewModel) -> NSSize {
        let rows = CGFloat(max(viewModel.levelInputs.count, 1))
        let rowsHeight = rows * rowHeight + (rows - 1) * rowGap
        let width = padding * 2
            + nameWidth(for: viewModel)
            + columnGap
            + meterWidth
            + columnGap
            + valueWidth()
        return NSSize(width: width, height: padding * 2 + rowsHeight)
    }

    let viewModel: MixerViewModel
    var onClose: @MainActor () -> Void
    /// Сообщает окну новый размер, когда содержимое (число входов, имена) изменилось.
    var onResize: (@MainActor (NSSize) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel, onClose: onClose, onResize: onResize)
    }

    func makeNSView(context: Context) -> NSView {
        let size = Self.contentSize(for: viewModel)
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: Coordinator.messageName)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.autoresizingMask = [.width, .height]
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor

        let webView = LevelsWebViewImpl(frame: container.bounds, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.useTransparentBackground()
        webView.autoresizingMask = [.width, .height]
        webView.allowsBackForwardNavigationGestures = false
        container.addSubview(webView)

        context.coordinator.webView = webView
        context.coordinator.load()
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        static let messageName = "rme"

        private let viewModel: MixerViewModel
        private let onClose: @MainActor () -> Void
        private let onResize: (@MainActor (NSSize) -> Void)?

        weak var webView: WKWebView?
        private var updateTask: Task<Void, Never>?
        private let windowDrag = WindowDragController()
        private var lastSize: NSSize = .zero

        init(viewModel: MixerViewModel, onClose: @escaping @MainActor () -> Void, onResize: (@MainActor (NSSize) -> Void)?) {
            self.viewModel = viewModel
            self.onClose = onClose
            self.onResize = onResize
            super.init()
        }

        @MainActor
        func load() {
            guard let webView, let url = Self.pageURL() else { return }
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }

        private static func pageURL() -> URL? {
            if let url = Bundle.main.url(forResource: "levels", withExtension: "html") {
                return url
            }
            if let url = Bundle.main.url(forResource: "levels", withExtension: "html", subdirectory: "Web") {
                return url
            }
            return Bundle.main.resourceURL?.appendingPathComponent("levels.html")
        }

        @MainActor
        func stop() {
            updateTask?.cancel()
            updateTask = nil
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: Self.messageName)
            webView?.navigationDelegate = nil
        }

        // MARK: - WebKit delegates

        nonisolated func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            MainActor.assumeIsolated {
                handle(message)
            }
        }

        nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            MainActor.assumeIsolated {
                startUpdates()
            }
        }

        // MARK: - Web → native

        @MainActor
        private func handle(_ message: WKScriptMessage) {
            guard message.name == Self.messageName,
                  let body = message.body as? [String: Any],
                  let action = body["action"] as? String else { return }

            switch action {
            case "close":
                onClose()

            case "dragStart":
                windowDrag.start(for: webView?.window)

            case "drag":
                windowDrag.update()

            case "dragEnd":
                windowDrag.end()

            default:
                break
            }
        }

        // MARK: - Native → web

        @MainActor
        private func startUpdates() {
            pushState()
            updateTask?.cancel()
            updateTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    guard let self else { return }
                    self.pushState()
                }
            }
        }

        @MainActor
        private func pushState() {
            guard let webView else { return }

            let levelInputs = viewModel.levelInputs
            let size = LevelsWebView.contentSize(for: viewModel)
            if size != lastSize {
                lastSize = size
                onResize?(size)
            }

            let inputs: [[String: Any]] = levelInputs.map { input in
                [
                    "name": viewModel.inputLabel(for: input.id),
                    "phantom": viewModel.isPhantomOn(input.id),
                    "level": viewModel.micLevel(input.id)
                ]
            }

            guard let data = try? JSONSerialization.data(withJSONObject: [
                "inputs": inputs,
                "nameWidth": Double(LevelsWebView.nameWidth(for: viewModel)),
                "valueWidth": Double(LevelsWebView.valueWidth()),
                "meterWidth": Double(LevelsWebView.meterWidth)
            ]),
            let json = String(data: data, encoding: .utf8) else { return }

            webView.evaluateJavaScript("window.rme && window.rme.update(\(json));")
        }
    }
}

/// `WKWebView` в nonactivating-панели по умолчанию не получает первый клик.
private final class LevelsWebViewImpl: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
