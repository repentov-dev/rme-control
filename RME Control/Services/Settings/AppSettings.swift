import Foundation
import Observation

/// Пользовательские настройки, которые сохраняются между запусками:
/// конфигурация входов и выходов, OSC-адреса кнопок, что показывать в UI,
/// поведение аппаратных клавиш и параметры веб-пульта.
/// Любое изменение свойства сразу записывается в хранилище.
/// Каналы адресуются по `id` (UUID), а не по индексу.
@MainActor
@Observable
final class AppSettings {
    // Свойства объявлены без значений по умолчанию: первое присваивание в init —
    // это инициализация, и загруженные значения не перезаписываются обратно в хранилище.

    // MARK: - OSC-адреса кнопок Control Room

    var speakerBAddress: String { didSet { storage.set(speakerBAddress, for: .speakerBAddress) } }
    var dimAddress: String { didSet { storage.set(dimAddress, for: .dimAddress) } }
    var monoAddress: String { didSet { storage.set(monoAddress, for: .monoAddress) } }

    // MARK: - Устройство

    /// Считать TotalMix отключённым, если он не видит аудиоинтерфейс.
    var watchDeviceConnection: Bool { didSet { storage.set(watchDeviceConnection, for: .watchDeviceConnection) } }

    // MARK: - Язык

    /// Выбранный язык интерфейса; применяется после перезапуска (см. `AppLanguage`).
    var language: AppLanguage { didSet { storage.set(language.rawValue, for: .language) } }

    // MARK: - Каналы

    var inputs: [InputConfig] { didSet { persistInputs() } }
    var outputs: [OutputConfig] { didSet { persistOutputs() } }
    var sends: [SendConfig] { didSet { persistSends() } }

    // MARK: - Отображение в поповере

    var showMuteButtons: Bool { didSet { storage.set(showMuteButtons, for: .showMuteButtons) } }
    var showSpeakerB: Bool { didSet { storage.set(showSpeakerB, for: .showSpeakerB) } }
    var showDim: Bool { didSet { storage.set(showDim, for: .showDim) } }
    var showMono: Bool { didSet { storage.set(showMono, for: .showMono) } }

    // MARK: - Компрессор и эквалайзер в UI

    /// Показывать кнопку компрессора у входов.
    var showInputCompressor: Bool { didSet { storage.set(showInputCompressor, for: .showInputCompressor) } }
    /// Показывать кнопку EQ у входов.
    var showInputEQ: Bool { didSet { storage.set(showInputEQ, for: .showInputEQ) } }
    /// Показывать кнопку компрессора у выходов.
    var showOutputCompressor: Bool { didSet { storage.set(showOutputCompressor, for: .showOutputCompressor) } }
    /// Показывать кнопку EQ у выходов.
    var showOutputEQ: Bool { didSet { storage.set(showOutputEQ, for: .showOutputEQ) } }
    var showOutputRoomEQ: Bool { didSet { storage.set(showOutputRoomEQ, for: .showOutputRoomEQ) } }

    // MARK: - Аппаратные клавиши

    var muteKeyAction: MuteKeyAction { didSet { storage.set(muteKeyAction.rawValue, for: .muteKeyAction) } }
    var volumeStepDB: Double { didSet { storage.set(volumeStepDB, for: .volumeStepDB) } }
    var volumeKeyOutputID: UUID? { didSet { storage.set(volumeKeyOutputID?.uuidString, for: .volumeKeyOutputID) } }
    /// Временное переназначение клавиш (на время замера). Не сохраняется на диск:
    /// после закрытия окна или падения приложения клавиши сами вернутся.
    var temporaryVolumeKeyOutputID: UUID?
    /// Снимать Mute с выхода при изменении его громкости.
    var unmuteOnVolumeChange: Bool { didSet { storage.set(unmuteOnVolumeChange, for: .unmuteOnVolumeChange) } }
    /// Переключать выход клавишами Option + ↑/↓.
    var switchOutputWithArrowKeys: Bool { didSet { storage.set(switchOutputWithArrowKeys, for: .switchOutputWithArrowKeys) } }
    /// При переключении выхода мьютить все остальные выходы.
    var muteOtherOutputsOnSwitch: Bool { didSet { storage.set(muteOtherOutputsOnSwitch, for: .muteOtherOutputsOnSwitch) } }
    /// Устаревшая настройка: раньше включала отдельный перехват F10–F12. Сейчас
    /// комбинации настраиваются в `hotkeys`, но флаг читается при миграции.
    var useFunctionKeys: Bool { didSet { storage.set(useFunctionKeys, for: .useFunctionKeys) } }

    // MARK: - Горячие клавиши

    /// Переназначенные комбинации; ключ — `HotkeyAction.rawValue`.
    /// Пустой словарь означает «всё по умолчанию».
    var hotkeys: [String: Hotkey] { didSet { storage.setEncodable(hotkeys, for: .hotkeys) } }

    /// Пока в настройках записывается комбинация, глобальный перехват клавиш
    /// не должен её съедать — иначе, например, ⌘⇧M сработает вместо записи.
    @ObservationIgnored var isRecordingHotkey = false

    // MARK: - Первый запуск

    /// Пользователь прошёл (или закрыл) мастер настройки.
    private(set) var setupCompleted: Bool { didSet { storage.set(setupCompleted, for: .setupCompleted) } }

    /// Мастер показывается только на свежей установке, где ещё нет каналов.
    var needsSetup: Bool { !setupCompleted && inputs.isEmpty && outputs.isEmpty }


    // MARK: - Пресеты настроек

    private(set) var presets: [SettingsPreset] { didSet { storage.setEncodable(presets, for: .settingsPresets) } }

    // MARK: - Пользовательские пресеты Room EQ

    /// Пресеты, сохранённые из измерений Room EQ.
    private(set) var roomEQUserPresets: [RoomEQUserPreset] {
        didSet { storage.setEncodable(roomEQUserPresets, for: .roomEQUserPresets) }
    }

    /// Последние выбранные устройство, выход, микрофон и калибровка мастера замера.
    var roomCorrectionPreferences: RoomCorrectionPreferences {
        didSet { storage.setEncodable(roomCorrectionPreferences, for: .roomCorrectionPreferences) }
    }

    // MARK: - Веб-пульт

    var webServerEnabled: Bool { didSet { storage.set(webServerEnabled, for: .webServerEnabled) } }
    var webServerPort: Int { didSet { storage.set(webServerPort, for: .webServerPort) } }
    var webShowButtons: Bool { didSet { storage.set(webShowButtons, for: .webShowButtons) } }
    var webShowInputs: Bool { didSet { storage.set(webShowInputs, for: .webShowInputs) } }
    var webShowLevels: Bool { didSet { storage.set(webShowLevels, for: .webShowLevels) } }

    @ObservationIgnored private let storage: StorageProtocol

    init(storage: StorageProtocol) {
        self.storage = storage
        let migrator = StorageMigrator(storage: storage)

        speakerBAddress = migrator.speakerBAddress()
        dimAddress = migrator.dimAddress()
        monoAddress = migrator.monoAddress()
        watchDeviceConnection = storage.value(.watchDeviceConnection, default: true)
        language = AppLanguage(rawValue: storage.string(for: .language) ?? "") ?? .default
        showMuteButtons = storage.value(.showMuteButtons, default: true)
        showSpeakerB = storage.value(.showSpeakerB, default: true)
        showDim = storage.value(.showDim, default: true)
        showMono = storage.value(.showMono, default: true)
        showInputCompressor = storage.value(.showInputCompressor, default: true)
        showInputEQ = storage.value(.showInputEQ, default: true)
        showOutputCompressor = storage.value(.showOutputCompressor, default: true)
        showOutputEQ = storage.value(.showOutputEQ, default: true)
        showOutputRoomEQ = storage.value(.showOutputRoomEQ, default: true)
        muteKeyAction = MuteKeyAction(rawValue: storage.string(for: .muteKeyAction) ?? "") ?? .dim
        volumeStepDB = storage.value(.volumeStepDB, default: DefaultConfig.volumeStepDB)
        volumeKeyOutputID = storage.string(for: .volumeKeyOutputID).flatMap(UUID.init)
        unmuteOnVolumeChange = storage.value(.unmuteOnVolumeChange, default: true)
        let legacySwitchOutputWithArrowKeys = storage.value(.switchOutputWithArrowKeys, default: false)
        switchOutputWithArrowKeys = legacySwitchOutputWithArrowKeys
        muteOtherOutputsOnSwitch = storage.value(.muteOtherOutputsOnSwitch, default: false)
        let legacyUseFunctionKeys = storage.value(.useFunctionKeys, default: false)
        useFunctionKeys = legacyUseFunctionKeys
        webServerEnabled = storage.value(.webServerEnabled, default: false)
        webServerPort = storage.value(.webServerPort, default: DefaultConfig.webServerPort)
        webShowButtons = storage.value(.webShowButtons, default: true)
        webShowInputs = storage.value(.webShowInputs, default: true)
        webShowLevels = storage.value(.webShowLevels, default: true)
        presets = storage.decodable([SettingsPreset].self, for: .settingsPresets) ?? []
        roomEQUserPresets = storage.decodable([RoomEQUserPreset].self, for: .roomEQUserPresets) ?? []
        roomCorrectionPreferences = storage.decodable(RoomCorrectionPreferences.self,
                                                      for: .roomCorrectionPreferences) ?? RoomCorrectionPreferences()
        setupCompleted = storage.bool(for: .setupCompleted)

        // Каналов больше нет «по умолчанию»: на свежей установке их ноль и
        // пользователя ведёт мастер настройки. Пустые списки не сохраняем,
        // чтобы отсутствие ключа и дальше означало «каналы ещё не настроены».
        let savedOutputs = storage.decodable([OutputConfig].self, for: .outputs)
        let savedInputs = storage.decodable([InputConfig].self, for: .inputs)
        let savedSends = storage.decodable([SendConfig].self, for: .sends)
        // Очень старая версия не знала выходов и хранила только имена входов:
        // для неё сохраняем прежний набор каналов, иначе после обновления
        // пользователь остался бы совсем без выходов.
        let migratingLegacyChannels = savedInputs == nil && migrator.hasLegacyInputs

        outputs = savedOutputs ?? (migratingLegacyChannels ? DefaultConfig.outputs() : [])
        inputs = savedInputs ?? (migratingLegacyChannels ? migrator.legacyInputs() : [])
        sends = savedSends ?? Self.legacySends(from: storage.data(for: .inputs))

        // Горячие клавиши: сохранённые переопределения важнее старых флагов.
        if let saved = storage.decodable([String: Hotkey].self, for: .hotkeys) {
            hotkeys = saved
        } else {
            var migrated: [String: Hotkey] = [:]
            if legacyUseFunctionKeys {
                for action in [HotkeyAction.volumeUp, .volumeDown, .mute] {
                    var hotkey = action.defaultHotkey
                    hotkey.isEnabled = true
                    migrated[action.rawValue] = hotkey
                }
            }
            if legacySwitchOutputWithArrowKeys {
                for action in [HotkeyAction.nextOutput, .previousOutput] {
                    var hotkey = action.defaultHotkey
                    hotkey.isEnabled = true
                    migrated[action.rawValue] = hotkey
                }
            }
            hotkeys = migrated
        }

        // Все сохранённые свойства инициализированы — дальше можно писать в хранилище.
        // Миграция старой версии: сохраняем перенесённые каналы, но не пустые списки.
        if savedOutputs == nil, !outputs.isEmpty { persistOutputs() }
        if savedInputs == nil, !inputs.isEmpty { persistInputs() }
        if savedSends == nil, !sends.isEmpty { persistSends() }
        if volumeKeyOutputID == nil, let first = outputs.first {
            volumeKeyOutputID = first.id
        }
    }

    private struct LegacyInputSends: Decodable {
        let id: UUID
        let sends: [UUID]?
    }

    /// Переносит посылы из первой версии, где они хранились внутри входов.
    private static func legacySends(from data: Data?) -> [SendConfig] {
        guard let data,
              let inputs = try? JSONDecoder().decode([LegacyInputSends].self, from: data) else {
            return []
        }
        return inputs.flatMap { input in
            (input.sends ?? []).map { SendConfig(inputID: input.id, outputID: $0) }
        }
    }

    // MARK: - Выходы

    func output(id: UUID) -> OutputConfig? {
        outputs.first { $0.id == id }
    }

    /// Выход, которым управляют клавиши громкости: выбранный или первый.
    var volumeKeyOutput: OutputConfig? {
        if let id = temporaryVolumeKeyOutputID, let output = output(id: id) {
            return output
        }
        if let id = volumeKeyOutputID, let output = output(id: id) {
            return output
        }
        return outputs.first
    }

    /// Переключает выход клавиш громкости на соседний по списку, по кругу.
    func selectAdjacentVolumeKeyOutput(offset: Int) {
        guard !outputs.isEmpty else { return }
        let currentID = volumeKeyOutput?.id
        let index = outputs.firstIndex { $0.id == currentID } ?? 0
        let nextIndex = (index + offset + outputs.count) % outputs.count
        volumeKeyOutputID = outputs[nextIndex].id
    }

    /// Имя выхода для UI; если имя пустое — его OSC-адрес.
    func outputName(for id: UUID) -> String {
        guard let output = output(id: id) else { return "" }
        return output.name.isEmpty ? output.oscAddress : output.name
    }

    /// Изменяет конфигурацию выхода и сохраняет весь список.
    func updateOutput(_ id: UUID, _ mutate: (inout OutputConfig) -> Void) {
        guard let i = outputs.firstIndex(where: { $0.id == id }) else { return }
        var updated = outputs
        mutate(&updated[i])
        outputs = updated
    }

    /// Добавляет выход с адресом `/output/<следующий номер>`.
    func appendOutput() {
        outputs.append(OutputConfig(name: "", oscAddress: OSCAddress.output(outputs.count), showInMain: true))
    }

    /// Удаляет выход; если он управлялся клавишами громкости — переназначает на другой.
    func removeOutput(id: UUID) {
        guard outputs.contains(where: { $0.id == id }) else { return }
        if volumeKeyOutputID == id {
            volumeKeyOutputID = outputs.first { $0.id != id }?.id
        }
        outputs.removeAll { $0.id == id }
        sends.removeAll { $0.outputID == id }
    }

    // MARK: - Входы

    func input(id: UUID) -> InputConfig? {
        inputs.first { $0.id == id }
    }

    func inputName(for id: UUID) -> String {
        input(id: id)?.name ?? ""
    }

    /// Подпись входа для UI: имя, иначе «Input N» по номеру канала, иначе «In N».
    func inputLabel(for id: UUID) -> String {
        guard let index = inputs.firstIndex(where: { $0.id == id }) else { return "" }
        let input = inputs[index]
        if !input.name.isEmpty { return input.name }
        if let last = input.oscAddress.split(separator: "/").last, let ch = Int(last) {
            return "Input \(ch + 1)"
        }
        return "In \(index + 1)"
    }

    /// Изменяет конфигурацию входа и сохраняет весь список.
    func updateInput(_ id: UUID, _ mutate: (inout InputConfig) -> Void) {
        guard let i = inputs.firstIndex(where: { $0.id == id }) else { return }
        var updated = inputs
        mutate(&updated[i])
        inputs = updated
    }

    func appendInput() {
        inputs.append(InputConfig(name: "", oscAddress: DefaultConfig.newInputAddress, type: .line, showInMain: true))
    }

    /// Настроен ли уже вход с таким OSC-адресом.
    func hasInput(address: String) -> Bool {
        let key = OSCAddress.normalized(address)
        return inputs.contains { OSCAddress.normalized($0.oscAddress) == key }
    }

    /// Настроен ли уже выход с таким OSC-адресом.
    func hasOutput(address: String) -> Bool {
        let key = OSCAddress.normalized(address)
        return outputs.contains { OSCAddress.normalized($0.oscAddress) == key }
    }

    func removeInput(id: UUID) {
        inputs.removeAll { $0.id == id }
        sends.removeAll { $0.inputID == id }
    }

    // MARK: - Посылы

    func send(id: UUID) -> SendConfig? {
        sends.first { $0.id == id }
    }

    /// Имя посыла для UI: заданное или «Вход → Выход».
    func sendName(for id: UUID) -> String {
        guard let send = send(id: id) else { return "" }
        if !send.name.isEmpty { return send.name }
        let from = inputLabel(for: send.inputID)
        let to = outputName(for: send.outputID)
        return "\(from) → \(to)"
    }

    /// Создаёт посыл, если такой маршрут ещё не существует.
    @discardableResult
    func appendSend(inputID: UUID, outputID: UUID) -> SendConfig? {
        guard input(id: inputID) != nil, output(id: outputID) != nil else { return nil }
        guard !sends.contains(where: { $0.inputID == inputID && $0.outputID == outputID }) else { return nil }
        let send = SendConfig(inputID: inputID, outputID: outputID)
        sends.append(send)
        return send
    }

    func updateSend(_ id: UUID, _ mutate: (inout SendConfig) -> Void) {
        guard let index = sends.firstIndex(where: { $0.id == id }) else { return }
        var updated = sends
        mutate(&updated[index])
        sends = updated
    }

    func removeSend(id: UUID) {
        sends.removeAll { $0.id == id }
    }

    // MARK: - Горячие клавиши

    /// Действующая комбинация: сохранённая или по умолчанию.
    func hotkey(for action: HotkeyAction) -> Hotkey {
        hotkeys[action.rawValue] ?? action.defaultHotkey
    }

    /// Сохраняет комбинацию действия (или её отключённое состояние).
    func setHotkey(_ hotkey: Hotkey, for action: HotkeyAction) {
        var updated = hotkeys
        updated[action.rawValue] = hotkey
        hotkeys = updated
    }

    /// Возвращает все комбинации к значениям по умолчанию.
    func resetHotkeys() {
        hotkeys = [:]
    }

    // MARK: - Первый запуск

    /// Отмечает мастер настройки пройденным: больше не показываем его при запуске.
    func completeSetup() {
        guard !setupCompleted else { return }
        setupCompleted = true
    }

    // MARK: - Сброс

    // MARK: - Пресеты

    /// Сохраняет текущие настройки под именем; пресет с таким же именем обновляется.
    /// Добавляет пресеты из файла, не затирая одноимённые.
    func addPresets(_ incoming: [SettingsPreset]) {
        for preset in incoming where !presets.contains(where: {
            $0.name.caseInsensitiveCompare(preset.name) == .orderedSame
        }) {
            presets.append(preset)
        }
    }

    func savePreset(named name: String,
                    roomEQs: [String: RoomEQState] = [:],
                    mixer: SettingsPreset.MixerSnapshot? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let snapshot = makeSnapshot(roomEQs: roomEQs, mixer: mixer)
        if let index = presets.firstIndex(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            presets[index].snapshot = snapshot
        } else {
            presets.append(SettingsPreset(name: trimmed, snapshot: snapshot))
        }
    }

    func apply(_ preset: SettingsPreset) {
        let s = preset.snapshot
        speakerBAddress = s.speakerBAddress
        dimAddress = s.dimAddress
        monoAddress = s.monoAddress
        watchDeviceConnection = s.watchDeviceConnection
        inputs = s.inputs
        outputs = s.outputs
        sends = s.sends
        showMuteButtons = s.showMuteButtons
        showSpeakerB = s.showSpeakerB
        showDim = s.showDim
        showMono = s.showMono
        showInputCompressor = s.showInputCompressor
        showInputEQ = s.showInputEQ
        showOutputCompressor = s.showOutputCompressor
        showOutputEQ = s.showOutputEQ
        showOutputRoomEQ = s.showOutputRoomEQ ?? true
        muteKeyAction = s.muteKeyAction
        volumeStepDB = s.volumeStepDB
        volumeKeyOutputID = s.volumeKeyOutputID
            .flatMap { id in s.outputs.contains { $0.id == id } ? id : nil }
            ?? s.outputs.first?.id
        unmuteOnVolumeChange = s.unmuteOnVolumeChange
        switchOutputWithArrowKeys = s.switchOutputWithArrowKeys ?? false
        muteOtherOutputsOnSwitch = s.muteOtherOutputsOnSwitch ?? false
        useFunctionKeys = s.useFunctionKeys
        webServerEnabled = s.webServerEnabled
        webServerPort = s.webServerPort
        webShowButtons = s.webShowButtons
        webShowInputs = s.webShowInputs
        webShowLevels = s.webShowLevels
        if let hotkeys = s.hotkeys {
            self.hotkeys = hotkeys
        }
        if let userPresets = s.roomEQUserPresets {
            roomEQUserPresets = userPresets
        }
        if let preferences = s.roomCorrectionPreferences {
            roomCorrectionPreferences = preferences
        }
    }

    func removePreset(id: UUID) {
        presets.removeAll { $0.id == id }
    }

    func replaceRoomEQUserPresets(_ presets: [RoomEQUserPreset]) {
        roomEQUserPresets = presets
    }

    func addRoomEQUserPreset(_ preset: RoomEQUserPreset) {
        roomEQUserPresets.insert(preset, at: 0)
    }

    func removeRoomEQUserPreset(id: UUID) {
        roomEQUserPresets.removeAll { $0.id == id }
    }

    func renameRoomEQUserPreset(id: UUID, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = roomEQUserPresets.firstIndex(where: { $0.id == id }) else { return }
        roomEQUserPresets[index].name = trimmed
    }

    private func makeSnapshot(roomEQs: [String: RoomEQState],
                              mixer: SettingsPreset.MixerSnapshot?) -> SettingsPreset.Snapshot {
        SettingsPreset.Snapshot(
            speakerBAddress: speakerBAddress,
            dimAddress: dimAddress,
            monoAddress: monoAddress,
            watchDeviceConnection: watchDeviceConnection,
            inputs: inputs,
            outputs: outputs,
            sends: sends,
            showMuteButtons: showMuteButtons,
            showSpeakerB: showSpeakerB,
            showDim: showDim,
            showMono: showMono,
            showInputCompressor: showInputCompressor,
            showInputEQ: showInputEQ,
            showOutputCompressor: showOutputCompressor,
            showOutputEQ: showOutputEQ,
            showOutputRoomEQ: showOutputRoomEQ,
            muteKeyAction: muteKeyAction,
            volumeStepDB: volumeStepDB,
            volumeKeyOutputID: volumeKeyOutputID,
            unmuteOnVolumeChange: unmuteOnVolumeChange,
            switchOutputWithArrowKeys: switchOutputWithArrowKeys,
            muteOtherOutputsOnSwitch: muteOtherOutputsOnSwitch,
            useFunctionKeys: useFunctionKeys,
            webServerEnabled: webServerEnabled,
            webServerPort: webServerPort,
            webShowButtons: webShowButtons,
            webShowInputs: webShowInputs,
            webShowLevels: webShowLevels,
            hotkeys: hotkeys,
            roomEQs: roomEQs.isEmpty ? nil : roomEQs,
            roomEQUserPresets: roomEQUserPresets,
            roomCorrectionPreferences: roomCorrectionPreferences,
            version: 2,
            mixer: mixer
        )
    }

    func resetToDefaults() {
        speakerBAddress = OSCAddress.Defaults.speakerB
        dimAddress = OSCAddress.Defaults.dim
        monoAddress = OSCAddress.Defaults.mono
        watchDeviceConnection = true
        inputs = DefaultConfig.inputs()
        outputs = DefaultConfig.outputs()
        sends = []
        showMuteButtons = true
        showSpeakerB = true
        showDim = true
        showMono = true
        showInputCompressor = true
        showInputEQ = true
        showOutputCompressor = true
        showOutputEQ = true
        showOutputRoomEQ = true
        muteKeyAction = .dim
        volumeStepDB = DefaultConfig.volumeStepDB
        volumeKeyOutputID = outputs.first?.id
        unmuteOnVolumeChange = true
        switchOutputWithArrowKeys = false
        muteOtherOutputsOnSwitch = false
        useFunctionKeys = false
        hotkeys = [:]
        webServerEnabled = false
        webServerPort = DefaultConfig.webServerPort
        webShowButtons = true
        webShowInputs = true
        webShowLevels = true
    }

    // MARK: - Persist

    private func persistInputs() {
        storage.setEncodable(inputs, for: .inputs)
    }

    private func persistOutputs() {
        storage.setEncodable(outputs, for: .outputs)
    }

    private func persistSends() {
        storage.setEncodable(sends, for: .sends)
    }
}
