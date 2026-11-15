import Cocoa
import ApplicationServices

/// Перехватывает аппаратные клавиши громкости/Mute, а также комбинации,
/// назначенные пользователем в настройках (громкость, Mute, Mono, переключение
/// выхода), пока TotalMix запущен и подключён, и вызывает команды `MixerService`
/// вместо системной громкости macOS.
/// Требует разрешение «Специальные возможности»; без него повторяет попытку каждые 5 секунд.
@MainActor
final class VolumeKeyMonitor {
    private enum VolumeAction {
        case up
        case down
        case mute
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var keyTap: CFMachPort?
    private var keyTapSource: CFRunLoopSource?
    private var isStarted = false

    private let settings: AppSettings
    private let state: MixerState
    private let mixer: MixerService
    private let totalMix: TotalMixDetector

    var onVolumeChanged: (() -> Void)?
    var onMuteChanged: (() -> Void)?
    var onVolumeKeyOutputChanged: (() -> Void)?

    private static let NX_KEYTYPE_SOUND_UP = 0
    private static let NX_KEYTYPE_SOUND_DOWN = 1
    private static let NX_KEYTYPE_MUTE = 7
    private static let NX_SUBTYPE_AUX_CONTROL_BUTTONS: Int16 = 8
    private static let NX_SYSDEFINED_EVENT_TYPE: UInt32 = 14
    private static let retryInterval: Duration = .seconds(5)

    init(settings: AppSettings, state: MixerState, mixer: MixerService, totalMix: TotalMixDetector) {
        self.settings = settings
        self.state = state
        self.mixer = mixer
        self.totalMix = totalMix
    }

    var isAuthorized: Bool {
        AccessibilityPermission.isGranted
    }

    func start() {
        guard !isStarted else { return }

        guard AccessibilityPermission.isGranted else {
            retryStart()
            return
        }

        guard let tap = createTap(mask: CGEventMask(1) << CGEventMask(Self.NX_SYSDEFINED_EVENT_TYPE), handler: .system),
              let keyTap = createTap(mask: (1 << CGEventMask(CGEventType.keyDown.rawValue)) | (1 << CGEventMask(CGEventType.keyUp.rawValue)), handler: .keys)
        else {
            retryStart()
            return
        }

        eventTap = tap
        self.keyTap = keyTap
        install(tap, into: &runLoopSource)
        install(keyTap, into: &keyTapSource)
        CGEvent.tapEnable(tap: tap, enable: true)
        CGEvent.tapEnable(tap: keyTap, enable: true)
        isStarted = true
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        for source in [runLoopSource, keyTapSource].compactMap({ $0 }) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        for tap in [eventTap, keyTap].compactMap({ $0 }) {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        eventTap = nil
        keyTap = nil
        runLoopSource = nil
        keyTapSource = nil
    }

    private func retryStart() {
        Task { [weak self] in
            try? await Task.sleep(for: Self.retryInterval)
            guard let self, !self.isStarted else { return }
            self.start()
        }
    }

    // MARK: - Event taps

    private enum TapHandler: Int {
        case system = 1
        case keys = 2
    }

    /// Контекст C-колбэка: указатель на монитор и тип tap'а. Монитор живёт столько же,
    /// сколько `AppCoordinator`, а tap'ы снимаются в `stop()`, поэтому unretained-ссылка безопасна.
    private final class TapContext {
        unowned let monitor: VolumeKeyMonitor
        let handler: TapHandler
        init(monitor: VolumeKeyMonitor, handler: TapHandler) {
            self.monitor = monitor
            self.handler = handler
        }
    }

    private var tapContexts: [TapContext] = []

    private func createTap(mask: CGEventMask, handler: TapHandler) -> CFMachPort? {
        let context = TapContext(monitor: self, handler: handler)
        tapContexts.append(context)
        return CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let context = Unmanaged<TapContext>.fromOpaque(userInfo).takeUnretainedValue()
                // Tap'ы добавлены в главный run loop, поэтому колбэк всегда на главном потоке.
                let consume = MainActor.assumeIsolated {
                    context.handler == .system
                        ? context.monitor.handleSystemEvent(type: type, event: event)
                        : context.monitor.handleKey(type: type, event: event)
                }
                return consume ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(context).toOpaque()
        )
    }

    private func install(_ tap: CFMachPort, into source: inout CFRunLoopSource?) {
        if let s = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) {
            source = s
            CFRunLoopAddSource(CFRunLoopGetMain(), s, .commonModes)
        }
    }

    /// macOS отключает tap, если колбэк отвечает слишком долго; включаем обратно.
    private func reenableIfDisabled(_ type: CGEventType, tap: CFMachPort?) -> Bool {
        guard type == .tapDisabledByTimeout || type == .tapDisabledByUserInput else { return false }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return true
    }

    private var canHandleKeys: Bool {
        totalMix.isRunning && state.isConnected
    }

    // MARK: - Обработка событий (true — событие поглощено и не уходит в систему)

    /// Медиа-клавиши (громкость/Mute) приходят как системные события NX_SYSDEFINED.
    private func handleSystemEvent(type: CGEventType, event: CGEvent) -> Bool {
        if reenableIfDisabled(type, tap: eventTap) { return false }

        guard type.rawValue == Self.NX_SYSDEFINED_EVENT_TYPE,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == Self.NX_SUBTYPE_AUX_CONTROL_BUTTONS
        else {
            return false
        }

        let data1 = nsEvent.data1
        let keyCode = Int((data1 & 0xFFFF0000) >> 16)
        let keyFlags = data1 & 0x0000FFFF
        let isKeyDown = ((keyFlags & 0xFF00) >> 8) == 0x0A

        let action: VolumeAction
        switch keyCode {
        case Self.NX_KEYTYPE_SOUND_UP: action = .up
        case Self.NX_KEYTYPE_SOUND_DOWN: action = .down
        case Self.NX_KEYTYPE_MUTE: action = .mute
        default: return false
        }

        guard canHandleKeys else { return false }

        if isKeyDown {
            DispatchQueue.main.async { [weak self] in
                self?.handle(action)
            }
        }
        return true
    }

    /// Обычные клавиши: комбинации, назначенные пользователем в настройках
    /// (громкость, Mute, Mono, переключение выхода). Аппаратные клавиши громкости
    /// приходят отдельными системными событиями и обрабатываются выше.
    private func handleKey(type: CGEventType, event: CGEvent) -> Bool {
        if reenableIfDisabled(type, tap: keyTap) { return false }
        guard type == .keyDown else { return false }
        // Пока в настройках записывается новая комбинация, перехват не должен
        // её «съедать»: иначе назначить уже занятую комбинацию невозможно.
        guard !settings.isRecordingHotkey else { return false }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = event.flags.hotkeyModifiers

        for action in HotkeyAction.allCases {
            let hotkey = settings.hotkey(for: action)
            guard hotkey.matches(keyCode: keyCode, modifiers: modifiers) else { continue }
            guard canPerform(action) else { return false }
            DispatchQueue.main.async { [weak self] in
                self?.perform(action)
            }
            return true
        }

        return false
    }

    /// Действие можно выполнить только когда TotalMix действительно управляем:
    /// иначе комбинация не перехватывается и работает как обычно в системе.
    private func canPerform(_ action: HotkeyAction) -> Bool {
        action.requiresConnection ? canHandleKeys : totalMix.isRunning
    }

    private func perform(_ action: HotkeyAction) {
        switch action {
        case .volumeUp: handle(.up)
        case .volumeDown: handle(.down)
        case .mute: handle(.mute)
        case .nextOutput: switchVolumeKeyOutput(by: 1)
        case .previousOutput: switchVolumeKeyOutput(by: -1)
        case .mono: toggleMono()
        }
    }

    private func handle(_ action: VolumeAction) {
        guard state.isConnected, let outputID = settings.volumeKeyOutput?.id else { return }
        switch action {
        case .up:
            mixer.stepVolume(outputID: outputID, byDB: settings.volumeStepDB)
            onVolumeChanged?()
        case .down:
            mixer.stepVolume(outputID: outputID, byDB: -settings.volumeStepDB)
            onVolumeChanged?()
        case .mute:
            if settings.muteKeyAction == .dim {
                mixer.toggleDim()
            } else {
                mixer.toggleMute(outputID: outputID)
                onMuteChanged?()
            }
        }
    }

    private func switchVolumeKeyOutput(by offset: Int) {
        guard state.isConnected else { return }
        settings.selectAdjacentVolumeKeyOutput(offset: offset)
        if settings.muteOtherOutputsOnSwitch, let outputID = settings.volumeKeyOutput?.id {
            mixer.muteOtherOutputs(except: outputID)
        }
        onVolumeKeyOutputChanged?()
    }

    private func toggleMono() {
        guard state.isConnected else { return }
        mixer.toggleMono()
    }
}

private extension CGEventFlags {
    /// Модификаторы события в терминах `NSEvent`; служебные флаги (fn, Caps Lock,
    /// NumPad) отбрасываем, чтобы комбинации не зависели от них.
    var hotkeyModifiers: NSEvent.ModifierFlags {
        var modifiers: NSEvent.ModifierFlags = []
        if contains(.maskCommand) { modifiers.insert(.command) }
        if contains(.maskAlternate) { modifiers.insert(.option) }
        if contains(.maskControl) { modifiers.insert(.control) }
        if contains(.maskShift) { modifiers.insert(.shift) }
        return modifiers
    }
}
