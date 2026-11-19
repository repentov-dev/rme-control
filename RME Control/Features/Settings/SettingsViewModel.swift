import AppKit
import SwiftUI
import Observation

/// ViewModel окна настроек: даёт View привязки (`Binding`) к настройкам,
/// управляет каналами (добавить/удалить/переименовать), применяет OSC-хост и порты
/// и отдаёт адрес и QR-код веб-пульта.
@MainActor
@Observable
final class SettingsViewModel {
    // MARK: - Черновик OSC-подключения (применяется кнопкой Apply)

    var oscHost: String
    var oscSendPort: String
    var oscRecvPort: String
    private(set) var showOSCError = false

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let mixer: MixerService
    @ObservationIgnored private let osc: OSCClient
    @ObservationIgnored private let webServer: WebServer
    @ObservationIgnored var onOpenOSCMonitor: (() -> Void)?
    @ObservationIgnored var onOpenChannelDiscovery: (() -> Void)?
    /// Открывает окно Room EQ для выхода (окно создаёт WindowManager).
    @ObservationIgnored var onOpenRoomEQ: ((RoomEQTarget) -> Void)?

    init(settings: AppSettings, mixer: MixerService, osc: OSCClient, webServer: WebServer) {
        self.settings = settings
        self.mixer = mixer
        self.osc = osc
        self.webServer = webServer
        oscHost = osc.currentHost
        oscSendPort = String(osc.currentSendPort)
        oscRecvPort = String(osc.currentRecvPort)
    }

    /// Двусторонняя привязка к свойству настроек (для Toggle, Picker, Slider).
    func binding<Value>(_ keyPath: ReferenceWritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        let settings = settings
        return Binding(
            get: { settings[keyPath: keyPath] },
            set: { settings[keyPath: keyPath] = $0 }
        )
    }

    var volumeStepDB: Double { settings.volumeStepDB }
    var webServerEnabled: Bool { settings.webServerEnabled }
    var appVersion: String { AppEnvironment.appVersion }

    // MARK: - Запуск и разрешения

    var launchAtLoginEnabled: Bool { LaunchAtLogin.isEnabled }

    func setLaunchAtLogin(_ enabled: Bool) { LaunchAtLogin.setEnabled(enabled) }

    var accessibilityGranted: Bool { AccessibilityPermission.isGranted }

    func openAccessibilitySettings() { AccessibilityPermission.openSystemSettings() }

    // MARK: - Выходы

    var outputs: [OutputConfig] { settings.outputs }

    func outputName(for id: UUID) -> String { settings.outputName(for: id) }

    func outputAddress(for id: UUID) -> String { settings.output(id: id)?.oscAddress ?? "" }

    private func outputBinding<Value>(_ id: UUID, _ keyPath: WritableKeyPath<OutputConfig, Value>, default defaultValue: Value, transform: @escaping (Value) -> Value = { $0 }) -> Binding<Value> {
        let settings = settings
        return Binding(
            get: { settings.output(id: id)?[keyPath: keyPath] ?? defaultValue },
            set: { newValue in settings.updateOutput(id) { $0[keyPath: keyPath] = transform(newValue) } }
        )
    }

    func outputNameBinding(_ id: UUID) -> Binding<String> {
        outputBinding(id, \.name, default: "") { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    func outputAddressBinding(_ id: UUID) -> Binding<String> {
        outputBinding(id, \.oscAddress, default: "") { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Адрес индикатора уровня, выведенный из номера канала в OSC-адресе.
    func outputLevelAddress(for id: UUID) -> String {
        settings.output(id: id)?.resolvedLevelAddress ?? ""
    }

    func outputPartnerBinding(_ id: UUID) -> Binding<String> {
        outputBinding(id, \.partnerAddress, default: "") { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Подсказка под полем парного канала: что попадёт в RIGHT.
    func partnerLevelHint(_ id: UUID) -> String {
        guard let target = roomEQTarget(for: id) else { return String(localized: "Set the channel address first") }
        guard let partner = target.partner else { return String(localized: "No partner: edits one channel") }
        let explicit = settings.output(id: id)?.partnerAddress.trimmingCharacters(in: .whitespaces) ?? ""
        if explicit.isEmpty {
            return String(format: String(localized: "%@ (automatic)"), partner)
        }
        return partner
    }

    /// Адресат Room EQ для выхода: его адрес, парный канал (если задан) и имя.
    func roomEQTarget(for id: UUID) -> RoomEQTarget? {
        guard let output = settings.output(id: id), !output.oscAddress.isEmpty else { return nil }
        return RoomEQTarget(
            address: output.oscAddress,
            partner: output.resolvedPartnerAddress,
            label: output.name.isEmpty ? output.oscAddress : output.name,
            isHeadphone: output.icon == .headphones
        )
    }

    func openRoomEQ(_ id: UUID) {
        guard let target = roomEQTarget(for: id) else { return }
        onOpenRoomEQ?(target)
    }

    func outputIconBinding(_ id: UUID) -> Binding<OutputIcon> {
        outputBinding(id, \.icon, default: .speaker)
    }

    func outputShowBinding(_ id: UUID) -> Binding<Bool> {
        outputBinding(id, \.showInMain, default: false)
    }

    func addOutput() { mixer.addOutput() }
    func removeOutput(_ id: UUID) { mixer.removeOutput(id: id) }

    // MARK: - Входы

    var inputs: [InputConfig] { settings.inputs }

    func inputLabel(for id: UUID) -> String { settings.inputLabel(for: id) }

    func inputAddress(for id: UUID) -> String { settings.input(id: id)?.oscAddress ?? "" }

    private func inputBinding<Value>(_ id: UUID, _ keyPath: WritableKeyPath<InputConfig, Value>, default defaultValue: Value, transform: @escaping (Value) -> Value = { $0 }) -> Binding<Value> {
        let settings = settings
        return Binding(
            get: { settings.input(id: id)?[keyPath: keyPath] ?? defaultValue },
            set: { newValue in settings.updateInput(id) { $0[keyPath: keyPath] = transform(newValue) } }
        )
    }

    func inputNameBinding(_ id: UUID) -> Binding<String> {
        inputBinding(id, \.name, default: "") { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    func inputAddressBinding(_ id: UUID) -> Binding<String> {
        inputBinding(id, \.oscAddress, default: "") { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Адрес индикатора уровня, выведенный из номера канала в OSC-адресе.
    func inputLevelAddress(for id: UUID) -> String {
        settings.input(id: id)?.resolvedLevelAddress ?? ""
    }

    func inputTypeBinding(_ id: UUID) -> Binding<InputType> {
        inputBinding(id, \.type, default: .line)
    }

    func inputShowInPopoverBinding(_ id: UUID) -> Binding<Bool> {
        inputBinding(id, \.showInPopover, default: false)
    }

    func inputShowInLevelsBinding(_ id: UUID) -> Binding<Bool> {
        inputBinding(id, \.showInMain, default: false)
    }

    func addInput() { mixer.addInput() }
    func removeInput(_ id: UUID) { mixer.removeInput(id: id) }

    // MARK: - Считывание каналов из TotalMix

    /// Открывает окно со всем, что TotalMix прислал: пользователь сам отмечает,
    /// какие входы и выходы добавить в программу.
    func openChannelDiscovery() {
        onOpenChannelDiscovery?()
    }

    // MARK: - Посылы

    var sends: [SendConfig] { settings.sends }

    func sendName(for id: UUID) -> String { settings.sendName(for: id) }

    func sendInputLabel(for id: UUID) -> String {
        guard let send = settings.send(id: id) else { return "" }
        return settings.inputLabel(for: send.inputID)
    }

    func sendOutputName(for id: UUID) -> String {
        guard let send = settings.send(id: id) else { return "" }
        return settings.outputName(for: send.outputID)
    }

    func sendNameBinding(_ id: UUID) -> Binding<String> {
        let settings = settings
        return Binding(
            get: { settings.send(id: id)?.name ?? "" },
            set: { newValue in
                settings.updateSend(id) { $0.name = newValue.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        )
    }

    func sendShowBinding(_ id: UUID) -> Binding<Bool> {
        let settings = settings
        return Binding(
            get: { settings.send(id: id)?.showInMain ?? false },
            set: { newValue in settings.updateSend(id) { $0.showInMain = newValue } }
        )
    }

    func availableSendOutputs(for inputID: UUID) -> [OutputConfig] {
        outputs.filter { output in
            !settings.sends.contains { $0.inputID == inputID && $0.outputID == output.id }
        }
    }

    func addSend(inputID: UUID, outputID: UUID) {
        mixer.addSend(inputID: inputID, outputID: outputID)
    }

    func removeSend(_ id: UUID) {
        mixer.removeSend(id: id)
    }

    // MARK: - OSC

    /// Проверяет хост и порты; при ошибке показывает «Invalid ports», иначе переподключает OSC.
    func applyOSCSettings() {
        let trimmedHost = oscHost.trimmingCharacters(in: .whitespaces)
        guard let sp = UInt16(oscSendPort.trimmingCharacters(in: .whitespaces)), sp > 0,
              let rp = UInt16(oscRecvPort.trimmingCharacters(in: .whitespaces)), rp > 0,
              !trimmedHost.isEmpty else {
            showOSCError = true
            return
        }
        showOSCError = false
        osc.reconfigure(host: trimmedHost, sendPort: sp, recvPort: rp)
    }

    func openOSCMonitor() {
        onOpenOSCMonitor?()
    }

    // MARK: - Пресеты настроек

    var presets: [SettingsPreset] { settings.presets }

    func savePreset(named name: String) {
        // Пресет — отпечаток всего: конфигурация, Room EQ и живое состояние пульта.
        settings.savePreset(named: name,
                            roomEQs: mixer.roomEQStates,
                            mixer: mixer.mixerSnapshot())
    }

    func applyPreset(_ preset: SettingsPreset) {
        mixer.applyConfiguration { settings.apply(preset) }
        if let roomEQs = preset.snapshot.roomEQs {
            mixer.applyRoomEQStates(roomEQs)
        }
        if let live = preset.snapshot.mixer {
            mixer.applyChannelProcessing(live.processing ?? [:])
            mixer.applyMixerSnapshot(live)
        }
        // Эквалайзеры, фильтры и динамика — тоже часть отпечатка.
        mixer.pushChannelProcessing()
    }

    /// Импорт из файла: пресеты добавляются к текущим, ничего не затирая.
    func importPresets(_ presets: [SettingsPreset]) {
        settings.addPresets(presets)
    }

    func removePreset(_ preset: SettingsPreset) {
        settings.removePreset(id: preset.id)
    }

    // MARK: - Язык

    var language: AppLanguage { settings.language }

    /// Выбранный язык отличается от того, с которым запущено приложение.
    var languageNeedsRestart: Bool { settings.language != AppLanguage.launchLanguage }

    var languageBinding: Binding<AppLanguage> {
        let settings = settings
        return Binding(
            get: { settings.language },
            set: { newValue in
                settings.language = newValue
                newValue.applyOverride()
            }
        )
    }

    /// Запускает новый экземпляр приложения и завершает текущий, чтобы применить язык.
    func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            guard error == nil else { return }
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

    // MARK: - Веб-пульт

    var webURLString: String { webServer.urlString }

    var webQRCode: NSImage? { QRCodeGenerator.image(for: webServer.urlString) }

    /// Порт веб-пульта; применяется сразу и ограничивается диапазоном 1…65535.
    var webServerPortBinding: Binding<Int> {
        let settings = settings
        return Binding(
            get: { settings.webServerPort },
            set: { settings.webServerPort = min(max($0, 1), 65535) }
        )
    }

    func copyWebURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(webURLString, forType: .string)
    }

    // MARK: - Горячие клавиши

    func hotkey(for action: HotkeyAction) -> Hotkey {
        settings.hotkey(for: action)
    }

    func hotkeyEnabledBinding(_ action: HotkeyAction) -> Binding<Bool> {
        Binding(
            get: { self.settings.hotkey(for: action).isEnabled },
            set: { isEnabled in
                var hotkey = self.settings.hotkey(for: action)
                hotkey.isEnabled = isEnabled
                if isEnabled, hotkey.isAssigned {
                    // Включение занятой комбинации отключает её у другого действия.
                    self.assignHotkey(hotkey, to: action)
                } else {
                    self.settings.setHotkey(hotkey, for: action)
                }
            }
        )
    }

    /// Назначает комбинацию действию. Если она уже занята другим действием,
    /// у того она выключается — одна комбинация не может срабатывать дважды.
    func assignHotkey(_ hotkey: Hotkey, to action: HotkeyAction) {
        var all = Dictionary(uniqueKeysWithValues: HotkeyAction.allCases.map { ($0, settings.hotkey(for: $0)) })
        if hotkey.isEnabled, hotkey.isAssigned {
            for (other, otherHotkey) in all where other != action {
                if otherHotkey.isEnabled, otherHotkey.usesSameCombination(as: hotkey) {
                    all[other]?.isEnabled = false
                }
            }
        }
        all[action] = hotkey
        settings.hotkeys = Dictionary(uniqueKeysWithValues: all.map { ($0.key.rawValue, $0.value) })
    }

    /// Убирает комбинацию у действия (остаётся выключенной и без клавиши).
    func clearHotkey(for action: HotkeyAction) {
        settings.setHotkey(Hotkey(keyCode: nil, modifiers: [], label: "", isEnabled: false), for: action)
    }

    func resetHotkeys() {
        settings.resetHotkeys()
    }

    /// Ни одной переназначенной комбинации — значит, включены значения по умолчанию.
    var hotkeysAreDefault: Bool { settings.hotkeys.isEmpty }

    /// Действие, для которого сейчас записывается комбинация.
    private(set) var recordingAction: HotkeyAction?

    /// Пока идёт запись комбинации, глобальный перехват клавиш приостановлен.
    func beginHotkeyRecording(for action: HotkeyAction) {
        recordingAction = action
        settings.isRecordingHotkey = true
    }

    func endHotkeyRecording() {
        recordingAction = nil
        settings.isRecordingHotkey = false
    }

    // MARK: - Файл настроек

    var settingsFilePath: String { SettingsFile.displayPath }

    func showSettingsFile() {
        SettingsFile.reveal()
    }

    // MARK: - Сброс

    func resetToDefaults() {
        mixer.resetToDefaults()
        osc.reconfigure(
            host: OSCClient.defaultHost,
            sendPort: OSCClient.defaultSendPort,
            recvPort: OSCClient.defaultRecvPort
        )
        oscHost = osc.currentHost
        oscSendPort = String(osc.currentSendPort)
        oscRecvPort = String(osc.currentRecvPort)
        showOSCError = false
    }
}
