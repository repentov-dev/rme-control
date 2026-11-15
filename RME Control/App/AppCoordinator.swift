import AppKit
import Combine

/// Composition root приложения: единственное место, где создаются сервисы и ViewModel
/// и связываются между собой. Координатор живёт столько же, сколько приложение
/// (его держит `AppDelegate`), поэтому каждый сервис существует в одном экземпляре
/// без глобальных синглтонов — зависимости передаются через init.
@MainActor
final class AppCoordinator {
    private static let stateSyncInterval: TimeInterval = 5.0
    private static let deviceHUDDuration: TimeInterval = 2.0
    private static let initialSyncHUDSuppression: TimeInterval = 1.5
    private static let dimVolumeHUDSuppression: TimeInterval = 0.6
    private static let totalMixLaunchDelay: Duration = .seconds(2)

    // MARK: - Сервисы

    private let settings: AppSettings
    private let state: MixerState
    private let osc: OSCClient
    private let mixer: MixerService
    private let channelScanner: ChannelScanner
    private let connectionMonitor: ConnectionMonitor
    private let totalMix: TotalMixDetector
    private let keyMonitor: VolumeKeyMonitor
    private let webServer: WebServer

    // MARK: - UI

    private let mixerViewModel: MixerViewModel
    private let hud: HudPresenter
    private let statusBar = StatusBarController()
    private let windows: WindowManager

    // MARK: - Подавление HUD при запуске и после (от)подключения устройства

    private var syncTimer: Timer?
    private var suppressLaunchHUD = true
    private var suppressHUDUntil = Date.distantPast
    private var suppressStateHUDUntil = Date.distantPast
    private var hudSuppressed: Bool {
        suppressLaunchHUD || Date() < suppressHUDUntil
    }
    /// HUD об изменениях из TotalMix не показываются во время стартовой синхронизации.
    private var stateHUDSuppressed: Bool {
        hudSuppressed || Date() < suppressStateHUDUntil
    }
    private var didInitialSync = false
    private var pendingVolumeHUD: DispatchWorkItem?
    private var suppressVolumeHUDUntil = Date.distantPast
    private var cancellables = Set<AnyCancellable>()
    private var screenObserver: NSObjectProtocol?

    init(storage: StorageProtocol = UserDefaultsStorage()) {
        let settings = AppSettings(storage: storage)
        let state = MixerState()
        let osc = OSCClient(storage: storage)
        let oscMonitor = OSCMonitor()
        let mixer = MixerService(osc: osc, settings: settings, state: state)
        let channelScanner = ChannelScanner(osc: osc)
        let webServer = WebServer(settings: settings, state: state, mixer: mixer)
        let totalMix = TotalMixDetector()
        let mixerViewModel = MixerViewModel(settings: settings, state: state, mixer: mixer)

        self.settings = settings
        self.state = state
        self.osc = osc
        self.mixer = mixer
        self.channelScanner = channelScanner
        self.webServer = webServer
        self.totalMix = totalMix
        self.mixerViewModel = mixerViewModel
        osc.onActivity = { activity in
            oscMonitor.record(activity)
        }
        connectionMonitor = ConnectionMonitor(
            settings: settings,
            state: state,
            lastReceiveTime: { [weak osc] in osc?.lastReceiveTime ?? .distantPast },
            onConnected: { [weak mixer] in mixer?.requestState() }
        )
        keyMonitor = VolumeKeyMonitor(settings: settings, state: state, mixer: mixer, totalMix: totalMix)
        hud = HudPresenter(viewModel: mixerViewModel)
        windows = WindowManager(
            mixerViewModel: mixerViewModel,
            oscMonitor: oscMonitor,
            makeSettingsViewModel: {
                SettingsViewModel(settings: settings, mixer: mixer, osc: osc, webServer: webServer)
            },
            makeChannelDiscoveryViewModel: {
                ChannelDiscoveryViewModel(scanner: channelScanner, mixer: mixer, settings: settings)
            },
            makeSetupAssistantViewModel: {
                SetupAssistantViewModel(
                    discovery: ChannelDiscoveryViewModel(scanner: channelScanner, mixer: mixer, settings: settings),
                    settings: settings
                )
            }
        )
    }

    // MARK: - Жизненный цикл

    func start() {
        connectionMonitor.start()
        NSApplication.shared.setActivationPolicy(.accessory)

        statusBar.install { [weak self] in
            self?.hud.toggleMainPopover()
        }
        statusBar.onOpenSettings = { [weak self] in
            self?.windows.openSettings()
        }
        hud.attach(
            statusItem: statusBar.statusItem,
            onToggleMeters: { [weak self] in
                self?.windows.toggleMetersPanel()
            },
            onOpenSettings: { [weak self] in
                self?.windows.openSettings()
            },
            onOpenCompressor: { [weak self] target in
                self?.windows.openCompressor(target: target)
            },
            onOpenEQ: { [weak self] target in
                self?.windows.openEQ(target)
            }
        )

        // Мастер показываем только при первом запуске: сразу отмечаем его
        // пройденным, чтобы он не вернулся после перезапуска или удаления каналов.
        let showsSetupAssistant = settings.needsSetup
        settings.completeSetup()
        if showsSetupAssistant {
            // Даём приложению завершить запуск, чтобы окно мастера встало поверх
            // уже созданной иконки в строке меню.
            DispatchQueue.main.async { [weak self] in
                self?.windows.openSetupAssistant()
            }
        }

        bindDeviceEvents()
        bindStateHUD()
        bindOSC()

        mixer.requestState()

        syncTimer = Timer.scheduledTimer(withTimeInterval: Self.stateSyncInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.state.isConnected else { return }
                self.mixer.requestState()
            }
        }

        bindKeyMonitor()
        // На первом запуске разрешение спрашивает мастер: не показываем два окна сразу.
        if !keyMonitor.isAuthorized && !settings.needsSetup {
            AccessibilityPermission.prompt()
        }

        bindDimIndicator()
        bindWebServer()
        observeSystemEvents()
    }

    func stop() {
        syncTimer?.invalidate()
        syncTimer = nil
        pendingVolumeHUD?.cancel()
        pendingVolumeHUD = nil
        connectionMonitor.stop()
        keyMonitor.stop()
        osc.stopListening()
        webServer.stop()
        hud.closeAll()
        windows.closeCompressor()
        windows.closeEQ()
        windows.closeOSCMonitor()
        windows.hideDimIndicator()
    }

    // MARK: - Связи

    /// HUD о клиппинге и (от)подключении устройства.
    private func bindDeviceEvents() {
        mixer.clipTrigger
            .sink { [weak self] inputID in
                guard let self, !self.hudSuppressed else { return }
                self.hud.showClipIndicator(inputID: inputID)
            }
            .store(in: &cancellables)
        mixer.deviceConnectedTrigger
            .sink { [weak self] device in
                self?.showDeviceHUD(.deviceConnected(device))
            }
            .store(in: &cancellables)
        mixer.deviceDisconnectedTrigger
            .sink { [weak self] device in
                self?.showDeviceHUD(.deviceDisconnected(device))
            }
            .store(in: &cancellables)
    }

    private func showDeviceHUD(_ kind: HUDStatusKind) {
        guard !suppressLaunchHUD else { return }
        suppressHUDUntil = Date().addingTimeInterval(Self.deviceHUDDuration)
        hud.showStatusHUD(kind: kind, duration: Self.deviceHUDDuration)
    }

    /// HUD, когда громкость, Dim или Mono меняют в TotalMix или в приложении.
    private func bindStateHUD() {
        mixer.outputVolumeChangedTrigger
            .sink { [weak self] outputID in
                self?.scheduleVolumeHUD(outputID: outputID)
            }
            .store(in: &cancellables)
        mixer.dimChangedTrigger
            .sink { [weak self] _ in
                guard let self, !self.stateHUDSuppressed else { return }
                self.suppressVolumeHUDForDim()
                self.hud.updateDimMonoHUD(kind: .dim)
            }
            .store(in: &cancellables)
        mixer.monoChangedTrigger
            .sink { [weak self] _ in
                guard let self, !self.stateHUDSuppressed else { return }
                self.hud.updateDimMonoHUD(kind: .mono)
            }
            .store(in: &cancellables)
    }

    /// Показывает HUD громкости сразу, но через следующий цикл run loop:
    /// так Dim из того же пакета TotalMix успевает отменить его без видимой задержки.
    private func scheduleVolumeHUD(outputID: UUID) {
        guard !stateHUDSuppressed, Date() >= suppressVolumeHUDUntil else { return }
        pendingVolumeHUD?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.stateHUDSuppressed, Date() >= self.suppressVolumeHUDUntil else { return }
            self.pendingVolumeHUD = nil
            self.hud.showVolumeHUD(outputID: outputID, immediate: true)
        }
        pendingVolumeHUD = work
        DispatchQueue.main.async(execute: work)
    }

    private func suppressVolumeHUDForDim() {
        pendingVolumeHUD?.cancel()
        pendingVolumeHUD = nil
        suppressVolumeHUDUntil = Date().addingTimeInterval(Self.dimVolumeHUDSuppression)
    }

    /// Входящие OSC-сообщения → MixerService. Первое сообщение снимает подавление HUD при запуске.
    private func bindOSC() {
        osc.onFloat = { [weak self] address, value in
            guard let self else { return }
            self.mixer.handleOSCFloat(address, value)
            if !self.didInitialSync {
                self.didInitialSync = true
                self.suppressLaunchHUD = false
                self.suppressStateHUDUntil = Date().addingTimeInterval(Self.initialSyncHUDSuppression)
            }
        }
        osc.onString = { [weak self] address, value in
            self?.mixer.handleOSCString(address, value)
        }
        osc.onMessage = { [weak self] address, floatValue, stringValue in
            self?.channelScanner.handle(address, floatValue: floatValue, stringValue: stringValue)
        }
        osc.startListening()
    }

    private func bindKeyMonitor() {
        keyMonitor.start()
        keyMonitor.onVolumeChanged = { [weak self] in
            guard let self, let id = self.settings.volumeKeyOutput?.id else { return }
            self.hud.showVolumeHUD(outputID: id, immediate: true)
        }
        keyMonitor.onMuteChanged = { [weak self] in
            self?.hud.updateDimMonoHUD(kind: .mute)
        }
        keyMonitor.onVolumeKeyOutputChanged = { [weak self] in
            self?.hud.showOutputPickerHUD()
        }
    }

    private func bindDimIndicator() {
        let state = state
        observe({ state.dimOn }) { [weak self] isOn in
            self?.windows.updateDimIndicator(isOn: isOn)
        }
    }

    private func bindWebServer() {
        let settings = settings
        observe({ (settings.webServerEnabled, settings.webServerPort) }) { [weak self] enabled, port in
            if enabled {
                self?.webServer.start(port: UInt16(clamping: port))
            } else {
                self?.webServer.stop()
            }
        }
    }

    /// Смена конфигурации экранов двигает индикатор DIM; запуск TotalMix запрашивает состояние.
    private func observeSystemEvents() {
        screenObserver = SystemNotifications.observeScreenParameterChanges { [weak self] in
            self?.windows.positionDimIndicator()
        }

        totalMix.onLaunch = { [weak self] in
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.totalMixLaunchDelay)
                self?.mixer.requestState()
            }
        }
    }
}
