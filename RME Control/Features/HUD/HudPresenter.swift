import AppKit
import SwiftUI

/// Показывает поповеры, привязанные к иконке в строке меню:
/// главный поповер (по клику) и короткие HUD — громкость, статус (Dim/Mono/Mute,
/// подключение устройства), предупреждение о клиппинге. Отвечает за задержку
/// показа, автоскрытие по таймеру и за то, чтобы HUD не перекрывали главный поповер.
@MainActor
final class HudPresenter {
    private let viewModel: MixerViewModel
    private weak var statusItem: NSStatusItem?
    private var mainPopover: NSPopover?
    private var volumePopover: NSPopover?
    private var volumePopoverTarget: UUID?
    private var statusHUDPopover: NSPopover?
    private var statusHUDPopoverKind: HUDStatusKind?
    private var dimMonoPopover: NSPopover?
    private var dimMonoDismissTimer: Timer?
    private var outputPickerPopover: NSPopover?
    private var outputPickerDismissTimer: Timer?
    private var clipPopover: NSPopover?
    private var clipDismissTimer: Timer?
    private var clipVisible = false
    private var dismissTimer: Timer?
    private var pendingShowWork: DispatchWorkItem?

    private var mainMaxContentHeight: CGFloat = 640
    private var mainOnToggleMeters: (() -> Void)?
    private var mainOnOpenSettings: (() -> Void)?
    private var mainOnOpenCompressor: ((CompressorTarget) -> Void)?
    private var mainOnOpenEQ: ((EQTarget) -> Void)?
    private var mainOnOpenRoomEQ: ((RoomEQTarget) -> Void)?

    private static let hudDuration: TimeInterval = 1.5
    private static let clipHUDDuration: TimeInterval = 5.0
    private static let dimMonoHUDDuration: TimeInterval = 2.0
    private static let outputPickerHUDDuration: TimeInterval = 2.0
    private static let showDelay: TimeInterval = 0.1

    init(viewModel: MixerViewModel) {
        self.viewModel = viewModel
    }

    /// Создаёт главный поповер и привязывает все HUD к кнопке статус-бара.
    func attach(statusItem: NSStatusItem, onToggleMeters: @escaping () -> Void, onOpenSettings: @escaping () -> Void, onOpenCompressor: @escaping (CompressorTarget) -> Void, onOpenEQ: @escaping (EQTarget) -> Void, onOpenRoomEQ: @escaping (RoomEQTarget) -> Void) {
        self.statusItem = statusItem
        mainOnToggleMeters = onToggleMeters
        mainOnOpenSettings = onOpenSettings
        mainOnOpenCompressor = onOpenCompressor
        mainOnOpenEQ = onOpenEQ
        mainOnOpenRoomEQ = onOpenRoomEQ
        // Высота поповера не должна выходить за видимую область экрана.
        let screen = statusItem.button?.window?.screen ?? NSScreen.main ?? NSScreen.screens.first
        mainMaxContentHeight = max(280, (screen?.visibleFrame.height ?? 700) - 48)
        if let outputID = viewModel.volumeKeyOutputID {
            _ = volumePopover(for: outputID)
        }
    }

    func toggleMainPopover() {
        guard let button = statusItem?.button else { return }
        if mainPopover?.isShown == true {
            mainPopover?.performClose(nil)
            return
        }
        closeAll()
        mainPopover?.close()
        // Решаем по фактической высоте контента: при переполнении — ScrollView,
        // иначе обычный вид без прокрутки. Так «резинового» отскока нет.
        mainPopover = makeMainPopover()
        mainPopover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        mainPopover?.contentViewController?.view.window?.makeKey()
    }

    /// Главный поповер: обычный вид, если контент помещается, иначе — с прокруткой.
    private func makeMainPopover() -> NSPopover {
        let view = VolumeControlView(
            viewModel: viewModel,
            maxContentHeight: mainMaxContentHeight,
            scrollable: mainPopoverNeedsScrolling(),
            onToggleMeters: mainOnToggleMeters,
            onOpenSettings: mainOnOpenSettings,
            onOpenCompressor: mainOnOpenCompressor,
            onOpenEQ: mainOnOpenEQ,
            onOpenRoomEQ: mainOnOpenRoomEQ
        )
        return makePopover(view, behavior: .transient)
    }

    /// Измеряет контент в том виде, в каком он будет показан без прокрутки.
    private func mainPopoverNeedsScrolling() -> Bool {
        let probe = VolumeControlView(viewModel: viewModel, maxContentHeight: mainMaxContentHeight)
        let controller = NSHostingController(rootView: probe)
        controller.sizingOptions = .preferredContentSize
        controller.view.layoutSubtreeIfNeeded()
        return controller.preferredContentSize.height > mainMaxContentHeight
    }

    /// - Parameter immediate: показывать сразу, без задержки — для изменений,
    ///   которые приходят из TotalMix, чтобы HUD успевал появиться во время перетаскивания фейдера.
    func showVolumeHUD(outputID: UUID, immediate: Bool = false) {
        guard mainPopover?.isShown != true, let button = statusItem?.button else { return }
        cancelPending()
        closeStatusHUD()
        closeDimMonoPopover()
        closeOutputPickerHUD()

        let vp = volumePopover(for: outputID)
        if !vp.isShown {
            if immediate {
                vp.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            } else {
                scheduleShow { [weak self] in
                    guard let self, let button = self.statusItem?.button, let vp = self.volumePopover, !vp.isShown else { return }
                    vp.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                }
            }
        }
        scheduleDismiss(after: Self.hudDuration)
    }

    func showStatusHUD(kind: HUDStatusKind, duration: TimeInterval) {
        guard mainPopover?.isShown != true, statusItem?.button != nil else { return }
        cancelPending()
        closeVolumeHUD()
        closeDimMonoPopover()
        closeOutputPickerHUD()

        if statusHUDPopover == nil || statusHUDPopoverKind != kind || statusHUDPopover?.contentViewController?.view.window == nil {
            statusHUDPopover?.close()
            statusHUDPopover = makePopover(StatusHUDView(viewModel: viewModel, kind: kind), behavior: .applicationDefined)
            statusHUDPopoverKind = kind
        }

        guard let hud = statusHUDPopover else { return }
        if !hud.isShown {
            scheduleShow { [weak self] in
                guard let self, let button = self.statusItem?.button, let hud = self.statusHUDPopover, !hud.isShown else { return }
                hud.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
        scheduleDismiss(after: duration)
    }

    func showClipIndicator(inputID: UUID) {
        if mainPopover?.isShown == true { return }
        guard let button = statusItem?.button else { return }

        if !clipVisible {
            clipPopover?.close()
            let name = viewModel.inputLabel(for: inputID)
            let p = makePopover(
                SingleStatusHUDView(icon: "exclamationmark.triangle.fill", title: String(localized: "Clipping on \(name)"), on: true, tint: .red),
                behavior: .applicationDefined
            )
            clipPopover = p

            NSApp.activate()
            p.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            clipVisible = true
        }

        clipDismissTimer?.invalidate()
        clipDismissTimer = scheduleTimer(after: Self.clipHUDDuration) { [weak self] in
            self?.closeClipIndicator()
        }
    }

    func updateDimMonoHUD(kind: HUDStatusKind) {
        let on: Bool
        switch kind {
        case .dim: on = viewModel.dimOn
        case .mono: on = viewModel.monoOn
        case .mute: on = viewModel.isVolumeKeyOutputMuted
        default: return
        }
        let icon = HUDStatusText.icon(kind)
        let status = HUDStatusText.onOff(kind, on: on)
        let title: String
        if kind == .mute, let outputID = viewModel.volumeKeyOutputID {
            title = "\(viewModel.outputName(for: outputID)): \(status)"
        } else {
            title = status
        }
        if mainPopover?.isShown == true { return }
        guard let button = statusItem?.button else { return }

        cancelPending()
        closeVolumeHUD()
        closeStatusHUD()
        closeOutputPickerHUD()
        dimMonoPopover?.close()
        let p = makePopover(SingleStatusHUDView(icon: icon, title: title, on: on), behavior: .applicationDefined)
        dimMonoPopover = p

        NSApp.activate()
        p.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        dimMonoDismissTimer?.invalidate()
        dimMonoDismissTimer = scheduleTimer(after: Self.dimMonoHUDDuration) { [weak self] in
            self?.closeDimMonoPopover()
        }
    }

    /// HUD выбора выхода для клавиш громкости. Показывается поверх остальных HUD
    /// и закрывает главный поповер, если он открыт.
    func showOutputPickerHUD() {
        guard let button = statusItem?.button else { return }
        if mainPopover?.isShown == true {
            mainPopover?.close()
        }
        cancelPending()
        closeVolumeHUD()
        closeStatusHUD()
        closeDimMonoPopover()

        if outputPickerPopover == nil {
            outputPickerPopover = makePopover(OutputPickerHUDView(viewModel: viewModel), behavior: .applicationDefined)
        }
        if outputPickerPopover?.isShown != true {
            outputPickerPopover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }

        outputPickerDismissTimer?.invalidate()
        outputPickerDismissTimer = scheduleTimer(after: Self.outputPickerHUDDuration) { [weak self] in
            self?.closeOutputPickerHUD()
        }
    }

    func closeAll() {
        cancelPending()
        mainPopover?.close()
        closeVolumeHUD()
        closeStatusHUD()
        closeDimMonoPopover()
        closeOutputPickerHUD()
        closeClipIndicator()
    }

    // MARK: - Private

    private func makePopover<Content: View>(_ rootView: Content, behavior: NSPopover.Behavior) -> NSPopover {
        let hosting = NSHostingController(rootView: rootView)
        hosting.sizingOptions = .preferredContentSize
        let popover = NSPopover()
        popover.behavior = behavior
        popover.contentViewController = hosting
        return popover
    }

    /// Таймер в режиме `.common`, чтобы срабатывал и во время трекинга мыши/меню.
    private func scheduleTimer(after interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: false) { _ in
            MainActor.assumeIsolated { action() }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    private func closeClipIndicator() {
        clipDismissTimer?.invalidate()
        clipDismissTimer = nil
        if clipPopover?.isShown == true { clipPopover?.close() }
        clipVisible = false
    }

    private func closeDimMonoPopover() {
        dimMonoDismissTimer?.invalidate()
        dimMonoDismissTimer = nil
        if dimMonoPopover?.isShown == true { dimMonoPopover?.close() }
    }

    private func closeOutputPickerHUD() {
        outputPickerDismissTimer?.invalidate()
        outputPickerDismissTimer = nil
        if outputPickerPopover?.isShown == true { outputPickerPopover?.close() }
    }

    private func volumePopover(for outputID: UUID) -> NSPopover {
        if let p = volumePopover, volumePopoverTarget == outputID {
            return p
        }
        volumePopover?.close()
        let p = makePopover(VolumeHUDView(viewModel: viewModel, outputID: outputID), behavior: .applicationDefined)
        volumePopover = p
        volumePopoverTarget = outputID
        return p
    }

    private func scheduleShow(_ work: @escaping @MainActor () -> Void) {
        let item = DispatchWorkItem {
            MainActor.assumeIsolated { work() }
        }
        pendingShowWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.showDelay, execute: item)
    }

    private func scheduleDismiss(after interval: TimeInterval) {
        dismissTimer?.invalidate()
        dismissTimer = scheduleTimer(after: interval) { [weak self] in
            self?.closeVolumeHUD()
            self?.closeStatusHUD()
        }
    }

    private func cancelPending() {
        pendingShowWork?.cancel()
        pendingShowWork = nil
        dismissTimer?.invalidate()
        dismissTimer = nil
    }

    private func closeVolumeHUD() {
        if volumePopover?.isShown == true { volumePopover?.close() }
    }

    private func closeStatusHUD() {
        if statusHUDPopover?.isShown == true { statusHUDPopover?.close() }
    }
}
