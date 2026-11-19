import AVFoundation
import CoreAudio
import Foundation
import Observation

/// Состояние мастера коррекции Room EQ.
@MainActor
@Observable
final class RoomCorrectionViewModel {
    enum Stage: Equatable {
        case setup
        case position(Int)
        case measuring(Int)
        case computing
        case results
    }

    let mixer: MixerViewModel
    private let fallbackTarget: RoomEQTarget
    private var preferences: RoomCorrectionPreferences
    private var isLoading = true

    /// Выходы RME Control (OSC-выходы TotalMix), по ним выбирается замер.
    var outputs: [OutputConfig] { mixer.outputs }

    var selectedOutput: OutputConfig? {
        guard let selectedOutputID else { return nil }
        return outputs.first { $0.id == selectedOutputID }
    }

    var selectedOutputID: UUID?

    /// Микрофоны из RME Control — их имена и адреса, как в настройках.
    var inputs: [InputConfig] { mixer.inputs }

    var selectedInputID: UUID?

    var selectedInput: InputConfig? {
        guard let selectedInputID else { return nil }
        return inputs.first { $0.id == selectedInputID }
    }

    /// Реальный канал карты для выбранного микрофона (число из OSC-адреса).
    var selectedInputChannel: Int? {
        guard let selectedInput,
              let channel = OSCAddress.channelNumber(in: selectedInput.oscAddress).flatMap(Int.init),
              let device = selectedDevice,
              channel >= 0, channel < device.inputChannels else { return nil }
        return channel
    }

    /// Подпись физического входа для проверки: «Analog 9» и т.п.
    var selectedInputChannelTitle: String? {
        guard let channel = selectedInputChannel else { return nil }
        if inputNames.indices.contains(channel), !inputNames[channel].isEmpty {
            return inputNames[channel]
        }
        return String(localized: "Input \(channel + 1)")
    }

    private var inputNames: [String] = []

    private func refreshChannelNames() {
        guard let device = selectedDevice else {
            inputNames = []
            return
        }
        inputNames = RoomAudioDeviceService.channelNames(id: device.id,
                                                         scope: kAudioDevicePropertyScopeInput)
    }

    /// Есть устройство и выбранный OSC-выход.
    var hasValidOutput: Bool {
        selectedDevice != nil && selectedOutput != nil && outputChannelPair != nil
    }

    /// Есть устройство, выход и валидный вход микрофона.
    var hasValidChannels: Bool {
        hasValidOutput && selectedInputChannel != nil
    }

    /// Канал Room EQ выбранного выхода. Сюда уходят коррекция и пресет.
    var target: RoomEQTarget {
        if let selectedOutputID, let target = mixer.roomEQTarget(for: selectedOutputID) {
            return target
        }
        return fallbackTarget
    }

    var outputChannelPair: (left: Int, right: Int)? {
        guard let output = selectedOutput,
              let left = OSCAddress.channelNumber(in: output.oscAddress).flatMap(Int.init) else { return nil }
        let right = output.resolvedPartnerAddress
            .flatMap { OSCAddress.channelNumber(in: $0) }
            .flatMap(Int.init) ?? (left + 1)
        return (left, right)
    }

    private let service = RoomCorrectionService()
    private var task: Task<Void, Never>?

    var devices: [RoomAudioDevice] = []
    var selectedDeviceID: AudioDeviceID?
    /// Живая частота выбранного устройства: снимок из `devices` устаревает,
    /// как только её меняют в Audio MIDI Setup.
    var deviceSampleRate: Double?
    var calibration: MicCalibration?
    var calibrationPath: String?
    var positionCount = 1 { didSet { persistIfReady() } }
    /// Зерно оптимизации на текущую сессию: пересчёт при смене наклона идёт с ним же,
    /// поэтому варианты остаются сравнимыми.
    private(set) var calibrationSeed: Int?
    var positions: [RoomPositionMeasurement] = []
    var corrections: [RoomCorrectionChannel: RoomCorrection] = [:]
    var selectedChannel: RoomCorrectionChannel = .stereo
    var stage: Stage = .setup
    var progress: RoomCorrectionProgress?
    /// Отказ замера: крупный заголовок и подсказка в окне Measure.
    var failure: MeasurementFailure?
    var status = ""
    var inputChannel = 0 { didSet { persistIfReady() } }
    var leftOutputChannel = 0 { didSet { persistIfReady() } }
    var rightOutputChannel = 1 { didSet { persistIfReady() } }
    var targetTilt = 0.0 { didSet { persistIfReady() } }
    var roomLength = 0.0 { didSet { persistIfReady() } }
    var roomWidth = 0.0 { didSet { persistIfReady() } }
    var roomHeight = 0.0 { didSet { persistIfReady() } }
    var presetName = ""
    var didApply = false
    var micLevelDB: Double?
    var isCheckingMic = false
    var isLevelTestRunning = false
    var levelTestDB: Double?
    var isTestingOutput = false
    var smoothing = 1.0 / 6.0 { didSet { persistIfReady() } }
    var countdown: Int?
    var isRecalculating = false
    private var levelTest: LevelTestSession?
    private var levelTask: Task<Void, Never>?
    private var routingState: CalibrationRoutingState?
    private var routingApplied = false
    private var micCheckTask: Task<Void, Never>?
    private var rateTask: Task<Void, Never>?
    /// На время замера клавиши громкости наводятся на выбранный выход,
    /// после — возвращаются к настройке пользователя.
    private var volumeKeysOverridden = false
    private var testToneTask: Task<Void, Never>?
    private var isClosing = false

    init(mixer: MixerViewModel, target: RoomEQTarget) {
        self.mixer = mixer
        self.fallbackTarget = target
        self.preferences = mixer.roomCorrectionPreferences
        leftOutputChannel = 0
        rightOutputChannel = 1
        reloadDevices()
        applyPreferences()
        isLoading = false
    }

    private func applyPreferences() {
        if let uid = preferences.deviceUID,
           let device = devices.first(where: { $0.uid == uid }) {
            selectedDeviceID = device.id
        }

        // Мастер открыли из Room EQ конкретного выхода — он и должен быть выбран.
        if let match = outputs.first(where: {
            $0.oscAddress == fallbackTarget.address
                || $0.resolvedPartnerAddress == fallbackTarget.address
                || fallbackTarget.partner == $0.oscAddress
        }) {
            selectedOutputID = match.id
        } else if let id = preferences.outputID, outputs.contains(where: { $0.id == id }) {
            selectedOutputID = id
        } else {
            selectedOutputID = outputs.first?.id
        }

        leftOutputChannel = 0
        rightOutputChannel = 1
        if let id = preferences.inputID, inputs.contains(where: { $0.id == id }) {
            selectedInputID = id
        } else {
            selectedInputID = inputs.first { input in
                guard let channel = OSCAddress.channelNumber(in: input.oscAddress).flatMap(Int.init),
                      let device = selectedDevice else { return false }
                return channel >= 0 && channel < device.inputChannels
            }?.id ?? inputs.first?.id
        }
        if let channel = selectedInputChannel {
            inputChannel = channel
        }
        clampChannels()
        refreshChannelNames()

        positionCount = max(1, preferences.positionCount)
        smoothing = preferences.smoothing
        targetTilt = preferences.targetTilt
        calibrationPath = preferences.calibrationPath

        if let path = calibrationPath,
           FileManager.default.fileExists(atPath: path),
           let calibration = try? MicCalibration.load(from: URL(fileURLWithPath: path)) {
            self.calibration = calibration
        }
    }

    private func persistIfReady() {
        guard !isLoading else { return }
        persistPreferences()
    }

    func persistPreferences() {
        preferences.deviceUID = selectedDevice?.uid
        preferences.outputID = selectedOutputID
        preferences.inputID = selectedInputID
        preferences.inputChannel = inputChannel
        preferences.leftOutputChannel = leftOutputChannel
        preferences.rightOutputChannel = rightOutputChannel
        preferences.positionCount = positionCount
        preferences.smoothing = smoothing
        preferences.targetTilt = targetTilt
        preferences.calibrationPath = calibrationPath
        if roomLength > 0, roomWidth > 0, roomHeight > 0 {
            preferences.roomDimensions = RoomDimensions(length: roomLength,
                                                        width: roomWidth,
                                                        height: roomHeight)
        } else {
            preferences.roomDimensions = nil
        }
        mixer.saveRoomCorrectionPreferences(preferences)
    }

    var microphoneAccessDenied = false

    func requestMicrophoneAccess() async {
        // Системный диалог микрофона блокирует главный поток: пока он открыт,
        // перехват клавиш снят, иначе ввод «залипает».
        VolumeKeyMonitor.current?.suspendForModal()
        defer { VolumeKeyMonitor.current?.resumeAfterModal() }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneAccessDenied = false
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            microphoneAccessDenied = !granted
        default:
            microphoneAccessDenied = true
        }
        // TCC-диалог сворачивается не мгновенно: даём модальному циклу закрыться,
        // и только потом возвращаем перехват клавиш (defer сработает после паузы).
        try? await Task.sleep(for: .milliseconds(450))
    }

    var selectedDevice: RoomAudioDevice? {
        devices.first { $0.id == selectedDeviceID }
    }

    var selectedCorrection: RoomCorrection? {
        corrections[selectedChannel]
    }

    var canMeasure: Bool {
        guard hasValidChannels else { return false }
        if case .position = stage { return true }
        return false
    }

    var isBusy: Bool {
        switch stage {
        case .measuring, .computing: return true
        default: return false
        }
    }

    var statusText: String {
        if !status.isEmpty { return status }
        switch stage {
        case .setup: return String(localized: "Choose the device and microphone.")
        case .position: return String(localized: "Ready to measure.")
        case .measuring: return String(localized: "Measuring…")
        case .computing: return String(localized: "Calculating corrections…")
        case .results: return String(localized: "Ready. Choose Left, Right or Stereo.")
        }
    }

    func reloadDevices() {
        devices = RoomAudioDeviceService.all().filter { $0.inputChannels > 0 && $0.outputChannels > 0 }
        if let selectedDeviceID, devices.contains(where: { $0.id == selectedDeviceID }) {
            clampChannels()
                return
        }
        selectedDeviceID = RoomAudioDeviceService.preferred(deviceName: mixer.deviceName)?.id
            ?? devices.first?.id
        clampChannels()
        refreshDeviceSampleRate()
    }

    func selectDevice(_ id: AudioDeviceID?) {
        stopLevelTest()
        // Маршрут замера принадлежит прежнему устройству: сначала возвращаем
        // TotalMix как было при его числе выходов, и только потом переключаемся.
        // Иначе откат считался бы по каналам нового интерфейса и часть mute
        // осталась бы висеть.
        let hadSession = routingApplied
        endCalibrationSession()
        selectedDeviceID = id
        clampChannels()
        refreshChannelNames()
        refreshDeviceSampleRate()
        persistPreferences()
        // Замер на другом интерфейсе недействителен — начинаем с чистого листа.
        task?.cancel()
        task = nil
        positions = []
        corrections = [:]
        countdown = nil
        progress = nil
        isRecalculating = false
        stage = .setup
        status = ""
        failure = nil
        if hadSession {
            Task { [weak self] in
                await self?.startCalibrationSession()
            }
        }
    }

    /// На время замера клавиши громкости управляют выбранным выходом.
    private func overrideVolumeKeys(to id: UUID?) {
        guard id != nil else { return }
        volumeKeysOverridden = true
        mixer.setTemporaryVolumeKeyOutput(id)
    }

    /// Возвращает клавиши громкости туда, где они были до открытия Measure.
    private func restoreVolumeKeys() {
        guard volumeKeysOverridden else { return }
        mixer.setTemporaryVolumeKeyOutput(nil)
        volumeKeysOverridden = false
    }

    /// Читает частоту устройства из CoreAudio прямо сейчас.
    func refreshDeviceSampleRate() {
        guard let id = selectedDeviceID else {
            deviceSampleRate = nil
            return
        }
        let rate = RoomAudioDeviceService.nominalSampleRate(id)
        if deviceSampleRate != rate { deviceSampleRate = rate }
    }

    /// Опрос, пока окно Measure открыто: смена частоты в Audio MIDI Setup
    /// должна снимать предупреждение без переоткрытия окна.
    func startWatchingSampleRate() {
        refreshDeviceSampleRate()
        rateTask?.cancel()
        rateTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                self.refreshDeviceSampleRate()
            }
        }
    }

    func stopWatchingSampleRate() {
        rateTask?.cancel()
        rateTask = nil
    }

    /// Движок замера работает только на 48 кГц: пока интерфейс на другой
    /// частоте, запуск закрыт. Частота читается живьём, поэтому переключение
    /// в Audio MIDI Setup сразу снимает запрет.
    var isSampleRateReady: Bool {
        guard let rate = deviceSampleRate, rate > 0 else { return false }
        return abs(rate - RoomMeasurementAnalyzer.sampleRate) <= 1
    }

    /// Подсказка в Setup нужна только когда интерфейс есть, а частота не та.
    var showsSampleRateWarning: Bool {
        selectedDevice != nil && !isSampleRateReady
    }

    /// Выбирает OSC-выход калибровки. Звук идёт в playback 1/2, а маршрут
    /// на этот выход и mute остальных ставятся на время сессии.
    func selectOutput(_ id: UUID?) {
        let wasTesting = isLevelTestRunning
        stopLevelTest()
        overrideVolumeKeys(to: id)
        selectedOutputID = id
        positions = []
        corrections = [:]
        stage = .setup
        status = ""
        failure = nil
        persistPreferences()
        applyRouting()
        if wasTesting {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(150))
                guard let self, !self.isClosing else { return }
                self.toggleLevelTest()
            }
        }
    }

    /// На время Measure: снять состояние TotalMix, отправить звук в выбранный
    /// выход и замьютить остальные. Запускается из вью при открытии окна.
    func startCalibrationSession() async {
        guard !routingApplied, !isClosing else { return }
        mixer.requestCalibrationState()
        // Ждём не фиксированные 500 мс, а пока TotalMix пришлёт состояние:
        // от него зависит корректный откат mute и посылов.
        for _ in 0..<25 {
            try? await Task.sleep(for: .milliseconds(100))
            if Task.isCancelled { return }
            if !mixer.calibrationRoutingState().mutes.isEmpty { break }
        }
        guard !Task.isCancelled, !isClosing else { return }
        applyRouting()
    }

    private func applyRouting() {
        guard !isClosing,
              let device = selectedDevice,
              let pair = outputChannelPair else { return }
        if routingState == nil {
            routingState = mixer.calibrationRoutingState()
        }
        mixer.applyCalibrationRouting(outputLeft: pair.left,
                                      outputRight: pair.right,
                                      channelCount: device.outputChannels)
        routingApplied = true
    }

    /// Возвращает TotalMix как было: mute выходов и посылы, которые меняли.
    func endCalibrationSession() {
        restoreVolumeKeys()
        guard routingApplied else { return }
        guard let device = selectedDevice else {
            routingState = nil
            routingApplied = false
            return
        }
        mixer.restoreCalibrationRouting(routingState ?? CalibrationRoutingState(mutes: [:], sends: [:]),
                                        channelCount: device.outputChannels)
        routingState = nil
        routingApplied = false
    }

    /// Микрофон всегда моно: вход RME Control, приведённый к каналу карты.
    func selectInput(_ id: UUID?) {
        let wasTesting = isLevelTestRunning
        stopLevelTest()
        selectedInputID = id
        if let channel = selectedInputChannel {
            inputChannel = channel
        }
        persistPreferences()
        if wasTesting {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(150))
                guard let self, !self.isClosing else { return }
                self.toggleLevelTest()
            }
        }
    }

    func setCalibration(url: URL) {
        do {
            calibration = try MicCalibration.load(from: url)
            calibrationPath = url.path
            persistPreferences()
            status = String(format: String(localized: "Calibration: %@"), calibration?.name ?? "")
            failure = nil
        } catch {
            failure = MeasurementFailure(title: error.localizedDescription)
        }
    }

    func clearCalibration() {
        calibration = nil
        calibrationPath = nil
        persistPreferences()
        status = ""
    }

    func startMeasurement() {
        stopLevelTest()
        guard !microphoneAccessDenied else {
            failure = MeasurementFailure(
                title: String(localized: "RME Control has no microphone access."),
                hint: String(localized: "Allow it in System Settings → Privacy & Security → Microphone.")
            )
            return
        }
        guard let device = selectedDevice, hasValidChannels else {
            failure = MeasurementFailure(title: String(localized: "Choose the RME interface, the stereo output and the microphone input."))
            return
        }
        clampChannels()
        guard inputChannel < device.inputChannels else {
            failure = MeasurementFailure(title: String(localized: "The microphone channel is outside the device inputs."))
            return
        }
        guard rightOutputChannel < device.outputChannels else {
            failure = MeasurementFailure(title: String(localized: "The stereo output pair is outside the device outputs."))
            return
        }
        // Частоту читаем прямо сейчас, а не из последнего опроса: иначе окно
        // в секунду между переключением в Audio MIDI Setup и опросом врёт.
        refreshDeviceSampleRate()
        guard isSampleRateReady else {
            failure = .sampleRateMismatch(rate: deviceSampleRate)
            return
        }
        positions = []
        corrections = [:]
        progress = nil
        didApply = false
        failure = nil
        calibrationSeed = Int.random(in: 1...Int(Int32.max))
        stage = .position(1)
        status = ""
    }

    func measurePosition() {
        guard case .position(let index) = stage,
              let device = selectedDevice,
              hasValidChannels,
              task == nil else { return }
        // Частоту могли поменять уже после входа в замер: свип на 48 кГц
        // в интерфейсе на 96 кГц не сойдётся, поэтому честно отказываем.
        refreshDeviceSampleRate()
        guard isSampleRateReady else {
            failure = .sampleRateMismatch(rate: deviceSampleRate)
            return
        }
        stage = .measuring(index)
        progress = nil
        countdown = 5
        task = Task { [weak self] in
            guard let self else { return }
            do {
                for value in stride(from: 5, through: 1, by: -1) {
                    try Task.checkCancellation()
                    self.countdown = value
                    try await Task.sleep(for: .seconds(1))
                }
                self.countdown = nil
                let position = try await self.service.measurePosition(
                    index: index,
                    total: self.positionCount,
                    device: device,
                    inputChannel: self.inputChannel,
                    leftOutputChannel: self.leftOutputChannel,
                    rightOutputChannel: self.rightOutputChannel,
                    calibrationPath: self.calibrationPath
                ) { progress in
                    self.progress = progress
                    self.status = progress.label
                }
                guard !Task.isCancelled else { return }
                self.positions.append(position)
                self.task = nil
                if self.positions.count >= self.positionCount {
                    self.compute()
                } else {
                    self.stage = .position(index + 1)
                    self.status = ""
                }
            } catch {
                self.countdown = nil
                self.task = nil
                self.stage = .position(index)
                if !(error is CancellationError) {
                    self.present(error)
                }
            }
        }
    }

    var roomDimensions: RoomDimensions? {
        guard roomLength > 0, roomWidth > 0, roomHeight > 0 else { return nil }
        return RoomDimensions(length: roomLength, width: roomWidth, height: roomHeight)
    }

    func calibrationResult() -> RoomCalibrationResult? {
        guard !corrections.isEmpty else { return nil }
        return RoomCalibrationResult(
            outputLabel: target.label,
            outputAddress: target.address,
            targetTilt: targetTilt,
            seed: calibrationSeed,
            corrections: Array(corrections.values).sorted { $0.channel.rawValue < $1.channel.rawValue }
        )
    }

    func loadCalibrationResult(from url: URL) throws {
        endCalibrationSession()
        let data = try Data(contentsOf: url)
        let result = try JSONDecoder().decode(RoomCalibrationResult.self, from: data)
        guard !result.corrections.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        var loaded: [RoomCorrectionChannel: RoomCorrection] = [:]
        for correction in result.corrections { loaded[correction.channel] = correction }
        corrections = loaded
        targetTilt = result.targetTilt
        calibrationSeed = result.seed
        selectedChannel = corrections[.stereo] != nil ? .stereo : (corrections.keys.first ?? .stereo)
        stage = .results
        status = String(format: String(localized: "Loaded calibration result: %@"), result.outputLabel)
        failure = nil
    }

    func compute(preservingSelection: Bool = false, keepResults: Bool = false) {
        guard !positions.isEmpty else { return }
        task?.cancel()
        task = nil
        if keepResults {
            isRecalculating = true
            status = String(localized: "Recalculating…")
        } else {
            stage = .computing
            status = String(localized: "Calculating corrections…")
        }
        let previousSelection = selectedChannel
        task = Task { [weak self] in
            guard let self else { return }
            let target = RoomCorrectionTarget(tiltDBPerOctave: self.targetTilt)
            if self.calibrationSeed == nil {
                self.calibrationSeed = Int.random(in: 1...Int(Int32.max))
            }
            let seed = self.calibrationSeed ?? 1
            do {
                let dimensions = self.roomDimensions
                let corrections = try await self.service.corrections(positions: self.positions,
                                                                     target: target,
                                                                     dimensions: dimensions,
                                                                     seed: seed)
                guard !Task.isCancelled else { return }
                self.corrections = corrections
                self.selectedChannel = preservingSelection
                    ? (corrections[previousSelection] != nil ? previousSelection : .stereo)
                    : .stereo
                self.endCalibrationSession()
                self.stage = .results
                self.failure = nil
                self.isRecalculating = false
                self.status = ""
            } catch {
                guard !Task.isCancelled else { return }
                self.present(error)
                self.isRecalculating = false
                if !keepResults { self.stage = .setup }
                self.status = ""
            }
            self.task = nil
        }
    }

    /// Пересчёт после изменения target tilt без повторного замера.
    func recompute() {
        guard !positions.isEmpty else { return }
        compute(preservingSelection: true, keepResults: true)
    }

    func rescan() {
        stopLevelTest()
        restoreVolumeKeys()
        task?.cancel()
        task = nil
        positions = []
        corrections = [:]
        countdown = nil
        isRecalculating = false
        progress = nil
        stage = .setup
        status = ""
        Task { [weak self] in
            await self?.startCalibrationSession()
        }
    }

    func apply() {
        guard let correction = selectedCorrection else { return }
        // Движок сам сказал, что правка ничего не даёт: записывать её нельзя,
        // иначе мы затрём текущую коррекцию нейтральными полосами.
        guard correction.engineAccepted else {
            failure = .engineUnchanged
            return
        }
        let channel: RoomEQChannel
        switch selectedChannel {
        case .left: channel = .left
        case .right: channel = .right
        case .stereo: channel = .both
        }
        let bands = correction.bands.map {
            RoomEQBand(frequency: $0.frequency, gain: $0.gain, q: $0.q, type: $0.type)
        }
        mixer.applyRoomEQBands(target, channel: channel, bands, preamp: correction.preamp)

        // Delay намеренно не пишем: его выставляют вручную в TotalMix.
        // Общая калибровка на оба канала — по самому консервативному запасу.
        let common = min(correction.preamp,
                         corrections[.left]?.preamp ?? correction.preamp,
                         corrections[.right]?.preamp ?? correction.preamp)
        mixer.setRoomEQParameter(target, channel: .both, .volumeCalibration,
                                 min(max(common, -24), 3))

        mixer.setRoomEQEnabled(target, channel: .both, true)
        didApply = true
        status = String(localized: "Correction applied to Room EQ.")
    }

    func savePreset() {
        guard let correction = selectedCorrection,
              !presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let bands = correction.bands.map {
            RoomEQPresetBand(frequency: $0.frequency, gain: $0.gain, q: $0.q, type: $0.type)
        }
        let common = min(correction.preamp,
                         corrections[.left]?.preamp ?? correction.preamp,
                         corrections[.right]?.preamp ?? correction.preamp)
        let calibration = min(max(common, -24), 3)
        mixer.saveRoomEQUserPreset(
            name: presetName,
            bands: bands,
            preamp: correction.preamp,
            mode: selectedChannel,
            delayLeft: nil,
            delayRight: nil,
            calibrationLeft: calibration,
            calibrationRight: calibration
        )
        presetName = ""
        status = String(localized: "Preset saved.")
    }

    func checkMicrophone() {
        guard let device = selectedDevice else { return }
        isCheckingMic = true
        micLevelDB = nil
        micCheckTask?.cancel()
        micCheckTask = Task {
            defer { isCheckingMic = false }
            do {
                let level = try await service.inputLevel(device: device, inputChannel: inputChannel)
                micLevelDB = level
                if level < -70 {
                    failure = MeasurementFailure(title: String(localized: "The microphone level is very low. Check the input and gain."))
                } else {
                    failure = nil
                }
            } catch {
                present(error)
            }
        }
    }

    /// Непрерывный тест: розовый шум в колонки + живой уровень микрофона.
    func toggleLevelTest() {
        guard !isClosing else { return }
        if isLevelTestRunning {
            stopLevelTest()
            return
        }
        guard let device = selectedDevice, hasValidChannels else {
            failure = MeasurementFailure(title: String(localized: "Choose the RME interface, the stereo output and the microphone input."))
            return
        }
        do {
            let session = try LevelTestSession(
                device: device,
                inputChannel: inputChannel,
                outputChannels: [leftOutputChannel, rightOutputChannel]
            )
            try session.start()
            levelTest = session
            isLevelTestRunning = true
            levelTestDB = nil
            failure = nil
            levelTask = Task { [weak self] in
                guard let self else { return }
                while !Task.isCancelled {
                    self.levelTestDB = session.levelDB
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
        } catch {
            stopLevelTest()
            present(error)
        }
    }

    func stopLevelTest() {
        levelTask?.cancel()
        levelTask = nil
        levelTest?.stop()
        levelTest = nil
        isLevelTestRunning = false
        levelTestDB = nil
    }

    /// Короткий тон в левый или правый канал выбранной пары — тем же путём,
    /// каким пойдёт свип, чтобы проверка совпадала с замером.
    func playTest(left: Bool) {
        guard let device = selectedDevice, hasValidOutput else {
            failure = MeasurementFailure(title: String(localized: "Choose the RME interface and the output pair."))
            return
        }
        guard !isTestingOutput else { return }
        isTestingOutput = true
        failure = nil
        testToneTask?.cancel()
        testToneTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isTestingOutput = false }
            do {
                try await self.service.playTone(device: device,
                                                outputChannel: left ? self.leftOutputChannel : self.rightOutputChannel)
            } catch {
                if !(error is CancellationError) {
                    self.present(error)
                }
            }
        }
    }

    func cancel() {
        guard !isClosing else { return }
        isClosing = true
        stopLevelTest()
        micCheckTask?.cancel()
        micCheckTask = nil
        testToneTask?.cancel()
        testToneTask = nil
        task?.cancel()
        task = nil
        endCalibrationSession()
    }

    /// Вход держим в пределах каналов карты. Звук всегда идёт в playback 1/2,
    /// а TotalMix по OSC направляет его в выбранный выход.
    private func clampChannels() {
        guard let device = selectedDevice else { return }
        leftOutputChannel = 0
        rightOutputChannel = 1
        inputChannel = min(max(inputChannel, 0), max(device.inputChannels - 1, 0))
    }

    /// Показывает отказ: технический текст движка уходит в лог, в окне —
    /// понятная пара строк.
    private func present(_ error: Error) {
        failure = MeasurementFailure.describing(error)
    }
}
