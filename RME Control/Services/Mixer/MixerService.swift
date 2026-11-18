import Foundation
import Combine

/// Бизнес-логика пульта — единственное место, где действия пользователя
/// (из поповера, веб-пульта или с клавиатуры) превращаются в OSC-команды,
/// а входящие OSC-сообщения TotalMix — в изменения `MixerState`.
/// Также добавляет и удаляет каналы, потому что это меняет одновременно
/// `AppSettings` и `MixerState`.
struct CalibrationRoutingState: Sendable {
    var mutes: [Int: Bool]
    /// playback -> submix -> уровень посыла в dB.
    var sends: [Int: [Int: Double]]
}

struct CalibrationSend: Hashable, Sendable {
    let playback: Int
    let submix: Int
}

@MainActor
final class MixerService {
    /// Аудиоинтерфейс подключился (передаётся имя устройства).
    let deviceConnectedTrigger = PassthroughSubject<String, Never>()
    /// Аудиоинтерфейс отключился (передаётся имя устройства).
    let deviceDisconnectedTrigger = PassthroughSubject<String, Never>()
    /// Уровень на входе с указанным id дошёл до 0 dBFS.
    let clipTrigger = PassthroughSubject<UUID, Never>()
    /// Громкость выхода изменилась в TotalMix (передаётся id выхода).
    let outputVolumeChangedTrigger = PassthroughSubject<UUID, Never>()
    /// Dim переключён в TotalMix или в приложении (передаётся новое состояние).
    let dimChangedTrigger = PassthroughSubject<Bool, Never>()
    /// Mono переключён в TotalMix или в приложении (передаётся новое состояние).
    let monoChangedTrigger = PassthroughSubject<Bool, Never>()

    private static let stateResponseWindow: TimeInterval = 0.5
    private static let volumeChangeThreshold: Double = 0.05

    private let osc: OSCSending
    private var outputMutes: [Int: Bool] = [:]
    private var playbackSendLevels: [Int: [Int: Double]] = [:]
    private var touchedCalibrationSends: Set<CalibrationSend> = []
    private let settings: AppSettings
    private let state: MixerState
    private var lastStateRequest = Date.distantPast

    init(osc: OSCSending, settings: AppSettings, state: MixerState) {
        self.osc = osc
        self.settings = settings
        self.state = state
        state.syncOutputs(ids: settings.outputs.map(\.id))
        state.syncInputs(ids: settings.inputs.map(\.id))
        state.syncSends(ids: settings.sends.map(\.id))
    }

    // MARK: - Команды: выходы

    func sendVolume(outputID: UUID, value: Double) {
        guard let output = settings.output(id: outputID), !output.oscAddress.isEmpty else { return }
        osc.send(output.oscAddress + OSCAddress.Suffix.faderLinear, Float(min(max(value, 0), 1)))
    }

    func sendMute(outputID: UUID, muted: Bool) {
        guard let output = settings.output(id: outputID), !output.oscAddress.isEmpty else { return }
        osc.send(output.oscAddress + OSCAddress.Suffix.mute, muted ? 1.0 : 0.0)
    }

    /// Ставит громкость (0…1) локально и отправляет в TotalMix.
    /// Если включено «снимать mute при изменении громкости», канал размьючивается.
    func setVolume(outputID: UUID, value: Double) {
        guard settings.output(id: outputID) != nil else { return }
        let v = min(max(value, 0), 1)
        state.updateOutput(outputID) { $0.value = v }
        if settings.unmuteOnVolumeChange, state.output(outputID).muted {
            setMuted(outputID: outputID, muted: false)
        }
        sendVolume(outputID: outputID, value: v)
    }

    /// Ставит mute локально и отправляет в TotalMix.
    func setMuted(outputID: UUID, muted: Bool) {
        guard settings.output(id: outputID) != nil else { return }
        state.updateOutput(outputID) { $0.muted = muted }
        sendMute(outputID: outputID, muted: muted)
    }

    func toggleMute(outputID: UUID) {
        setMuted(outputID: outputID, muted: !state.output(outputID).muted)
    }

    /// Оставляет звук только на выбранном выходе: остальные мьютит, выбранный размьючивает.
    func muteOtherOutputs(except outputID: UUID) {
        guard settings.output(id: outputID) != nil else { return }
        for output in settings.outputs {
            let muted = output.id != outputID
            if state.output(output.id).muted != muted {
                setMuted(outputID: output.id, muted: muted)
            }
        }
    }

    /// Шаг громкости в dB от текущего положения фейдера; снимает mute, если он был
    /// и это включено в настройках.
    func stepVolume(outputID: UUID, byDB delta: Double) {
        guard settings.output(id: outputID) != nil else { return }
        let current = state.output(outputID)
        if current.muted && settings.unmuteOnVolumeChange {
            setMuted(outputID: outputID, muted: false)
        }
        let newValue = FaderMath.position(forDB: FaderMath.db(for: current.value) + delta)
        state.updateOutput(outputID) { $0.value = newValue }
        sendVolume(outputID: outputID, value: newValue)
    }

    // MARK: - Команды: посылы

    /// Создаёт посыл из входа на выход и ставит его на 0 dB.
    func addSend(inputID: UUID, outputID: UUID) {
        guard let send = settings.appendSend(inputID: inputID, outputID: outputID),
              let address = sendAddress(for: send) else {
            return
        }
        state.syncSends(ids: settings.sends.map(\.id))
        state.updateSend(send.id) {
            $0.value = FaderMath.position(forDB: 0)
            $0.db = 0
            $0.muted = false
        }
        osc.send(address + OSCAddress.Suffix.fader, 0.0)
    }

    /// Убирает посыл из настроек и опускает его фейдер в TotalMix.
    func removeSend(id: UUID) {
        guard let send = settings.send(id: id) else { return }
        sendFader(for: send, db: -300)
        settings.removeSend(id: id)
        state.syncSends(ids: settings.sends.map(\.id))
    }

    /// Ставит уровень посыла в dB и отправляет его в TotalMix.
    func setSendVolume(id: UUID, value: Double) {
        guard let send = settings.send(id: id),
              let address = sendAddress(for: send) else { return }
        let clamped = min(max(value, 0), 1)
        state.updateSend(id) {
            $0.value = clamped
            $0.db = FaderMath.db(for: clamped)
            $0.muted = false
        }
        osc.send(address + OSCAddress.Suffix.fader, Float(FaderMath.db(for: clamped)))
    }

    func setSendMuted(id: UUID, muted: Bool) {
        guard let send = settings.send(id: id),
              let address = sendAddress(for: send) else { return }
        state.updateSend(id) { $0.muted = muted }
        if muted {
            sendFader(for: send, db: -300)
        } else {
            let db = FaderMath.db(for: state.send(id).value)
            state.updateSend(id) { $0.db = db }
            osc.send(address + OSCAddress.Suffix.fader, Float(db))
        }
    }

    func toggleSendMute(id: UUID) {
        setSendMuted(id: id, muted: !state.send(id).muted)
    }

    /// Шаг громкости посыла в dB; снимает mute, если он был.
    func stepSendVolume(id: UUID, byDB delta: Double) {
        guard settings.send(id: id) != nil else { return }
        let current = state.send(id)
        let baseDB = current.muted ? FaderMath.db(for: current.value) : current.db
        let newValue = FaderMath.position(forDB: baseDB + delta)
        setSendVolume(id: id, value: newValue)
    }

    func sendAddress(for send: SendConfig) -> String? {
        guard let input = settings.input(id: send.inputID),
              let output = settings.output(id: send.outputID) else { return nil }
        return OSCAddress.send(inputAddress: input.oscAddress, outputAddress: output.oscAddress)
    }

    private func sendFader(for send: SendConfig, db: Double) {
        guard let address = sendAddress(for: send) else { return }
        osc.send(address + OSCAddress.Suffix.fader, Float(db))
    }

    // MARK: - Команды: Control Room

    func toggleDim() {
        state.dimOn.toggle()
        dimChangedTrigger.send(state.dimOn)
        osc.send(settings.dimAddress, state.dimOn ? 1.0 : 0.0)
    }

    func toggleMono() {
        state.monoOn.toggle()
        monoChangedTrigger.send(state.monoOn)
        osc.send(settings.monoAddress, state.monoOn ? 1.0 : 0.0)
    }

    func toggleSpeakerB() {
        state.speakerBOn.toggle()
        osc.send(settings.speakerBAddress, state.speakerBOn ? 1.0 : 0.0)
    }

    /// Просит TotalMix прислать полное текущее состояние.
    func requestState() {
        lastStateRequest = Date()
        osc.send(OSCAddress.requestAll, 1.0)
    }

    // MARK: - Команды: входы

    func togglePhantom(inputID: UUID) {
        guard let input = settings.input(id: inputID), input.type.hasPhantom else { return }
        state.updateInput(inputID) { $0.phantom.toggle() }
        osc.send(input.oscAddress + OSCAddress.Suffix.phantom, state.input(inputID).phantom ? 1.0 : 0.0)
    }

    func toggleInstrument(inputID: UUID) {
        guard let input = settings.input(id: inputID), input.type.hasInstrument else { return }
        state.updateInput(inputID) { $0.instrument.toggle() }
        osc.send(input.oscAddress + OSCAddress.Suffix.instrument, state.input(inputID).instrument ? 1.0 : 0.0)
    }

    // MARK: - Команды: компрессор входа или выхода

    func setCompressorEnabled(_ target: CompressorTarget, enabled: Bool) {
        guard let address = compressorAddress(for: target) else { return }
        updateCompressor(target) { $0.enabled = enabled }
        osc.send(address + OSCAddress.Dynamics.enable, enabled ? 1.0 : 0.0)
    }

    func toggleCompressor(_ target: CompressorTarget) {
        guard compressorAddress(for: target) != nil else { return }
        setCompressorEnabled(target, enabled: !compressorState(target).enabled)
    }

    /// Меняет параметр компрессора: значение ограничивается диапазоном и уходит в TotalMix.
    func setCompressorParameter(_ target: CompressorTarget, parameter: CompressorParameter, value: Double) {
        guard let address = compressorAddress(for: target) else { return }
        var compressor = compressorState(target)
        compressor.set(parameter, value: value)
        let clamped = compressor.value(for: parameter)
        updateCompressor(target) { $0.set(parameter, value: clamped) }
        osc.send(address + parameter.oscSuffix, Float(clamped))
    }

    /// Адрес канала для секции Dynamics; у входов компрессор доступен только комбо-входам.
    private func compressorAddress(for target: CompressorTarget) -> String? {
        let address: String?
        switch target.bus {
        case .input:
            guard let input = settings.input(id: target.id), input.type.showsCompressor else { return nil }
            address = input.oscAddress
        case .output:
            address = settings.output(id: target.id)?.oscAddress
        }
        guard let address, !address.isEmpty else { return nil }
        return address
    }

    private func compressorState(_ target: CompressorTarget) -> CompressorState {
        switch target.bus {
        case .input: return state.input(target.id).compressor
        case .output: return state.output(target.id).compressor
        }
    }

    private func updateCompressor(_ target: CompressorTarget, _ mutate: (inout CompressorState) -> Void) {
        switch target.bus {
        case .input: state.updateInput(target.id) { mutate(&$0.compressor) }
        case .output: state.updateOutput(target.id) { mutate(&$0.compressor) }
        }
    }

    // MARK: - Команды: EQ и Low Cut

    func setEQEnabled(_ target: EQTarget, enabled: Bool) {
        guard let address = channelAddress(for: target) else { return }
        updateEQ(target) { $0.enabled = enabled }
        osc.send(address + OSCAddress.EQ.enable, enabled ? 1.0 : 0.0)
    }

    func setLowCutEnabled(_ target: EQTarget, enabled: Bool) {
        guard let address = channelAddress(for: target) else { return }
        updateEQ(target) { $0.lowCutEnabled = enabled }
        osc.send(address + OSCAddress.EQ.lowCutEnable, enabled ? 1.0 : 0.0)
    }

    /// Меняет параметр EQ: значение ограничивается диапазоном и уходит в TotalMix.
    func setEQParameter(_ target: EQTarget, _ parameter: EQParameter, value: Double) {
        guard let address = channelAddress(for: target) else { return }
        var eq = eqState(target)
        eq.set(parameter, value: value)
        let clamped = eq.value(for: parameter)
        updateEQ(target) { $0.set(parameter, value: clamped) }
        osc.send(address + parameter.oscSuffix, Float(clamped))
    }

    // MARK: - Room EQ

    func setRoomEQEnabled(_ target: RoomEQTarget, channel: RoomEQChannel, enabled: Bool) {
        for address in target.addresses(for: channel) {
            if enabled {
                var restore: Double?
                state.updateRoomEQ(address) { room in
                    room.enabled = true
                    if let saved = room.calibrationBeforeBypass {
                        room.volumeCalibration = saved
                        room.calibrationBeforeBypass = nil
                        restore = saved
                    }
                }
                osc.send(address + OSCAddress.RoomEQ.enable, 1.0)
                if let restore {
                    osc.send(address + OSCAddress.RoomEQ.gain, Float(restore))
                }
            } else {
                state.updateRoomEQ(address) { room in
                    if room.enabled, room.calibrationBeforeBypass == nil {
                        room.calibrationBeforeBypass = room.volumeCalibration
                    }
                    room.enabled = false
                    room.volumeCalibration = 0
                }
                osc.send(address + OSCAddress.RoomEQ.enable, 0.0)
                osc.send(address + OSCAddress.RoomEQ.gain, 0.0)
            }
        }
    }

    private func handlePlaybackMatrix(_ address: String, _ value: Float) -> Bool {
        let lower = address.lowercased()
        guard lower.hasPrefix("/mix/pb/") else { return false }
        let parts = address.split(separator: "/")
        guard parts.count == 5,
              let playback = Int(parts[2]),
              let submix = Int(parts[3]) else { return true }
        switch parts[4].lowercased() {
        case "fader":
            playbackSendLevels[playback, default: [:]][submix] = Double(value)
        case "faderlin":
            // Если пришёл только линейный уровень, переводим его в dB.
            playbackSendLevels[playback, default: [:]][submix] = FaderMath.db(for: Double(value))
        default:
            break
        }
        return true
    }

    func requestCalibrationState() {
        osc.send(OSCAddress.requestAll, 1.0)
    }

    func calibrationRoutingState() -> CalibrationRoutingState {
        CalibrationRoutingState(mutes: outputMutes, sends: playbackSendLevels)
    }

    /// На время замера: звук идёт в playback 1/2, посыл 0 дБ на выбранный
    /// выход, остальные выходы замьючены. Громкости и mute playback не трогаем.
    func applyCalibrationRouting(outputLeft: Int, outputRight: Int, channelCount: Int) {
        for channel in 0..<max(channelCount, 0) {
            setCalibrationMute(channel, muted: !(channel == outputLeft || channel == outputRight))
        }
        for (playback, submix) in [(0, outputLeft), (1, outputRight)] {
            osc.send("/mix/pb/\(playback)/\(submix)/fader", 0.0)
            touchedCalibrationSends.insert(CalibrationSend(playback: playback, submix: submix))
        }
    }

    func restoreCalibrationRouting(_ state: CalibrationRoutingState, channelCount: Int) {
        for channel in 0..<max(channelCount, 0) {
            setCalibrationMute(channel, muted: state.mutes[channel] ?? false)
        }
        for send in touchedCalibrationSends {
            // Если состояние не пришло, возвращаем типичные 0 дБ, а не минимум.
            let level = state.sends[send.playback]?[send.submix] ?? 0
            osc.send("/mix/pb/\(send.playback)/\(send.submix)/fader", Float(level))
            playbackSendLevels[send.playback, default: [:]][send.submix] = level
        }
        touchedCalibrationSends.removeAll()
    }

    /// mute — это set: 1 мьютит, 0 снимает. Никаких toggle-сравнений:
    /// иначе при смене выхода «лишние» каналы мьютились повторно.
    private func setCalibrationMute(_ channel: Int, muted: Bool) {
        osc.send("/output/\(channel)/mute", muted ? 1.0 : 0.0)
        outputMutes[channel] = muted
    }

    var roomEQStates: [String: RoomEQState] { state.roomEQs }

    /// Восстанавливает полное состояние Room EQ по OSC-адресам (из пресета).
    func applyRoomEQStates(_ states: [String: RoomEQState]) {
        for (address, roomState) in states {
            let base = OSCAddress.normalized(address)
            osc.send(base + OSCAddress.RoomEQ.enable, roomState.enabled ? 1.0 : 0.0)
            osc.send(base + OSCAddress.RoomEQ.delay, Float(roomState.delay))
            osc.send(base + OSCAddress.RoomEQ.crossfeed, Float(roomState.crossfeed))
            osc.send(base + OSCAddress.RoomEQ.gain, Float(roomState.volumeCalibration))
            for number in 1...RoomEQState.bandCount {
                let band = roomState.band(number)
                osc.send(base + RoomEQParameter.bandFrequency(number).oscSuffix, Float(band.frequency))
                osc.send(base + RoomEQParameter.bandGain(number).oscSuffix, Float(band.gain))
                osc.send(base + RoomEQParameter.bandQ(number).oscSuffix, Float(band.q))
                osc.send(base + RoomEQParameter.bandType(number).oscSuffix, Float(band.type))
            }
            state.updateRoomEQ(base) { $0 = roomState }
        }
    }

    func setRoomEQParameter(_ target: RoomEQTarget, channel: RoomEQChannel,
                            parameter: RoomEQParameter, value: Double) {
        for address in target.addresses(for: channel) {
            var room = state.roomEQ(address)
            room.set(parameter, value: value)
            let clamped = room.value(for: parameter)
            state.updateRoomEQ(address) { stored in
                if case .bandGain(let number) = parameter {
                    stored.setBandGainFromUser(number, value: clamped)
                } else {
                    stored.set(parameter, value: clamped)
                }
            }
            osc.send(address + parameter.oscSuffix, Float(clamped))
        }
    }

    /// Меняет Mix: 0 — обход коррекции, 1 — полное действие. Масштабируются
    /// только усиления полос; частоты, Q и типы не трогаются.
    func setRoomEQMix(_ target: RoomEQTarget, channel: RoomEQChannel, mix: Double) {
        let clamped = min(max(mix, 0), 1)
        for address in target.addresses(for: channel) {
            state.updateRoomEQ(address) { $0.setMix(clamped) }
            let room = state.roomEQ(address)
            for number in 1...RoomEQState.bandCount {
                osc.send(address + RoomEQParameter.bandGain(number).oscSuffix,
                         Float(room.band(number).gain))
            }
        }
    }

    /// Ставит полный набор девяти полос (пресет или измерение) и Mix = 100%.
    func applyRoomEQBands(_ target: RoomEQTarget, channel: RoomEQChannel,
                          bands: [RoomEQBand], preamp: Double) {
        guard bands.count == RoomEQState.bandCount else { return }
        let clampedPreamp = min(max(preamp, -24), 3)
        for address in target.addresses(for: channel) {
            state.updateRoomEQ(address) { room in
                room.applyBands(bands)
                room.volumeCalibration = clampedPreamp
            }
            let room = state.roomEQ(address)
            for number in 1...RoomEQState.bandCount {
                let band = room.band(number)
                osc.send(address + RoomEQParameter.bandFrequency(number).oscSuffix, Float(band.frequency))
                osc.send(address + RoomEQParameter.bandGain(number).oscSuffix, Float(band.gain))
                osc.send(address + RoomEQParameter.bandQ(number).oscSuffix, Float(band.q))
                osc.send(address + RoomEQParameter.bandType(number).oscSuffix, Float(band.type))
            }
            osc.send(address + OSCAddress.RoomEQ.gain, Float(clampedPreamp))
        }
        // Mix общий для окна: после применения пресета он снова 100% у обоих каналов.
        setRoomEQMix(target, channel: .both, mix: 1)
    }

    /// Копирует Room EQ одного канала стереопары в другой. Вызывается, когда
    /// пользователь связывает каналы кнопкой link: у пары становится один Room EQ.
    func syncRoomEQ(from source: String, to destination: String) {
        let from = OSCAddress.normalized(source)
        let to = OSCAddress.normalized(destination)
        guard from != to else { return }

        let room = state.roomEQ(from)
        state.updateRoomEQ(to) { $0 = room }

        osc.send(to + OSCAddress.RoomEQ.enable, room.enabled ? 1.0 : 0.0)
        osc.send(to + OSCAddress.RoomEQ.delay, Float(room.delay))
        osc.send(to + OSCAddress.RoomEQ.crossfeed, Float(room.crossfeed))
        osc.send(to + OSCAddress.RoomEQ.gain, Float(room.volumeCalibration))

        for number in 1...RoomEQState.bandCount {
            let band = room.band(number)
            osc.send(to + RoomEQParameter.bandFrequency(number).oscSuffix, Float(band.frequency))
            osc.send(to + RoomEQParameter.bandGain(number).oscSuffix, Float(band.gain))
            osc.send(to + RoomEQParameter.bandQ(number).oscSuffix, Float(band.q))
            osc.send(to + RoomEQParameter.bandType(number).oscSuffix, Float(band.type))
        }
    }

    private func handleRoomEQ(_ address: String, base: String, value: Float) -> Bool {
        guard !base.isEmpty else { return false }
        let normalizedBase = OSCAddress.normalized(base)
        let normalizedAddress = OSCAddress.normalized(address)
        guard normalizedAddress.hasPrefix(normalizedBase + "/") else { return false }
        let rest = String(normalizedAddress.dropFirst(normalizedBase.count))

        switch rest {
        case OSCAddress.RoomEQ.enable:
            state.updateRoomEQ(base) { $0.enabled = value > 0.5 }
            return true
        case OSCAddress.RoomEQ.delay:
            state.updateRoomEQ(base) { $0.set(.delay, value: Double(value)) }
            return true
        case OSCAddress.RoomEQ.crossfeed:
            state.updateRoomEQ(base) { $0.set(.crossfeed, value: Double(value)) }
            return true
        case OSCAddress.RoomEQ.gain:
            state.updateRoomEQ(base) { $0.set(.volumeCalibration, value: Double(value)) }
            return true
        default:
            break
        }

        guard rest.hasPrefix("/roomeq/band") else { return false }
        let numbers = rest.dropFirst("/roomeq/band".count)
        guard let band = Int(numbers.prefix(while: \.isNumber)) else { return false }
        let parameter: RoomEQParameter?
        switch String(numbers.drop(while: \.isNumber)) {
        case "freq": parameter = .bandFrequency(band)
        case "gain": parameter = .bandGain(band)
        case "q": parameter = .bandQ(band)
        case "type": parameter = .bandType(band)
        default: parameter = nil
        }
        guard let parameter else { return false }
        state.updateRoomEQ(base) { $0.set(parameter, value: Double(value)) }
        return true
    }

    private func channelAddress(for target: EQTarget) -> String? {
        let address: String?
        switch target.bus {
        case .input: address = settings.input(id: target.id)?.oscAddress
        case .output: address = settings.output(id: target.id)?.oscAddress
        }
        guard let address, !address.isEmpty else { return nil }
        return address
    }

    private func eqState(_ target: EQTarget) -> EQState {
        switch target.bus {
        case .input: return state.input(target.id).eq
        case .output: return state.output(target.id).eq
        }
    }

    private func updateEQ(_ target: EQTarget, _ mutate: (inout EQState) -> Void) {
        switch target.bus {
        case .input: state.updateInput(target.id) { mutate(&$0.eq) }
        case .output: state.updateOutput(target.id) { mutate(&$0.eq) }
        }
    }

    // MARK: - Конфигурация каналов

    /// Применяет новую конфигурацию каналов и синхронизирует `MixerState`.
    /// Посылы, которых нет в новой конфигурации, опускаются в TotalMix.
    func applyConfiguration(_ apply: () -> Void) {
        let oldSends = settings.sends.compactMap { send in
            sendAddress(for: send).map { (id: send.id, address: $0) }
        }
        apply()
        let newSendIDs = Set(settings.sends.map(\.id))
        for send in oldSends where !newSendIDs.contains(send.id) {
            osc.send(send.address + OSCAddress.Suffix.fader, -300)
        }
        state.syncOutputs(ids: settings.outputs.map(\.id))
        state.syncInputs(ids: settings.inputs.map(\.id))
        state.syncSends(ids: settings.sends.map(\.id))
        requestState()
    }

    func addOutput() {
        settings.appendOutput()
        state.syncOutputs(ids: settings.outputs.map(\.id))
    }

    func removeOutput(id: UUID) {
        for send in settings.sends where send.outputID == id {
            sendFader(for: send, db: -300)
        }
        settings.removeOutput(id: id)
        state.syncOutputs(ids: settings.outputs.map(\.id))
        state.syncSends(ids: settings.sends.map(\.id))
    }

    func addInput() {
        settings.appendInput()
        state.syncInputs(ids: settings.inputs.map(\.id))
    }

    func removeInput(id: UUID) {
        for send in settings.sends where send.inputID == id {
            sendFader(for: send, db: -300)
        }
        settings.removeInput(id: id)
        state.syncInputs(ids: settings.inputs.map(\.id))
        state.syncSends(ids: settings.sends.map(\.id))
    }

    /// Добавляет выбранные пользователем каналы из списка, который прислал
    /// TotalMix. Канал, у которого уже есть запись с таким же OSC-адресом,
    /// не трогается: имя, тип, иконка и видимость остаются пользовательскими.
    /// Добавленные каналы сразу видны в меню: их выбрали вручную.
    /// Возвращает счётчики добавленного.
    @discardableResult
    func addDiscoveredChannels(inputs discoveredInputs: [DiscoveredChannel],
                               outputs discoveredOutputs: [DiscoveredChannel]) -> ChannelScanResult {
        var result = ChannelScanResult()
        result.didHearTotalMix = true

        var inputs = settings.inputs
        var knownInputs = Set(inputs.map { OSCAddress.normalized($0.oscAddress) })
        for channel in discoveredInputs {
            let address = OSCAddress.normalized(channel.oscAddress)
            guard !knownInputs.contains(address) else { continue }
            inputs.append(InputConfig(name: channel.name,
                                      oscAddress: channel.oscAddress,
                                      type: .line,
                                      showInMain: true,
                                      showInPopover: true))
            knownInputs.insert(address)
            result.addedInputs += 1
        }

        var outputs = settings.outputs
        var knownOutputs = Set(outputs.map { OSCAddress.normalized($0.oscAddress) })
        for channel in discoveredOutputs {
            let address = OSCAddress.normalized(channel.oscAddress)
            guard !knownOutputs.contains(address) else { continue }
            outputs.append(OutputConfig(name: channel.name,
                                        oscAddress: channel.oscAddress,
                                        icon: .output,
                                        showInMain: true))
            knownOutputs.insert(address)
            result.addedOutputs += 1
        }

        if result.addedInputs > 0 {
            settings.inputs = inputs
            state.syncInputs(ids: inputs.map(\.id))
        }
        if result.addedOutputs > 0 {
            settings.outputs = outputs
            state.syncOutputs(ids: outputs.map(\.id))
        }
        if result.addedInputs > 0 || result.addedOutputs > 0 {
            requestState()
        }
        return result
    }

    func resetToDefaults() {
        for send in settings.sends {
            sendFader(for: send, db: -300)
        }
        settings.resetToDefaults()
        state.syncInputs(ids: settings.inputs.map(\.id))
        state.syncOutputs(ids: settings.outputs.map(\.id))
        state.syncSends(ids: settings.sends.map(\.id))
    }

    // MARK: - Входящие OSC-сообщения

    func handleOSCString(_ address: String, _ value: String) {
        if address == OSCAddress.deviceStatus {
            let cleaned = value.split(separator: "(").first?.trimmingCharacters(in: .whitespaces) ?? value
            state.deviceName = cleaned
        }
    }

    func handleOSCFloat(_ address: String, _ value: Float) {
        if address.lowercased().hasPrefix("/output/"), address.lowercased().hasSuffix("/mute") {
            let parts = address.split(separator: "/")
            if parts.count == 3, let channel = Int(parts[1]) {
                outputMutes[channel] = value > 0.5
            }
        }
        if handlePlaybackMatrix(address, value) { return }
        let on = value > 0.5
        if address == OSCAddress.connectionStatus {
            let wasPresent = state.devicePresent
            state.devicePresent = on
            let label = state.deviceName.isEmpty ? "Device" : state.deviceName
            if on && !wasPresent {
                deviceConnectedTrigger.send(label)
                requestState()
            } else if !on && wasPresent {
                deviceDisconnectedTrigger.send(label)
            }
            return
        }
        if address == settings.speakerBAddress { state.speakerBOn = on; return }
        if address == settings.dimAddress {
            let changed = state.dimOn != on
            state.dimOn = on
            if changed { dimChangedTrigger.send(on) }
            return
        }
        if address == settings.monoAddress {
            let changed = state.monoOn != on
            state.monoOn = on
            if changed { monoChangedTrigger.send(on) }
            return
        }

        for input in settings.inputs where input.type.hasPhantom && address == input.oscAddress + OSCAddress.Suffix.phantom {
            state.updateInput(input.id) { $0.phantom = on }
            return
        }
        for input in settings.inputs where input.type.hasInstrument && address == input.oscAddress + OSCAddress.Suffix.instrument {
            state.updateInput(input.id) { $0.instrument = on }
            return
        }
        for input in settings.inputs where input.type.showsCompressor {
            if handleDynamics(address, base: input.oscAddress, value: value, target: CompressorTarget(bus: .input, id: input.id)) {
                return
            }
        }
        for output in settings.outputs {
            if handleDynamics(address, base: output.oscAddress, value: value, target: CompressorTarget(bus: .output, id: output.id)) {
                return
            }
        }
        for input in settings.inputs {
            if handleEQ(address, base: input.oscAddress, value: value, target: EQTarget(bus: .input, id: input.id)) {
                return
            }
        }
        for output in settings.outputs {
            if handleEQ(address, base: output.oscAddress, value: value, target: EQTarget(bus: .output, id: output.id)) {
                return
            }
        }
        // Room EQ приходит и на парный канал пары, которого может не быть
        // в списке выходов (например, `/output/9` для DT990 на `/output/8`).
        var roomAddresses: [String] = []
        for output in settings.outputs {
            if !output.oscAddress.isEmpty { roomAddresses.append(output.oscAddress) }
            if let partner = output.resolvedPartnerAddress { roomAddresses.append(partner) }
        }
        for base in Set(roomAddresses) {
            if handleRoomEQ(address, base: base, value: value) {
                return
            }
        }

        for input in settings.inputs where address == input.resolvedLevelAddress {
            let level = Double(value)
            if level >= 0 {
                clipTrigger.send(input.id)
            }
            state.updateLevel(level, for: input.id)
            return
        }

        for output in settings.outputs where address == output.resolvedLevelAddress {
            state.updateOutputLevel(Double(value), for: output.id)
            return
        }

        for send in settings.sends {
            guard let base = sendAddress(for: send) else { continue }
            if address == base + OSCAddress.Suffix.fader {
                let db = Double(value)
                let silent = db <= -100
                let position = FaderMath.position(forDB: db)
                let dragging = state.sendDragInProgress.contains(send.id)
                state.updateSend(send.id) {
                    $0.db = db
                    $0.muted = silent
                    if !silent && !dragging {
                        $0.value = position
                    }
                }
                return
            }
            if address == base + OSCAddress.Suffix.faderLinear {
                let linear = min(max(Double(value), 0), 1)
                let silent = linear <= 0.0001
                let dragging = state.sendDragInProgress.contains(send.id)
                state.updateSend(send.id) {
                    $0.db = FaderMath.db(for: linear)
                    $0.muted = silent
                    if !silent && !dragging {
                        $0.value = linear
                    }
                }
                return
            }
            if address == base + OSCAddress.Suffix.mute {
                state.updateSend(send.id) { $0.muted = on }
                return
            }
        }

        for output in settings.outputs where address == output.oscAddress + OSCAddress.Suffix.volume {
            let db = Double(value)
            let position = FaderMath.position(forDB: db)
            let current = state.output(output.id)
            let movesFader = !state.mainDragInProgress && abs(current.value - position) > 0.002
            let volumeChanged = abs(current.db - db) > Self.volumeChangeThreshold
            let isStateResponse = Date().timeIntervalSince(lastStateRequest) < Self.stateResponseWindow
            state.updateOutput(output.id) {
                $0.db = db
                if movesFader { $0.value = position }
            }
            if volumeChanged && !isStateResponse {
                outputVolumeChangedTrigger.send(output.id)
            }
            return
        }
        for output in settings.outputs where address == output.oscAddress + OSCAddress.Suffix.mute {
            state.updateOutput(output.id) { $0.muted = on }
            return
        }
    }

    /// Разбирает входящие сообщения секции Dynamics для одного канала.
    private func handleDynamics(_ address: String, base: String, value: Float, target: CompressorTarget) -> Bool {
        guard !base.isEmpty else { return false }
        if address == base + OSCAddress.Dynamics.enable {
            updateCompressor(target) { $0.enabled = value > 0.5 }
            return true
        }
        if let parameter = CompressorParameter.allCases.first(where: { address == base + $0.oscSuffix }) {
            updateCompressor(target) { $0.set(parameter, value: Double(value)) }
            return true
        }
        return false
    }

    /// Разбирает входящие сообщения секции EQ для одного канала.
    private func handleEQ(_ address: String, base: String, value: Float, target: EQTarget) -> Bool {        guard !base.isEmpty else { return false }
        if address == base + OSCAddress.EQ.enable {
            updateEQ(target) { $0.enabled = value > 0.5 }
            return true
        }
        if address == base + OSCAddress.EQ.lowCutEnable {
            updateEQ(target) { $0.lowCutEnabled = value > 0.5 }
            return true
        }
        if let parameter = EQParameter.allCases.first(where: { address == base + $0.oscSuffix }) {
            updateEQ(target) { $0.set(parameter, value: Double(value)) }
            return true
        }
        return false
    }
}
