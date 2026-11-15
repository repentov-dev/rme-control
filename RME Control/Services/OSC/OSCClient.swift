import Foundation
import Network
import Darwin

/// Отправка OSC-команд. Сервисы зависят от протокола, а не от сетевой реализации,
/// поэтому в тестах вместо сети можно подставить фейк.
@MainActor
protocol OSCSending: AnyObject {
    func send(_ address: String, _ value: Float)
}

/// UDP-транспорт OSC для связи с TotalMix FX.
/// Слушает входящие пакеты на `recvPort` через `NWListener` и отправляет команды
/// на `host:sendPort` обычным UDP-сокетом.
///
/// Отправка специально сделана через `sendto`, а не через `NWConnection`: если TotalMix
/// не запущен, порт закрыт и на отправленный датаграм приходит ICMP «port unreachable».
/// `NWConnection` в паре с активным `NWListener` уходит после этого в цикл на 100% ядра
/// (заметно как ~6 Вт и «высокое потребление энергии» в macOS). UDP-сокет такие ошибки
/// просто игнорирует, что для OSC и нужно: доставка не гарантируется в любом случае.
///
/// Все сетевые колбэки приходят на главную очередь, поэтому состояние клиента
/// изолировано на `MainActor` и не требует блокировок.
/// Хост и порты хранятся в `StorageProtocol`.
@MainActor
final class OSCClient: OSCSending {
    static let defaultHost = "127.0.0.1"
    static let defaultSendPort: UInt16 = 7001
    static let defaultRecvPort: UInt16 = 9001

    private let storage: StorageProtocol
    private(set) var currentHost: String
    private(set) var currentSendPort: UInt16
    private(set) var currentRecvPort: UInt16

    private var listener: NWListener?
    /// Входящие «соединения» — по одному на каждого отправителя (обычно только TotalMix).
    private var inbound: [NWConnection] = []

    // MARK: - Отправка (обычный UDP-сокет)

    /// Готовый `sockaddr` получателя в виде сырых байт: так его можно безопасно
    /// хранить и передавать между потоками (для IPv4 и IPv6 длина разная).
    private struct ResolvedAddress: Sendable {
        let family: Int32
        let bytes: [UInt8]
    }

    private var sendSocket: Int32 = -1
    private var socketFamily: Int32 = 0
    private var sendAddress: [UInt8] = []
    private var sendAddressLength: socklen_t = 0
    private var resolvedHost: String?
    private var resolvedPort: UInt16 = 0
    private var isResolving = false
    /// Последний пакет, который не удалось отправить, пока резолвилось имя хоста.
    private var pendingPacket: [UInt8]?

    /// Входящее сообщение с float-аргументом.
    var onFloat: ((String, Float) -> Void)?
    /// Входящее сообщение со строковым аргументом.
    var onString: ((String, String) -> Void)?
    /// Любое разобранное входящее или отправленное сообщение — для OSC-монитора.
    var onActivity: ((OSCActivity) -> Void)?
    /// Каждое входящее сообщение целиком. Нужен сканеру каналов: ему важны
    /// адреса, которых ещё нет в настройках (`/input/21/name` и т. п.).
    var onMessage: ((_ address: String, _ floatValue: Float?, _ stringValue: String?) -> Void)?

    /// Время последнего полученного сообщения — по нему определяется, жив ли TotalMix.
    private(set) var lastReceiveTime = Date.distantPast

    init(storage: StorageProtocol) {
        self.storage = storage
        currentHost = storage.string(for: .oscHost) ?? Self.defaultHost
        let sp = storage.integer(for: .oscSendPort)
        let rp = storage.integer(for: .oscRecvPort)
        currentSendPort = sp > 0 ? UInt16(sp) : Self.defaultSendPort
        currentRecvPort = rp > 0 ? UInt16(rp) : Self.defaultRecvPort
    }

    /// Меняет хост и порты, сохраняет их и перезапускает приём.
    func reconfigure(host: String, sendPort: UInt16, recvPort: UInt16) {
        stopListening()
        currentHost = host
        currentSendPort = sendPort
        currentRecvPort = recvPort
        storage.set(host, for: .oscHost)
        storage.set(Int(sendPort), for: .oscSendPort)
        storage.set(Int(recvPort), for: .oscRecvPort)
        startListening()
    }

    // MARK: - Приём

    func startListening() {
        guard listener == nil, let port = NWEndpoint.Port(rawValue: currentRecvPort) else { return }
        let parameters = NWParameters.udp
        parameters.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: parameters, on: port) else { return }

        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.accept(connection) }
        }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard case .failed = state else { return }
            MainActor.assumeIsolated {
                if let self, self.listener === listener {
                    self.listener?.cancel()
                    self.listener = nil
                }
            }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    func stopListening() {
        listener?.cancel()
        listener = nil
        inbound.forEach { $0.cancel() }
        inbound.removeAll()
        closeSendSocket()
        sendAddress = []
        sendAddressLength = 0
        resolvedHost = nil
        pendingPacket = nil
    }

    private func accept(_ connection: NWConnection) {
        inbound.append(connection)
        connection.start(queue: .main)
        receive(on: connection)
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let data, !data.isEmpty {
                    self.handle(packet: [UInt8](data))
                }
                if error == nil {
                    self.receive(on: connection)
                } else {
                    connection.cancel()
                    self.inbound.removeAll { $0 === connection }
                }
            }
        }
    }

    private func handle(packet: [UInt8]) {
        for msg in OSCCodec.parsePacket(packet) {
            lastReceiveTime = Date()
            onMessage?(msg.address, msg.floatValue, msg.stringValue)
            if let f = msg.floatValue {
                onActivity?(OSCActivity(direction: .incoming, address: msg.address, floatValue: f))
                onFloat?(msg.address, f)
            } else if let s = msg.stringValue {
                onActivity?(OSCActivity(direction: .incoming, address: msg.address, stringValue: s))
                onString?(msg.address, s)
            } else {
                onActivity?(OSCActivity(direction: .incoming, address: msg.address))
            }
        }
    }

    // MARK: - Отправка

    func send(_ address: String, _ value: Float) {
        onActivity?(OSCActivity(direction: .outgoing, address: address, floatValue: value))
        let packet = [UInt8](OSCCodec.encode(address: address, value: value))
        guard prepareAddress() else {
            // Имя хоста резолвится в фоне; отправим последний пакет, когда адрес будет готов.
            pendingPacket = packet
            return
        }
        pendingPacket = nil
        transmit(packet)
    }

    /// Проверяет, что адрес получателя готов. Для IP-адреса (обычный случай) готовит
    /// `sockaddr` сразу, для имени хоста запускает фоновый DNS-запрос.
    private func prepareAddress() -> Bool {
        if resolvedHost == currentHost, resolvedPort == currentSendPort, !sendAddress.isEmpty {
            return true
        }
        if let address = Self.numericAddress(host: currentHost, port: currentSendPort) {
            apply(address, host: currentHost, port: currentSendPort)
            return true
        }
        startResolution()
        return false
    }

    private func startResolution() {
        guard !isResolving else { return }
        isResolving = true
        let host = currentHost
        let port = currentSendPort
        Task { @MainActor [weak self] in
            let resolved = await Self.resolveAddress(host: host, port: port)
            guard let self else { return }
            self.isResolving = false
            guard self.currentHost == host, self.currentSendPort == port else {
                self.startResolution()
                return
            }
            if let resolved {
                self.apply(resolved, host: host, port: port)
                self.flushPending()
            } else {
                self.pendingPacket = nil
            }
        }
    }

    private func apply(_ address: ResolvedAddress, host: String, port: UInt16) {
        sendAddress = address.bytes
        sendAddressLength = socklen_t(address.bytes.count)
        resolvedHost = host
        resolvedPort = port
        ensureSocket(family: address.family)
    }

    private func flushPending() {
        guard let packet = pendingPacket else { return }
        pendingPacket = nil
        guard prepareAddress() else { return }
        transmit(packet)
    }

    private func transmit(_ packet: [UInt8]) {
        guard sendSocket >= 0, !sendAddress.isEmpty else { return }
        var storage = sockaddr_storage()
        sendAddress.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Void in
            withUnsafeMutableBytes(of: &storage) { destination in
                _ = raw.copyBytes(to: destination)
            }
        }
        let length = sendAddressLength
        withUnsafePointer(to: &storage) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                _ = packet.withUnsafeBytes { bytes in
                    sendto(sendSocket, bytes.baseAddress, bytes.count, 0, sockaddrPointer, length)
                }
            }
        }
    }

    private func ensureSocket(family: Int32) {
        if sendSocket >= 0, socketFamily == family { return }
        closeSendSocket()
        let descriptor = socket(family, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else { return }
        let flags = fcntl(descriptor, F_GETFL, 0)
        if flags >= 0 {
            _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)
        }
        sendSocket = descriptor
        socketFamily = family
    }

    private func closeSendSocket() {
        if sendSocket >= 0 {
            close(sendSocket)
        }
        sendSocket = -1
        socketFamily = 0
    }

    // MARK: - Резолвинг

    /// IP-адрес (v4 или v6) → готовый `sockaddr` без DNS.
    private nonisolated static func numericAddress(host: String, port: UInt16) -> ResolvedAddress? {
        var ipv4 = in_addr()
        if inet_pton(AF_INET, host, &ipv4) == 1 {
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = port.bigEndian
            address.sin_addr = ipv4
            let bytes = withUnsafeBytes(of: &address) { Array($0) }
            return ResolvedAddress(family: Int32(AF_INET), bytes: bytes)
        }

        var ipv6 = in6_addr()
        if inet_pton(AF_INET6, host, &ipv6) == 1 {
            var address = sockaddr_in6()
            address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            address.sin6_family = sa_family_t(AF_INET6)
            address.sin6_port = port.bigEndian
            address.sin6_addr = ipv6
            let bytes = withUnsafeBytes(of: &address) { Array($0) }
            return ResolvedAddress(family: Int32(AF_INET6), bytes: bytes)
        }
        return nil
    }

    /// Имя хоста → `sockaddr` через `getaddrinfo`. DNS-запрос уводится с главного потока.
    private nonisolated static func resolveAddress(host: String, port: UInt16) async -> ResolvedAddress? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: resolveSockaddr(host: host, port: port))
            }
        }
    }

    private nonisolated static func resolveSockaddr(host: String, port: UInt16) -> ResolvedAddress? {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_DGRAM
        hints.ai_protocol = IPPROTO_UDP

        var info: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &info) == 0, let first = info else {
            return nil
        }
        defer { freeaddrinfo(info) }

        // TotalMix слушает IPv4, поэтому IPv4-адрес предпочитаем: `localhost`
        // и многие имена сначала отдают IPv6 (`::1`), и пакет ушёл бы «в никуда».
        var fallback: ResolvedAddress?
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let node = cursor {
            if let address = node.pointee.ai_addr {
                let length = Int(node.pointee.ai_addrlen)
                if length > 0 {
                    let bytes = Array(UnsafeRawBufferPointer(start: address, count: length))
                    let family = Int32(address.pointee.sa_family)
                    let resolved = ResolvedAddress(family: family, bytes: bytes)
                    if family == AF_INET { return resolved }
                    if fallback == nil { fallback = resolved }
                }
            }
            cursor = node.pointee.ai_next
        }
        return fallback
    }
}
