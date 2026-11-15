import Foundation

/// Раз в секунду определяет, есть ли связь с пультом:
/// TotalMix считается живым, если за последние 3 секунды от него приходили OSC-сообщения,
/// а при `watchDeviceConnection` дополнительно должен быть подключён аудиоинтерфейс.
/// При появлении связи вызывает `onConnected` (запрос полного состояния).
@MainActor
final class ConnectionMonitor {
    static let checkInterval: TimeInterval = 1.0
    static let aliveTimeout: TimeInterval = 3.0

    private let settings: AppSettings
    private let state: MixerState
    private let lastReceiveTime: @MainActor () -> Date
    private let onConnected: @MainActor () -> Void
    private var timer: Timer?

    init(settings: AppSettings, state: MixerState, lastReceiveTime: @escaping @MainActor () -> Date, onConnected: @escaping @MainActor () -> Void) {
        self.settings = settings
        self.state = state
        self.lastReceiveTime = lastReceiveTime
        self.onConnected = onConnected
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func update() {
        let totalMixAlive = Date().timeIntervalSince(lastReceiveTime()) < Self.aliveTimeout
        let deviceOffline = settings.watchDeviceConnection && totalMixAlive && !state.devicePresent
        if state.deviceOffline != deviceOffline {
            state.deviceOffline = deviceOffline
        }
        let connected = totalMixAlive && (!settings.watchDeviceConnection || state.devicePresent)
        if connected != state.isConnected {
            state.isConnected = connected
            if connected {
                onConnected()
            }
        }
    }
}
