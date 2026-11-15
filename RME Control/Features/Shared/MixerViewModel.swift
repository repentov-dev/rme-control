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
