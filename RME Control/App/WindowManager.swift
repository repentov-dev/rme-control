import AppKit
import SwiftUI

/// Управляет дополнительными окнами приложения: плавающей панелью уровней,
/// индикатором DIM поверх всех окон и окном настроек (создаётся один раз и переиспользуется).
@MainActor
final class WindowManager {
    private var metersPanel: NSPanel?
    private var compressorPanel: NSPanel?
    private var compressorTarget: CompressorTarget?
    private var eqPanel: NSPanel?
    private var eqTarget: EQTarget?
    private var roomEQPanel: NSPanel?
    private var roomEQTarget: RoomEQTarget?
    private var roomCorrectionPanel: NSPanel?
    private var roomEQLoweredForMeasure = false
    private var roomCorrectionTarget: RoomEQTarget?
    private var dimIndicatorPanel: NSPanel?
    private var settingsWindow: NSWindow?
    private var oscMonitorWindow: OSCMonitorWindow?
    private var channelDiscoveryWindow: ChannelDiscoveryWindow?
    private var channelDiscoveryViewModel: ChannelDiscoveryViewModel?
    private var setupWindow: SetupAssistantWindow?
    private var setupViewModel: SetupAssistantViewModel?

    private let mixerViewModel: MixerViewModel
    private let oscMonitor: OSCMonitor
    private let makeSettingsViewModel: () -> SettingsViewModel
    private let makeChannelDiscoveryViewModel: () -> ChannelDiscoveryViewModel
    private let makeSetupAssistantViewModel: () -> SetupAssistantViewModel

    init(mixerViewModel: MixerViewModel, oscMonitor: OSCMonitor,
         makeSettingsViewModel: @escaping () -> SettingsViewModel,
         makeChannelDiscoveryViewModel: @escaping () -> ChannelDiscoveryViewModel,
         makeSetupAssistantViewModel: @escaping () -> SetupAssistantViewModel) {
        self.mixerViewModel = mixerViewModel
        self.oscMonitor = oscMonitor
        self.makeSettingsViewModel = makeSettingsViewModel
        self.makeChannelDiscoveryViewModel = makeChannelDiscoveryViewModel
        self.makeSetupAssistantViewModel = makeSetupAssistantViewModel
    }

    // MARK: - Анимация появления

    private static let compressorFrameName = "CompressorPanelFrame"
    private static let eqFrameName = "EQPanelFrame"
    private static let roomEQFrameName = "RoomEQPanelFrame"
    private static let roomCorrectionFrameName = "RoomCorrectionPanelFrame"
    private static let metersFrameName = "MetersPanelFrame"

    /// Восстанавливает сохранённое положение окна. Если сохранённого положения
    /// нет или оно оказалось за пределами экранов, ставит окно по умолчанию.
    private func restoreFrame(of panel: NSPanel, named name: String, fallback: NSRect) {
        let restored = panel.setFrameUsingName(name)
        panel.setFrameAutosaveName(name)
        let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(panel.frame) }
        if !restored || !onScreen {
            panel.setFrame(fallback, display: false)
        }
    }

    private func saveFrame(of panel: NSPanel, named name: String) {
        panel.saveFrame(usingName: name)
    }

    private func showPanel(_ panel: NSPanel) {
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            panel.animator().alphaValue = 1
        }
    }

    private func hidePanel(_ panel: NSPanel) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    // MARK: - Панель уровней

    func toggleMetersPanel() {
        if let panel = metersPanel, panel.isVisible {
            closeMetersPanel()
            return
        }
        let size = LevelsView.contentSize(for: mixerViewModel)
        let hosting = DraggableHostingView(rootView: LevelsView(viewModel: mixerViewModel, onClose: { [weak self] in
            self?.closeMetersPanel()
        }, onResize: { [weak self] size in
            self?.resizeMetersPanel(to: size)
        }))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.sizingOptions = []
        let panel = PanelFactory.makeOverlayPanel(MetersPanel.self, contentView: hosting, size: size)
        panel.hidesOnDeactivate = false

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        restoreFrame(
            of: panel,
            named: Self.metersFrameName,
            fallback: NSRect(x: screen.maxX - size.width - 20, y: screen.maxY - size.height - 60, width: size.width, height: size.height)
        )
        panel.setContentSize(size)
        showPanel(panel)
        metersPanel = panel
    }

    private func closeMetersPanel() {
        if let panel = metersPanel {
            saveFrame(of: panel, named: Self.metersFrameName)
            hidePanel(panel)
        }
        metersPanel = nil
    }

    /// Подгоняет панель уровней под содержимое (число строк, ширину подписей),
    /// сохраняя левый и верхний края на месте.
    private func resizeMetersPanel(to size: NSSize) {
        guard let panel = metersPanel else { return }
        let origin = NSPoint(x: panel.frame.minX, y: panel.frame.maxY - size.height)
        panel.minSize = size
        panel.maxSize = size
        panel.setContentSize(size)
        panel.setFrameOrigin(origin)
    }

    // MARK: - Окно компрессора

    /// Открывает окно компрессора выбранного входа или выхода (переиспользует уже открытое).
    func openCompressor(target: CompressorTarget) {
        if let panel = compressorPanel, compressorTarget == target, panel.isVisible {
            panel.orderFrontRegardless()
            if panel.alphaValue < 1 {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.14
                    panel.animator().alphaValue = 1
                }
            }
            return
        }
        if let panel = compressorPanel {
            saveFrame(of: panel, named: Self.compressorFrameName)
            hidePanel(panel)
        }
        let size = CompressorView.contentSize
        let hosting = FirstMouseHostingView(rootView: CompressorView(viewModel: mixerViewModel, target: target) { [weak self] in
            self?.closeCompressor()
        })
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.sizingOptions = []
        let panel = PanelFactory.makeOverlayPanel(CompressorPanel.self, contentView: hosting, size: size)
        panel.hidesOnDeactivate = false

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        restoreFrame(
            of: panel,
            named: Self.compressorFrameName,
            fallback: NSRect(x: screen.maxX - size.width - 20, y: screen.maxY - size.height - 60, width: size.width, height: size.height)
        )
        panel.setContentSize(size)
        showPanel(panel)
        compressorPanel = panel
        compressorTarget = target
    }

    func closeCompressor() {
        if let panel = compressorPanel {
            saveFrame(of: panel, named: Self.compressorFrameName)
            hidePanel(panel)
        }
        compressorPanel = nil
        compressorTarget = nil
    }

    // MARK: - Окно эквалайзера

    /// Открывает окно EQ выбранного канала (переиспользует уже открытое).
    func openEQ(_ target: EQTarget) {
        if let panel = eqPanel, eqTarget == target, panel.isVisible {
            panel.orderFrontRegardless()
            if panel.alphaValue < 1 {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.14
                    panel.animator().alphaValue = 1
                }
            }
            return
        }
        if let panel = eqPanel {
            saveFrame(of: panel, named: Self.eqFrameName)
            hidePanel(panel)
        }
        let size = EqualizerView.contentSize
        let hosting = FirstMouseHostingView(rootView: EqualizerView(viewModel: mixerViewModel, target: target) { [weak self] in
            self?.closeEQ()
        })
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.sizingOptions = []
        let panel = PanelFactory.makeOverlayPanel(EQPanel.self, contentView: hosting, size: size)
        panel.hasShadow = true
        panel.hidesOnDeactivate = false

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        restoreFrame(
            of: panel,
            named: Self.eqFrameName,
            fallback: NSRect(x: screen.maxX - size.width - 20, y: screen.maxY - size.height - 60, width: size.width, height: size.height)
        )
        panel.setContentSize(size)
        showPanel(panel)
        eqPanel = panel
        eqTarget = target
    }

    func closeEQ() {
        if let panel = eqPanel {
            saveFrame(of: panel, named: Self.eqFrameName)
            hidePanel(panel)
        }
        eqPanel = nil
        eqTarget = nil
    }

    // MARK: - Room EQ

    /// Открывает окно Room EQ выхода (переиспользует открытое для того же адреса).
    func openRoomEQ(_ target: RoomEQTarget) {
        if let panel = roomEQPanel, roomEQTarget == target, panel.isVisible {
            panel.orderFrontRegardless()
            if panel.alphaValue < 1 {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.14
                    panel.animator().alphaValue = 1
                }
            }
            return
        }
        if let panel = roomEQPanel {
            saveFrame(of: panel, named: Self.roomEQFrameName)
            hidePanel(panel)
        }
        let size = RoomEQView.contentSize
        let hosting = FirstMouseHostingView(rootView: RoomEQView(
            viewModel: mixerViewModel,
            target: target,
            onClose: { [weak self] in self?.closeRoomEQ() },
            onMeasure: { [weak self] in self?.openRoomCorrection(for: target) }
        ))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.sizingOptions = []
        let panel = PanelFactory.makeOverlayPanel(EQPanel.self, contentView: hosting, size: size)
        panel.hasShadow = true
        panel.hidesOnDeactivate = false

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        restoreFrame(
            of: panel,
            named: Self.roomEQFrameName,
            fallback: NSRect(x: screen.minX + 40, y: screen.maxY - size.height - 60,
                             width: size.width, height: size.height)
        )
        panel.setContentSize(size)
        showPanel(panel)
        roomEQPanel = panel
        roomEQTarget = target
    }

    func closeRoomEQ() {
        if let panel = roomEQPanel {
            saveFrame(of: panel, named: Self.roomEQFrameName)
            hidePanel(panel)
        }
        roomEQPanel = nil
        roomEQTarget = nil
    }

    // MARK: - Room correction

    /// Открывает мастер замера и коррекции для того же выхода.
    func openRoomCorrection(for target: RoomEQTarget) {
        if let panel = roomCorrectionPanel, roomCorrectionTarget == target, panel.isVisible {
            panel.orderFrontRegardless()
            return
        }
        if let panel = roomCorrectionPanel {
            saveFrame(of: panel, named: Self.roomCorrectionFrameName)
            hidePanel(panel)
        }
        let size = RoomCorrectionView.contentSize
        let hosting = FirstMouseHostingView(rootView: RoomCorrectionView(
            mixer: mixerViewModel,
            target: target,
            onClose: { [weak self] in self?.closeRoomCorrection() }
        ))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.sizingOptions = []
        // Пока открыт мастер, Room EQ не должен висеть над ним.
        if let roomEQ = roomEQPanel {
            roomEQ.level = .normal
            roomEQ.collectionBehavior = [.managed]
            roomEQLoweredForMeasure = true
        }
        let panel = PanelFactory.makeOverlayPanel(EQPanel.self, contentView: hosting, size: size)
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        // Мастер замера — обычное окно, а не панель поверх всех приложений.
        panel.level = .normal
        panel.collectionBehavior = [.managed]
        panel.isFloatingPanel = false

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        restoreFrame(
            of: panel,
            named: Self.roomCorrectionFrameName,
            fallback: NSRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2,
                             width: size.width, height: size.height)
        )
        panel.setContentSize(size)
        showPanel(panel)
        roomCorrectionPanel = panel
        roomCorrectionTarget = target
    }

    func closeRoomCorrection() {
        if let panel = roomCorrectionPanel {
            saveFrame(of: panel, named: Self.roomCorrectionFrameName)
            hidePanel(panel)
        }
        roomCorrectionPanel = nil
        roomCorrectionTarget = nil
        if roomEQLoweredForMeasure, let roomEQ = roomEQPanel {
            roomEQ.level = .screenSaver
            roomEQ.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        }
        roomEQLoweredForMeasure = false
    }

    // MARK: - Индикатор DIM

    func updateDimIndicator(isOn: Bool) {
        if isOn {
            showDimIndicator()
        } else {
            hideDimIndicator()
        }
    }

    func hideDimIndicator() {
        guard let panel = dimIndicatorPanel else { return }
        panel.orderOut(nil)
        panel.contentView = nil
        dimIndicatorPanel = nil
    }

    /// Ставит индикатор в правый нижний угол главного экрана.
    func positionDimIndicator() {
        guard let panel = dimIndicatorPanel, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.frame
        let panelSize = panel.frame.size
        let x = frame.maxX - panelSize.width - 16
        let y = frame.minY + 16
        panel.setFrame(NSRect(x: x, y: y, width: panelSize.width, height: panelSize.height), display: true)
    }

    private func showDimIndicator() {
        if dimIndicatorPanel == nil {
            let panel = PanelFactory.makeOverlayPanel(NSPanel.self, contentView: NSHostingView(rootView: DimIndicatorView()))
            panel.ignoresMouseEvents = true
            dimIndicatorPanel = panel
        }
        positionDimIndicator()
        dimIndicatorPanel?.orderFrontRegardless()
    }

    // MARK: - OSC-монитор

    func openOSCMonitor() {
        if let window = oscMonitorWindow {
            oscMonitor.isEnabled = true
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let hosting = NSHostingController(rootView: OSCMonitorView(monitor: oscMonitor))
        hosting.sizingOptions = []
        let window = OSCMonitorWindow(contentViewController: hosting)
        window.title = String(localized: "OSC Monitor")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 640, height: 420))
        window.contentMinSize = NSSize(width: 480, height: 260)
        window.isReleasedWhenClosed = false
        window.center()
        window.onClose = { [weak self] in
            self?.oscMonitor.isEnabled = false
        }
        oscMonitorWindow = window
        oscMonitor.isEnabled = true
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func closeOSCMonitor() {
        oscMonitorWindow?.close()
        oscMonitorWindow = nil
    }

    // MARK: - Каналы из TotalMix

    /// Открывает окно выбора каналов: внутри сразу идёт опрос TotalMix,
    /// а пользователь отмечает, какие входы и выходы добавить в программу.
    func openChannelDiscovery() {
        if let window = channelDiscoveryWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            channelDiscoveryViewModel?.rescan()
            return
        }
        let viewModel = makeChannelDiscoveryViewModel()
        var createdWindow: ChannelDiscoveryWindow?
        let view = ChannelDiscoveryView(
            viewModel: viewModel,
            onDone: { createdWindow?.close() },
            onCancel: { createdWindow?.close() }
        )
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = []
        let window = ChannelDiscoveryWindow(contentViewController: hosting)
        createdWindow = window
        window.title = String(localized: "Add channels from TotalMix")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 580, height: 560))
        window.contentMinSize = NSSize(width: 540, height: 360)
        window.isReleasedWhenClosed = false
        window.center()
        window.onClose = { [weak self] in
            self?.channelDiscoveryWindow = nil
            self?.channelDiscoveryViewModel = nil
        }
        channelDiscoveryWindow = window
        channelDiscoveryViewModel = viewModel
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    // MARK: - Мастер настройки

    /// Мастер первого запуска: приветствие, выбор каналов и проверка разрешений.
    func openSetupAssistant() {
        if let window = setupWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let viewModel = makeSetupAssistantViewModel()
        let hosting = NSHostingController(rootView: SetupAssistantView(viewModel: viewModel))
        hosting.sizingOptions = []
        let window = SetupAssistantWindow(contentViewController: hosting)
        window.title = String(localized: "Set Up RME Control")
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 600, height: 620))
        window.isReleasedWhenClosed = false
        window.center()
        viewModel.onFinish = { [weak window] in
            window?.close()
        }
        window.onClose = { [weak self] in
            // Закрытие крестиком тоже считается завершением, иначе мастер
            // появлялся бы при каждом запуске.
            self?.setupViewModel?.markSetupCompleted()
            self?.setupWindow = nil
            self?.setupViewModel = nil
        }
        setupWindow = window
        setupViewModel = viewModel
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    // MARK: - Настройки

    func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let viewModel = makeSettingsViewModel()
        viewModel.onOpenOSCMonitor = { [weak self] in
            self?.openOSCMonitor()
        }
        viewModel.onOpenChannelDiscovery = { [weak self] in
            self?.openChannelDiscovery()
        }
        viewModel.onOpenRoomEQ = { [weak self] target in
            self?.openRoomEQ(target)
        }
        let hosting = NSHostingController(rootView: SettingsView(viewModel: viewModel))
        hosting.sizingOptions = []
        let window = SettingsWindow(contentViewController: hosting)
        window.delegate = window
        window.title = String(localized: "RME Control Settings")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 550, height: 640))
        let minimumContentSize = NSSize(width: 550, height: 540)
        window.contentMinSize = minimumContentSize
        window.minSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: minimumContentSize)).size
        window.maxSize = NSSize(width: 2000, height: 3000)
        window.isReleasedWhenClosed = false
        window.center()
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
