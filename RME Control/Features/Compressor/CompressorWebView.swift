import AppKit
import SwiftUI
import WebKit

/// Окно компрессора, отрисованное React-страницей в `WKWebView`.
/// Состояние приходит из `MixerViewModel` в страницу, а действия пользователя
/// (ручки, питание, пресеты, перетаскивание) возвращаются через message handler.
struct CompressorWebView: NSViewRepresentable {
    static let contentSize = NSSize(width: 380, height: 252)

    let viewModel: MixerViewModel
    let target: CompressorTarget
    var onClose: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel, target: target, onClose: onClose)
    }

    func makeNSView(context: Context) -> NSView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: Coordinator.messageName)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller

        let container = NSView(frame: NSRect(origin: .zero, size: Self.contentSize))
        container.autoresizingMask = [.width, .height]
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor

        let webView = InteractiveWebView(frame: container.bounds, configuration: configuration)
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
        private let target: CompressorTarget
        private let onClose: @MainActor () -> Void

        weak var webView: WKWebView?
        private var updateTask: Task<Void, Never>?
        private let windowDrag = WindowDragController()

        init(viewModel: MixerViewModel, target: CompressorTarget, onClose: @escaping @MainActor () -> Void) {
            self.viewModel = viewModel
            self.target = target
            self.onClose = onClose
            super.init()
        }

        @MainActor
        func load() {
            guard let webView, let url = Self.pageURL() else { return }
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }

        private static func pageURL() -> URL? {
            if let url = Bundle.main.url(forResource: "compressor", withExtension: "html") {
                return url
            }
            if let url = Bundle.main.url(forResource: "compressor", withExtension: "html", subdirectory: "Web") {
                return url
            }
            return Bundle.main.resourceURL?.appendingPathComponent("compressor.html")
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
            case "param":
                guard let name = body["name"] as? String,
                      let parameter = CompressorParameter(rawValue: name),
                      let value = (body["value"] as? NSNumber)?.doubleValue else { return }
                viewModel.setCompressorParameter(target, parameter, value)

            case "power":
                guard let enabled = (body["enabled"] as? NSNumber)?.boolValue else { return }
                viewModel.setCompressorEnabled(target, enabled)

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
                    try? await Task.sleep(nanoseconds: 40_000_000)
                    guard let self else { return }
                    self.pushState()
                }
            }
        }

        @MainActor
        private func pushState() {
            guard let webView else { return }

            let compressor = viewModel.compressor(target)
            let payload: [String: Any] = [
                "name": viewModel.eqLabel(EQTarget(bus: target.bus, id: target.id)),
                "isOutput": target.bus == .output,
                "enabled": compressor.enabled,
                "params": [
                    "threshold": compressor.threshold,
                    "ratio": compressor.ratio,
                    "attack": compressor.attack,
                    "release": compressor.release,
                    "gain": compressor.gain
                ],
                "level": viewModel.compressorInputLevel(target),
                "reduction": viewModel.compressorGainReduction(target),
                "output": viewModel.compressorOutputLevel(target)
            ]

            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let json = String(data: data, encoding: .utf8) else { return }

            webView.evaluateJavaScript("window.rme && window.rme.update(\(json));")
        }
    }
}

/// `WKWebView` в nonactivating-панели по умолчанию не получает первый клик
/// (панель никогда не становится key), поэтому кнопки и ручки не реагируют.
private final class InteractiveWebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
