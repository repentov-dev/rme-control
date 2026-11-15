import Foundation
import Network

/// Встроенный HTTP-сервер веб-пульта для управления с телефона в той же сети.
/// Отдаёт страницу `remote.html` из ресурсов, JSON-состояние (`/api/state`, `/api/levels`)
/// и принимает действия (`POST /api/volume`, `/api/mute`, `/api/dim`…).
/// Сеть обрабатывается на собственной очереди; чтение состояния и действия выполняются
/// на `MainActor`, и ответ отправляется только после того, как действие применено.
@MainActor
final class WebServer {
    private var listener: NWListener?
    nonisolated private let queue = DispatchQueue(label: "rme.webserver")
    nonisolated private let pageData: Data?
    nonisolated private let iconData: Data?
    nonisolated private let compressorPageData: Data?
    nonisolated private let eqPageData: Data?
    nonisolated private let webAssets: [String: Data]

    private let settings: AppSettings
    private let state: MixerState
    private let mixer: MixerService

    var isRunning: Bool { listener != nil }

    init(settings: AppSettings, state: MixerState, mixer: MixerService, bundle: Bundle = .main) {
        self.settings = settings
        self.state = state
        self.mixer = mixer
        pageData = Self.resourceData("remote", extension: "html", bundle: bundle)
        iconData = Self.resourceData("AppIcon", extension: "png", bundle: bundle)
        compressorPageData = Self.resourceData("compressor", extension: "html", bundle: bundle)
        eqPageData = Self.resourceData("eq", extension: "html", bundle: bundle)
        var assets: [String: Data] = [:]
        for name in ["compressor.js", "eq.js", "react.production.min.js", "react-dom.production.min.js", "window-drag.js", "remote-bridge.js"] {
            if let data = Self.resourceData((name as NSString).deletingPathExtension, extension: (name as NSString).pathExtension, bundle: bundle) {
                assets["/" + name] = data
            }
        }
        webAssets = assets
    }

    nonisolated private static func resourceData(_ name: String, extension ext: String, bundle: Bundle) -> Data? {
        let url = bundle.url(forResource: name, withExtension: ext)
            ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "Web")
            ?? bundle.resourceURL?.appendingPathComponent("\(name).\(ext)")
        return url.flatMap { try? Data(contentsOf: $0) }
    }

    func start(port: UInt16) {
        stop()
        guard let listener = try? NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port) ?? 8080) else { return }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    /// Адрес веб-пульта для QR-кода и ссылки в настройках.
    var urlString: String {
        let ip = NetworkInfo.localIP() ?? "localhost"
        return "http://\(ip):\(settings.webServerPort)"
    }

    // MARK: - HTTP (очередь сервера)

    nonisolated private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(connection, buffer: Data())
    }

    nonisolated private func receiveRequest(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buf = buffer
            if let data, !data.isEmpty { buf.append(data) }
            if error != nil {
                connection.cancel()
                return
            }
            if let range = buf.range(of: Data("\r\n\r\n".utf8)) {
                let headEnd = range.upperBound
                let headPart = String(data: buf[..<range.lowerBound], encoding: .utf8) ?? ""
                let headers = headPart.components(separatedBy: "\r\n")
                guard let requestLine = headers.first else { connection.cancel(); return }
                let parts = requestLine.split(separator: " ")
                guard parts.count >= 2 else { connection.cancel(); return }
                let method = String(parts[0])
                let path = String(parts[1])
                var contentLength = 0
                for h in headers.dropFirst() {
                    let kv = h.split(separator: ":", maxSplits: 1)
                    if kv.count == 2, kv[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                        contentLength = Int(kv[1].trimmingCharacters(in: .whitespaces)) ?? 0
                    }
                }
                if buf[headEnd...].count < contentLength {
                    self.receiveRequest(connection, buffer: buf)
                    return
                }
                let body = Data(buf[headEnd...].prefix(contentLength))
                self.route(connection, method: method, path: path, body: body)
                return
            }
            if isComplete {
                connection.cancel()
                return
            }
            self.receiveRequest(connection, buffer: buf)
        }
    }

    nonisolated private func route(_ connection: NWConnection, method: String, path: String, body: Data) {
        let cleanPath = path.split(separator: "?").first.map(String.init) ?? path
        switch cleanPath {
        case "/", "/index.html":
            if let pageData {
                Self.send(connection, status: 200, contentType: "text/html; charset=utf-8", body: pageData)
            } else {
                Self.send(connection, status: 500, contentType: "text/plain", body: Data("Remote page resource is missing".utf8))
            }
        case "/apple-touch-icon.png", "/icon.png", "/favicon.ico":
            if let iconData {
                Self.send(connection, status: 200, contentType: "image/png", body: iconData)
            } else {
                Self.sendNotFound(connection)
            }
        case "/compressor", "/compressor.html":
            if let compressorPageData {
                Self.send(connection, status: 200, contentType: "text/html; charset=utf-8", body: compressorPageData)
            } else {
                Self.sendNotFound(connection)
            }
        case "/eq", "/eq.html":
            if let eqPageData {
                Self.send(connection, status: 200, contentType: "text/html; charset=utf-8", body: eqPageData)
            } else {
                Self.sendNotFound(connection)
            }
        case "/api/compressor" where method == "GET":
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let dto = self.makeCompressorState(path: path) {
                    Self.sendJSON(connection, dto)
                } else {
                    Self.sendNotFound(connection)
                }
            }
        case "/api/eq" where method == "GET":
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let dto = self.makeEQState(path: path) {
                    Self.sendJSON(connection, dto)
                } else {
                    Self.sendNotFound(connection)
                }
            }
        case "/api/state":
            Task { @MainActor [weak self] in
                guard let self else { return }
                Self.sendJSON(connection, self.makeState())
            }
        case "/api/levels":
            Task { @MainActor [weak self] in
                guard let self else { return }
                Self.sendJSON(connection, self.makeLevels())
            }
        default:
            if method == "GET", let data = webAssets[cleanPath] {
                let type = cleanPath.hasSuffix(".js") ? "text/javascript; charset=utf-8" : "application/octet-stream"
                Self.send(connection, status: 200, contentType: type, body: data)
                return
            }
            guard method == "POST", cleanPath.hasPrefix("/api/") else {
                Self.sendNotFound(connection)
                return
            }
            let action = String(cleanPath.dropFirst(5))
            Task { @MainActor [weak self] in
                self?.perform(action: action, body: body)
                Self.sendJSON(connection, WebOKDTO())
            }
        }
    }

    // MARK: - Действия и состояние (MainActor)

    private func perform(action: String, body: Data) {
        let decoder = JSONDecoder()
        switch action {
        case "volume":
            if let req = try? decoder.decode(WebVolumeRequest.self, from: body), let id = outputID(at: req.index) {
                mixer.setVolume(outputID: id, value: req.value)
            }
        case "mute":
            if let req = try? decoder.decode(WebMuteRequest.self, from: body), let id = outputID(at: req.index) {
                mixer.setMuted(outputID: id, muted: req.muted)
            }
        case "dim":
            mixer.toggleDim()
        case "mono":
            mixer.toggleMono()
        case "speakerB":
            mixer.toggleSpeakerB()
        case "phantom":
            if let req = try? decoder.decode(WebIndexRequest.self, from: body), let id = inputID(at: req.index) {
                mixer.togglePhantom(inputID: id)
            }
        case "instrument":
            if let req = try? decoder.decode(WebIndexRequest.self, from: body), let id = inputID(at: req.index) {
                mixer.toggleInstrument(inputID: id)
            }
        case "input-name":
            if let req = try? decoder.decode(WebInputNameRequest.self, from: body), let id = inputID(at: req.index) {
                settings.updateInput(id) { $0.name = req.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        case "send-volume":
            if let req = try? decoder.decode(WebSendVolumeRequest.self, from: body), let id = sendID(at: req.index) {
                mixer.setSendVolume(id: id, value: req.value)
            }
        case "send-mute":
            if let req = try? decoder.decode(WebSendMuteRequest.self, from: body), let id = sendID(at: req.index) {
                mixer.setSendMuted(id: id, muted: req.muted)
            }
        case "compressor":
            if let req = try? decoder.decode(WebPanelActionRequest.self, from: body) {
                performCompressor(req)
            }
        case "eq":
            if let req = try? decoder.decode(WebPanelActionRequest.self, from: body) {
                performEQ(req)
            }
        case "settings":
            if let req = try? decoder.decode(WebSettingsUpdateRequest.self, from: body) {
                if let buttons = req.buttons { settings.webShowButtons = buttons }
                if let inputs = req.inputs { settings.webShowInputs = inputs }
                if let levels = req.levels { settings.webShowLevels = levels }
                if let mute = req.mute { settings.showMuteButtons = mute }
            }
        default:
            break
        }
    }

    private func performCompressor(_ req: WebPanelActionRequest) {
        guard let target = panelTarget(bus: req.bus, index: req.index) else { return }
        let compressorTarget = CompressorTarget(bus: target.bus, id: target.id)
        switch req.action {
        case "param":
            guard let name = req.name,
                  let parameter = CompressorParameter(rawValue: name),
                  let value = req.value else { return }
            mixer.setCompressorParameter(compressorTarget, parameter: parameter, value: value)
        case "power":
            guard let enabled = req.enabled else { return }
            mixer.setCompressorEnabled(compressorTarget, enabled: enabled)
        default:
            break
        }
    }

    private func performEQ(_ req: WebPanelActionRequest) {
        guard let target = panelTarget(bus: req.bus, index: req.index) else { return }
        let eqTarget = EQTarget(bus: target.bus, id: target.id)
        switch req.action {
        case "param":
            guard let name = req.name,
                  let parameter = EQParameter(rawValue: name),
                  let value = req.value else { return }
            mixer.setEQParameter(eqTarget, parameter, value: value)
        case "power":
            guard let enabled = req.enabled else { return }
            mixer.setEQEnabled(eqTarget, enabled: enabled)
        case "lowcut":
            guard let enabled = req.enabled else { return }
            mixer.setLowCutEnabled(eqTarget, enabled: enabled)
        default:
            break
        }
    }

    private func panelTarget(bus: String, index: Int) -> (bus: EQBus, id: UUID)? {
        switch bus {
        case "input":
            guard let id = inputID(at: index) else { return nil }
            return (.input, id)
        case "output":
            guard let id = outputID(at: index) else { return nil }
            return (.output, id)
        default:
            return nil
        }
    }

    private func outputID(at index: Int) -> UUID? {
        settings.outputs.indices.contains(index) ? settings.outputs[index].id : nil
    }

    private func inputID(at index: Int) -> UUID? {
        settings.inputs.indices.contains(index) ? settings.inputs[index].id : nil
    }

    private func sendID(at index: Int) -> UUID? {
        settings.sends.indices.contains(index) ? settings.sends[index].id : nil
    }

    private func makeState() -> WebStateDTO {
        let inputs = settings.inputs.enumerated().map { i, config in
            let live = state.input(config.id)
            return WebInputDTO(
                index: i,
                name: settings.inputLabel(for: config.id),
                has48v: config.type.hasPhantom,
                hasInst: config.type.hasInstrument,
                show: config.showInPopover,
                showInMain: config.showInMain,
                hasCompressor: settings.showInputCompressor && config.type.showsCompressor,
                compressorOn: live.compressor.enabled,
                hasEQ: settings.showInputEQ,
                eqOn: live.eq.enabled,
                phantom: live.phantom,
                instrument: live.instrument
            )
        }
        let outputs = settings.outputs.enumerated().map { i, config in
            let live = state.output(config.id)
            return WebOutputDTO(
                index: i,
                name: settings.outputName(for: config.id),
                show: config.showInMain,
                value: live.value,
                db: FaderMath.db(for: live.value),
                muted: live.muted,
                hasCompressor: settings.showOutputCompressor,
                compressorOn: live.compressor.enabled,
                hasEQ: settings.showOutputEQ,
                eqOn: live.eq.enabled
            )
        }
        let sends = settings.sends.enumerated().map { i, config in
            let live = state.send(config.id)
            return WebSendDTO(
                index: i,
                name: settings.sendName(for: config.id),
                show: config.showInMain,
                value: live.value,
                db: live.db,
                muted: live.muted
            )
        }
        return WebStateDTO(
            connected: state.isConnected,
            device: state.deviceName,
            dim: state.dimOn,
            mono: state.monoOn,
            speakerB: state.speakerBOn,
            settings: WebSettingsDTO(
                buttons: settings.webShowButtons,
                inputs: settings.webShowInputs,
                levels: settings.webShowLevels,
                mute: settings.showMuteButtons
            ),
            showDim: settings.showDim,
            showMono: settings.showMono,
            showSpeakerB: settings.showSpeakerB,
            inputs: inputs,
            outputs: outputs,
            sends: sends
        )
    }

    private func makeCompressorState(path: String) -> WebCompressorStateDTO? {
        guard let bus = Self.queryValue(path, "bus"),
              let index = Self.queryValue(path, "index").flatMap(Int.init),
              let target = panelTarget(bus: bus, index: index) else { return nil }

        let compressor: CompressorState
        let level: Double
        let name: String
        switch target.bus {
        case .input:
            compressor = state.input(target.id).compressor
            level = state.level(target.id)
            name = settings.inputLabel(for: target.id)
        case .output:
            compressor = state.output(target.id).compressor
            level = state.outputLevel(target.id)
            name = settings.outputName(for: target.id)
        }
        let reduction = compressor.gainReduction(forInputLevel: level)
        return WebCompressorStateDTO(
            name: name,
            isOutput: target.bus == .output,
            enabled: compressor.enabled,
            params: WebCompressorParamsDTO(
                threshold: compressor.threshold,
                ratio: compressor.ratio,
                attack: compressor.attack,
                release: compressor.release,
                gain: compressor.gain
            ),
            level: level,
            reduction: reduction,
            output: level + compressor.gain - reduction
        )
    }

    private func makeEQState(path: String) -> WebEQStateDTO? {
        guard let bus = Self.queryValue(path, "bus"),
              let index = Self.queryValue(path, "index").flatMap(Int.init),
              let target = panelTarget(bus: bus, index: index) else { return nil }

        let eq: EQState
        let name: String
        switch target.bus {
        case .input:
            eq = state.input(target.id).eq
            name = settings.inputLabel(for: target.id)
        case .output:
            eq = state.output(target.id).eq
            name = settings.outputName(for: target.id)
        }
        return WebEQStateDTO(
            name: name,
            enabled: eq.enabled,
            band1Type: eq.band1Type,
            band1Gain: eq.band1Gain,
            band1Freq: eq.band1Freq,
            band1Q: eq.band1Q,
            band2Gain: eq.band2Gain,
            band2Freq: eq.band2Freq,
            band2Q: eq.band2Q,
            band3Type: eq.band3Type,
            band3Gain: eq.band3Gain,
            band3Freq: eq.band3Freq,
            band3Q: eq.band3Q,
            lowCutEnabled: eq.lowCutEnabled,
            lowCutSlope: eq.lowCutSlope,
            lowCutFreq: eq.lowCutFreq
        )
    }

    nonisolated private static func queryValue(_ path: String, _ name: String) -> String? {
        URLComponents(string: path)?.queryItems?.first(where: { $0.name == name })?.value
    }

    private func makeLevels() -> WebLevelsDTO {
        let inputs = settings.inputs.filter(\.showInMain)
        return WebLevelsDTO(
            levels: inputs.map { state.level($0.id) },
            names: inputs.map { settings.inputLabel(for: $0.id) }
        )
    }

    // MARK: - Ответы

    nonisolated private static func sendJSON<T: Encodable>(_ connection: NWConnection, _ value: T) {
        let data = (try? JSONEncoder().encode(value)) ?? Data("{}".utf8)
        send(connection, status: 200, contentType: "application/json", body: data)
    }

    nonisolated private static func sendNotFound(_ connection: NWConnection) {
        send(connection, status: 404, contentType: "text/plain", body: Data("Not found".utf8))
    }

    nonisolated private static func send(_ connection: NWConnection, status: Int, contentType: String, body: Data) {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 404: reason = "Not Found"
        default: reason = "Error"
        }
        let head = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var data = Data(head.utf8)
        data.append(body)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
