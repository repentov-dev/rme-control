import Foundation

/// ViewModel «живого» пульта, общая для поповера, HUD и панели уровней.
/// Отдаёт View готовые к показу данные (громкость, mute, Dim/Mono, +48V/Inst, уровни)
/// и превращает действия пользователя в команды `MixerService`.
/// Своего состояния не хранит: View, читающие её свойства, через Observation
/// подписываются ровно на те поля `AppSettings`/`MixerState`, которые показывают.
@MainActor
final class MixerViewModel {
    private let settings: AppSettings
    private let state: MixerState
    private let mixer: MixerService

    init(settings: AppSettings, state: MixerState, mixer: MixerService) {
        self.settings = settings
        self.state = state
        self.mixer = mixer
    }

    // MARK: - Подключение

    var isConnected: Bool { state.isConnected }
    var deviceOffline: Bool { state.deviceOffline }
    var deviceName: String { state.deviceName }

    // MARK: - Выходы

    var outputs: [OutputConfig] { settings.outputs }
    var showMuteButtons: Bool { settings.showMuteButtons }

    func outputName(for id: UUID) -> String {
        settings.outputName(for: id)
    }

    func outputSymbolName(for id: UUID) -> String {
        (settings.output(id: id)?.icon ?? .speaker).symbolName
    }

    func outputValue(_ id: UUID) -> Double {
        state.output(id).value
    }

    func isOutputMuted(_ id: UUID) -> Bool {
        state.output(id).muted
    }

    /// Меняет положение фейдера только локально (во время перетаскивания слайдера).
    func setOutputValueLocally(_ value: Double, for id: UUID) {
        state.updateOutput(id) { $0.value = value }
    }

    func sendVolume(_ value: Double, for id: UUID) {
        mixer.sendVolume(outputID: id, value: value)
    }

    func setOutputMuted(_ muted: Bool, for id: UUID) {
        mixer.setMuted(outputID: id, muted: muted)
    }

    /// Пока пользователь тянет фейдер, входящие значения из TotalMix его не двигают.
    func setDragInProgress(_ inProgress: Bool) {
        state.mainDragInProgress = inProgress
    }

    // MARK: - Посылы

    var sends: [SendConfig] { settings.sends }
    var visibleSends: [SendConfig] { settings.sends.filter(\.showInMain) }

    func sendName(for id: UUID) -> String {
        settings.sendName(for: id)
    }

    func sendValue(_ id: UUID) -> Double {
        state.send(id).value
    }

    func sendDB(_ id: UUID) -> Double {
        state.send(id).db
    }

    func isSendMuted(_ id: UUID) -> Bool {
        state.send(id).muted
    }

    /// Меняет положение фейдера посыла только локально во время перетаскивания.
    func setSendValueLocally(_ value: Double, for id: UUID) {
        state.updateSend(id) {
            $0.value = value
            $0.db = FaderMath.db(for: value)
            $0.muted = false
        }
    }

    func setSendVolume(_ value: Double, for id: UUID) {
        mixer.setSendVolume(id: id, value: value)
    }

    func setSendMuted(_ muted: Bool, for id: UUID) {
        mixer.setSendMuted(id: id, muted: muted)
    }

    func setSendDragInProgress(_ inProgress: Bool, for id: UUID) {
        if inProgress {
            state.sendDragInProgress.insert(id)
        } else {
            state.sendDragInProgress.remove(id)
        }
    }

    // MARK: - Клавиши громкости

    var volumeKeyOutputID: UUID? { settings.volumeKeyOutput?.id }

    /// Временно навести клавиши громкости на другой выход (замер) или вернуть прежний.
    /// `nil` снимает переназначение — настройка пользователя не трогается.
    func setTemporaryVolumeKeyOutput(_ id: UUID?) {
        settings.temporaryVolumeKeyOutputID = id
    }
    var unmuteOnVolumeChange: Bool { settings.unmuteOnVolumeChange }

    var isVolumeKeyOutputMuted: Bool {
        volumeKeyOutputID.map { state.output($0).muted } ?? false
    }

    // MARK: - Control Room

    var showSpeakerB: Bool { settings.showSpeakerB }
    var showDim: Bool { settings.showDim }
    var showMono: Bool { settings.showMono }
    var speakerBOn: Bool { state.speakerBOn }
    var dimOn: Bool { state.dimOn }
    var monoOn: Bool { state.monoOn }

    /// Отправляет EQ и Dynamics всех каналов в TotalMix.
    func pushChannelProcessing() { mixer.pushChannelProcessing() }

    /// Живое состояние пульта для пресета и его восстановление.
    func mixerSnapshot() -> SettingsPreset.MixerSnapshot { mixer.mixerSnapshot() }
    func applyMixerSnapshot(_ snapshot: SettingsPreset.MixerSnapshot) { mixer.applyMixerSnapshot(snapshot) }
    func applyChannelProcessing(_ map: [String: SettingsPreset.ChannelProcessing]) {
        mixer.applyChannelProcessing(map)
    }

    func toggleSpeakerB() { mixer.toggleSpeakerB() }
    func toggleDim() { mixer.toggleDim() }
    func toggleMono() { mixer.toggleMono() }

    // MARK: - Входы

    var inputs: [InputConfig] { settings.inputs }

    func inputLabel(for id: UUID) -> String {
        settings.inputLabel(for: id)
    }

    func inputName(for id: UUID) -> String {
        settings.inputName(for: id)
    }

    func renameInput(_ id: UUID, to name: String) {
        settings.updateInput(id) { $0.name = name.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    func inputType(_ id: UUID) -> InputType? {
        settings.input(id: id)?.type
    }

    func isPhantomOn(_ id: UUID) -> Bool {
        state.input(id).phantom
    }

    func isInstrumentOn(_ id: UUID) -> Bool {
        state.input(id).instrument
    }

    func togglePhantom(_ id: UUID) { mixer.togglePhantom(inputID: id) }
    func toggleInstrument(_ id: UUID) { mixer.toggleInstrument(inputID: id) }

    // MARK: - Компрессор входов и выходов

    /// Кнопки компрессора/EQ показывать у входов и выходов (настройки RME Control).
    var showInputCompressor: Bool { settings.showInputCompressor }
    var showInputEQ: Bool { settings.showInputEQ }
    var showOutputCompressor: Bool { settings.showOutputCompressor }
    var showOutputEQ: Bool { settings.showOutputEQ }
    var showOutputRoomEQ: Bool { settings.showOutputRoomEQ }

    /// Адресат Room EQ для выхода: его адрес, парный канал и подпись.
    func roomEQTarget(for id: UUID) -> RoomEQTarget? {
        guard let output = outputs.first(where: { $0.id == id }), !output.oscAddress.isEmpty else {
            return nil
        }
        return RoomEQTarget(
            address: output.oscAddress,
            partner: output.resolvedPartnerAddress,
            label: output.name.isEmpty ? output.oscAddress : output.name,
            isHeadphone: output.icon == .headphones
        )
    }

    /// Состояние Room EQ по конкретному OSC-адресу (для правого канала пары).
    func roomEQState(at address: String) -> RoomEQState {
        state.roomEQ(address)
    }

    /// Включён ли Room EQ у выхода — для подсветки кнопки в поповере.
    func isRoomEQOn(_ target: RoomEQTarget) -> Bool {
        state.roomEQ(target.address).enabled
    }

    /// Есть ли у канала компрессор: у входов — только комбо-входы, у выходов — все.
    func hasCompressor(_ target: CompressorTarget) -> Bool {
        switch target.bus {
        case .input:
            return settings.showInputCompressor && (settings.input(id: target.id)?.type.showsCompressor ?? false)
        case .output:
            return settings.showOutputCompressor && settings.output(id: target.id) != nil
        }
    }

    /// Компрессор включён (состояние из TotalMix).
    func isCompressorOn(_ target: CompressorTarget) -> Bool {
        compressor(target).enabled
    }

    func compressor(_ target: CompressorTarget) -> CompressorState {
        switch target.bus {
        case .input: return state.input(target.id).compressor
        case .output: return state.output(target.id).compressor
        }
    }

    func toggleCompressor(_ target: CompressorTarget) { mixer.toggleCompressor(target) }

    func setCompressorEnabled(_ target: CompressorTarget, _ enabled: Bool) {
        mixer.setCompressorEnabled(target, enabled: enabled)
    }

    func setCompressorParameter(_ target: CompressorTarget, _ parameter: CompressorParameter, _ value: Double) {
        mixer.setCompressorParameter(target, parameter: parameter, value: value)
    }

    func setDynamicsMode(_ target: CompressorTarget, _ mode: DynamicsMode) {
        mixer.setDynamicsMode(target, mode: mode)
    }

    /// Уровень на входе компрессора: уровень входа или уровень выхода в dBFS.
    func compressorInputLevel(_ target: CompressorTarget) -> Double {
        switch target.bus {
        case .input: return state.level(target.id)
        case .output: return state.outputLevel(target.id)
        }
    }

    /// Насколько компрессор ослабляет сигнал, dB (оценка по кривой и уровню входа).
    func compressorGainReduction(_ target: CompressorTarget) -> Double {
        compressor(target).gainReduction(forInputLevel: compressorInputLevel(target))
    }

    /// Ожидаемый уровень на выходе компрессора, dBFS (вход + make-up − ослабление).
    func compressorOutputLevel(_ target: CompressorTarget) -> Double {
        compressorInputLevel(target) + compressor(target).gain - compressorGainReduction(target)
    }

    // MARK: - EQ и Low Cut

    /// Подпись канала в заголовке EQ-панели (имя входа или выхода).
    func eqLabel(_ target: EQTarget) -> String {
        switch target.bus {
        case .input: return inputLabel(for: target.id)
        case .output: return outputName(for: target.id)
        }
    }

    func eq(_ target: EQTarget) -> EQState {
        switch target.bus {
        case .input: return state.input(target.id).eq
        case .output: return state.output(target.id).eq
        }
    }

    func isEQOn(_ target: EQTarget) -> Bool {
        eq(target).enabled
    }

    func setEQEnabled(_ target: EQTarget, _ enabled: Bool) {
        mixer.setEQEnabled(target, enabled: enabled)
    }

    func setLowCutEnabled(_ target: EQTarget, _ enabled: Bool) {
        mixer.setLowCutEnabled(target, enabled: enabled)
    }

    func setEQParameter(_ target: EQTarget, _ parameter: EQParameter, _ value: Double) {
        mixer.setEQParameter(target, parameter, value: value)
    }

    // MARK: - Room EQ

    /// Состояние Room EQ того канала, который сейчас показан в окне.
    func roomEQ(_ target: RoomEQTarget, channel: RoomEQChannel) -> RoomEQState {
        state.roomEQ(target.shownAddress(for: channel))
    }

    /// Есть ли у выхода парный адрес: без него выбор LEFT/RIGHT не имеет смысла.
    func hasPartner(_ target: RoomEQTarget) -> Bool {
        target.hasPartner
    }

    var roomCorrectionPreferences: RoomCorrectionPreferences { settings.roomCorrectionPreferences }

    func saveRoomCorrectionPreferences(_ preferences: RoomCorrectionPreferences) {
        settings.roomCorrectionPreferences = preferences
    }

    var roomEQUserPresets: [RoomEQUserPreset] { settings.roomEQUserPresets }

    func saveRoomEQUserPreset(name: String, bands: [RoomEQPresetBand],
                              preamp: Double, mode: RoomCorrectionChannel,
                              delayLeft: Double? = nil, delayRight: Double? = nil,
                              calibrationLeft: Double? = nil, calibrationRight: Double? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        settings.addRoomEQUserPreset(RoomEQUserPreset(
            name: trimmed,
            mode: mode.rawValue,
            bands: bands,
            preamp: preamp,
            delayLeft: delayLeft,
            delayRight: delayRight,
            calibrationLeft: calibrationLeft,
            calibrationRight: calibrationRight
        ))
    }

    func deleteRoomEQUserPreset(id: UUID) {
        settings.removeRoomEQUserPreset(id: id)
    }

    func renameRoomEQUserPreset(id: UUID, name: String) {
        settings.renameRoomEQUserPreset(id: id, name: name)
    }

    /// Связывает Room EQ стереопары: копирует настройки выбранного канала
    /// во второй. Дальше правки уходят в оба, пока связь включена.
    func linkRoomEQ(_ target: RoomEQTarget, from channel: RoomEQChannel) {
        guard let partner = target.partner else { return }
        let source = target.shownAddress(for: channel)
        let destination = source == target.address ? partner : target.address
        mixer.syncRoomEQ(from: source, to: destination)
    }

    var roomEQStates: [String: RoomEQState] { state.roomEQs }

    func applyRoomEQStates(_ states: [String: RoomEQState]) {
        mixer.applyRoomEQStates(states)
    }

    func setRoomEQEnabled(_ target: RoomEQTarget, channel: RoomEQChannel, _ enabled: Bool) {
        mixer.setRoomEQEnabled(target, channel: channel, enabled: enabled)
    }

    func requestCalibrationState() {
        mixer.requestCalibrationState()
    }

    func calibrationRoutingState() -> CalibrationRoutingState {
        mixer.calibrationRoutingState()
    }

    func applyCalibrationRouting(outputLeft: Int, outputRight: Int, channelCount: Int) {
        mixer.applyCalibrationRouting(outputLeft: outputLeft, outputRight: outputRight,
                                      channelCount: channelCount)
    }

    func restoreCalibrationRouting(_ state: CalibrationRoutingState, channelCount: Int) {
        mixer.restoreCalibrationRouting(state, channelCount: channelCount)
    }

    func setRoomEQParameter(_ target: RoomEQTarget, channel: RoomEQChannel,
                            _ parameter: RoomEQParameter, _ value: Double) {
        mixer.setRoomEQParameter(target, channel: channel, parameter: parameter, value: value)
    }

    func setRoomEQMix(_ target: RoomEQTarget, channel: RoomEQChannel, _ mix: Double) {
        mixer.setRoomEQMix(target, channel: channel, mix: mix)
    }

    func applyRoomEQBands(_ target: RoomEQTarget, channel: RoomEQChannel,
                          _ bands: [RoomEQBand], preamp: Double) {
        mixer.applyRoomEQBands(target, channel: channel, bands: bands, preamp: preamp)
    }

    /// Входы с +48V/Inst для поповера: сгруппированы по типу, по 4 в строке.
    var popoverInputRows: [[UUID]] {
        InputType.allCases
            .compactMap { type in
                let ids = inputs
                    .filter { $0.showInPopover && $0.type == type }
                    .map(\.id)
                return ids.isEmpty ? nil : ids
            }
            .flatMap { $0.chunked(into: 4) }
    }

    // MARK: - Уровни

    /// Входы, которые показываются на панели уровней.
    var levelInputs: [InputConfig] { settings.inputs.filter(\.showInMain) }

    func micLevel(_ id: UUID) -> Double {
        state.level(id)
    }

    /// Снимок всех уровней (для подписей, которые обновляются реже полосок).
    var levelsSnapshot: [UUID: Double] { state.micLevels }
}
