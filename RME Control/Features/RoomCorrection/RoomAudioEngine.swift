import AVFoundation
import CoreAudio
import Foundation

/// CoreAudio-устройство, пригодное для замера.
struct RoomAudioDevice: Identifiable, Hashable, Sendable {
    let id: AudioDeviceID
    let name: String
    let uid: String
    let inputChannels: Int
    let outputChannels: Int
    let sampleRate: Double
}

enum RoomAudioDeviceService {
    static func all() -> [RoomAudioDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids
        ) == noErr else { return [] }

        return ids.compactMap { id in
            guard let name = stringProperty(id, kAudioDevicePropertyDeviceNameCFString),
                  let uid = stringProperty(id, kAudioDevicePropertyDeviceUID) else { return nil }
            return RoomAudioDevice(
                id: id,
                name: name,
                uid: uid,
                inputChannels: channelCount(id, scope: kAudioDevicePropertyScopeInput),
                outputChannels: channelCount(id, scope: kAudioDevicePropertyScopeOutput),
                sampleRate: nominalSampleRate(id)
            )
        }
    }

    /// RME-интерфейс: сначала точное совпадение с именем из TotalMix, затем любой RME.
    static func preferred(deviceName: String) -> RoomAudioDevice? {
        let devices = all().filter { $0.inputChannels > 0 && $0.outputChannels > 0 }
        let rme = devices.filter(isRME)
        let needle = normalized(deviceName)
        if !needle.isEmpty {
            if let match = rme.first(where: { normalized($0.name).contains(needle) || needle.contains(normalized($0.name)) }) {
                return match
            }
        }
        if let defaultID = defaultDevice(kAudioHardwarePropertyDefaultOutputDevice),
           let match = rme.first(where: { $0.id == defaultID }) {
            return match
        }
        return rme.first
    }

    static func nominalSampleRate(_ id: AudioDeviceID) -> Double {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var rate = Float64(0)
        var size = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &rate) == noErr else { return 0 }
        return rate
    }

    /// Имена физических каналов карты («Analog 1», «Phones 9», «ADAT 3»).
    static func channelNames(id: AudioDeviceID, scope: AudioObjectPropertyScope) -> [String] {
        var names: [String] = []
        for channel in 0..<64 {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyChannelNameCFString,
                mScope: scope,
                mElement: AudioObjectPropertyElement(channel + 1)
            )
            var value: CFString?
            var size = UInt32(MemoryLayout<CFString?>.size)
            let status = withUnsafeMutablePointer(to: &value) { pointer in
                AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
            }
            guard status == noErr, let value else { break }
            names.append(value as String)
        }
        return names
    }

    static func defaultOutput() -> RoomAudioDevice? {
        guard let id = defaultDevice(kAudioHardwarePropertyDefaultOutputDevice) else { return nil }
        return all().first { $0.id == id }
    }

    private static func isRME(_ device: RoomAudioDevice) -> Bool {
        let name = device.name.lowercased()
        return ["rme", "fireface", "babyface", "ucx", "ufx", "madiaface", "digiface", "adi-2"]
            .contains { name.contains($0) }
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
    }

    private static func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id
        ) == noErr else { return nil }
        return id
    }

    private static func stringProperty(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value as String
    }

    private static func channelCount(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        let list = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, list) == noErr else { return 0 }
        return UnsafeMutableAudioBufferListPointer(list).reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}

/// Запись и воспроизведение свипа через выбранное CoreAudio-устройство.
@MainActor
final class RoomAudioEngine {
    enum EngineError: LocalizedError {
        case noDevice
        case noInput
        case noOutput
        case engine(String)
        case silent
        case tooShort
        case channelUnavailable

        var errorDescription: String? {
            switch self {
            case .noDevice: return String(localized: "No RME audio device found.")
            case .noInput: return String(localized: "The selected microphone input is unavailable.")
            case .noOutput: return String(localized: "The selected speaker output is unavailable.")
            case .engine: return String(localized: "The audio engine stopped.")
            case .silent: return String(localized: "No signal from the microphone. Check the input and level.")
            case .tooShort: return String(localized: "The recording is too short. Try again.")
            case .channelUnavailable: return String(localized: "The interface does not expose this channel.")
            }
        }
    }

    /// Проверка микрофона: RMS-уровень выбранного входа за пару секунд.
    func inputLevel(device: RoomAudioDevice, inputChannel: Int, seconds: Double = 1.5) async throws -> Double {
        guard device.inputChannels > 0 else { throw EngineError.noInput }
        let engine = AVAudioEngine()
        try setDevice(device.id, on: engine.inputNode)
        try setDevice(device.id, on: engine.outputNode)
        let format = engine.inputNode.inputFormat(forBus: 0)
        guard format.channelCount > 0 else { throw EngineError.noInput }
        guard inputChannel >= 0, inputChannel < Int(format.channelCount) else {
            throw EngineError.channelUnavailable
        }
        let recorder = SampleRecorder()
        let sink = RoomAudioCapture.sink(recorder: recorder, channel: inputChannel)
        engine.attach(sink)
        engine.connect(engine.inputNode, to: sink, format: format)
        defer {
            engine.stop()
            engine.detach(sink)
        }
        engine.prepare()
        do { try engine.start() } catch { throw EngineError.engine(error.localizedDescription) }
        try await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
        let samples = recorder.take()
        guard !samples.isEmpty else { throw EngineError.silent }
        let rms = sqrt(samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(samples.count))
        return 20 * log10(max(rms, 1e-9))
    }

    /// Короткий тон для проверки, что выбранный канал идёт в нужный динамик.
    func playTest(device: RoomAudioDevice, outputChannel: Int, seconds: Double = 2.0) async throws {
        guard device.outputChannels > 0 else { throw EngineError.noOutput }
        let engine = AVAudioEngine()
        try setDevice(device.id, on: engine.outputNode)
        let outputFormat = engine.outputNode.inputFormat(forBus: 0)
        let rate = outputFormat.sampleRate > 0 ? outputFormat.sampleRate : 48_000
        let deviceChannels = Int(outputFormat.channelCount)
        let format = RoomAudioEngine.discreteFormat(rate: rate, channels: deviceChannels)
            ?? outputFormat
        let channels = Int(format.channelCount)
        guard outputChannel >= 0, outputChannel < channels else {
            throw EngineError.channelUnavailable
        }
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.outputNode, format: format)
        engine.prepare()
        applyIdentityChannelMap(to: engine)
        do { try engine.start() } catch { throw EngineError.engine(error.localizedDescription) }
        defer {
            player.stop()
            engine.stop()
            engine.detach(player)
        }

        let frames = AVAudioFrameCount(rate * seconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw EngineError.noOutput
        }
        buffer.frameLength = frames
        if let data = buffer.floatChannelData {
            for index in 0..<channels {
                data[index].initialize(repeating: 0, count: Int(frames))
            }
            let fade = max(Int(rate * 0.02), 1)
            for frame in 0..<Int(frames) {
                let t = Double(frame) / rate
                var value = sin(2 * Double.pi * 1_000 * t) * 0.08
                if frame < fade { value *= Double(frame) / Double(fade) }
                if frame > Int(frames) - fade {
                    value *= Double(Int(frames) - frame) / Double(fade)
                }
                data[outputChannel][frame] = Float(value)
            }
        }
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        player.play()
        try await Task.sleep(for: .milliseconds(Int((seconds + 0.15) * 1000)))
    }

    /// Дискретный layout: без него движок сводит многоканальный буфер в стерео.
    static func discreteFormat(rate: Double, channels: Int) -> AVAudioFormat? {
        guard channels > 0, channels <= 64,
              let layout = AVAudioChannelLayout(
                  layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | UInt32(channels)
              ) else { return nil }
        return AVAudioFormat(standardFormatWithSampleRate: rate, channelLayout: layout)
    }

    private func setDevice(_ id: AudioDeviceID, on node: AVAudioIONode) throws {
        guard let unit = node.audioUnit else { throw EngineError.noDevice }
        var deviceID = id
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw EngineError.engine(String(localized: "Cannot select the audio device."))
        }
    }
}

/// Живой тест уровня: розовый шум в выход и RMS микрофона в реальном времени.
@MainActor
final class LevelTestSession {
    private let engine = AVAudioEngine()
    private let state = LevelState()
    private let inputChannel: Int
    private let outputChannels: [Int]
    private var player: AVAudioPlayerNode?
    private var sink: AVAudioSinkNode?
    private var buffer: AVAudioPCMBuffer?

    init(device: RoomAudioDevice, inputChannel: Int, outputChannels: [Int]) throws {
        self.inputChannel = inputChannel
        self.outputChannels = Array(Set(outputChannels)).sorted()
        guard device.inputChannels > 0 else { throw RoomAudioEngine.EngineError.noInput }
        guard device.outputChannels > 0 else { throw RoomAudioEngine.EngineError.noOutput }
        try Self.selectDevice(device.id, on: engine.inputNode)
        try Self.selectDevice(device.id, on: engine.outputNode)

        let inputFormat = engine.inputNode.inputFormat(forBus: 0)
        guard inputFormat.channelCount > 0 else { throw RoomAudioEngine.EngineError.noInput }
        guard inputChannel >= 0, inputChannel < Int(inputFormat.channelCount) else {
            throw RoomAudioEngine.EngineError.channelUnavailable
        }
        let outputFormat = engine.outputNode.inputFormat(forBus: 0)
        guard outputFormat.channelCount > 0 else { throw RoomAudioEngine.EngineError.noOutput }
        let playerFormat = RoomAudioEngine.discreteFormat(
            rate: outputFormat.sampleRate > 0 ? outputFormat.sampleRate : 48_000,
            channels: Int(outputFormat.channelCount)
        ) ?? outputFormat
        for channel in self.outputChannels where channel < 0 || channel >= Int(playerFormat.channelCount) {
            throw RoomAudioEngine.EngineError.channelUnavailable
        }

        let sink = RoomAudioCapture.levelSink(state: state, channel: inputChannel)
        engine.attach(sink)
        engine.connect(engine.inputNode, to: sink, format: inputFormat)

        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.outputNode, format: playerFormat)
        self.player = player
        self.sink = sink

        let frames = AVAudioFrameCount(playerFormat.sampleRate * 2)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: playerFormat, frameCapacity: frames) else {
            throw RoomAudioEngine.EngineError.noOutput
        }
        buffer.frameLength = frames
        if let data = buffer.floatChannelData {
            for channel in 0..<Int(playerFormat.channelCount) {
                data[channel].initialize(repeating: 0, count: Int(frames))
            }
            let noise = Self.pinkNoise(count: Int(frames))
            for channel in self.outputChannels {
                for index in 0..<Int(frames) {
                    data[channel][index] = noise[index]
                }
            }
        }
        self.buffer = buffer
    }

    func start() throws {
        guard let player, let buffer else { throw RoomAudioEngine.EngineError.noOutput }
        engine.prepare()
        applyIdentityChannelMap(to: engine)
        do { try engine.start() } catch {
            throw RoomAudioEngine.EngineError.engine(error.localizedDescription)
        }
        player.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        player.play()
    }

    func stop() {
        player?.stop()
        engine.stop()
        if let player { engine.detach(player) }
        if let sink { engine.detach(sink) }
        player = nil
        sink = nil
        buffer = nil
    }

    var levelDB: Double { state.value }

    fileprivate static func selectDevice(_ id: AudioDeviceID, on node: AVAudioIONode) throws {
        guard let unit = node.audioUnit else { throw RoomAudioEngine.EngineError.noDevice }
        var deviceID = id
        let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                          kAudioUnitScope_Global, 0, &deviceID,
                                          UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else {
            throw RoomAudioEngine.EngineError.engine(String(localized: "Cannot select the audio device."))
        }
    }

    private static func pinkNoise(count: Int) -> [Float] {
        var b0 = 0.0, b1 = 0.0, b2 = 0.0, b3 = 0.0, b4 = 0.0, b5 = 0.0, b6 = 0.0
        var result = [Float](repeating: 0, count: count)
        for index in 0..<count {
            let white = Double.random(in: -1...1)
            b0 = 0.99886 * b0 + white * 0.0555179
            b1 = 0.99332 * b1 + white * 0.0750759
            b2 = 0.96900 * b2 + white * 0.1538520
            b3 = 0.86650 * b3 + white * 0.3104856
            b4 = 0.55000 * b4 + white * 0.5329522
            b5 = -0.7616 * b5 - white * 0.0168980
            let pink = b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362
            b6 = white * 0.115926
            result[index] = Float(pink * 0.03)
        }
        return result
    }
}

/// Ставит карту каналов 1:1: многоканальный формат без layout иначе может
/// сводиться движком в первые два канала.
func applyIdentityChannelMap(to engine: AVAudioEngine) {
    guard let unit = engine.outputNode.audioUnit else { return }
    let channels = Int(engine.outputNode.inputFormat(forBus: 0).channelCount)
    guard channels > 2 else { return }
    var map = (0..<channels).map { Int32($0) }
    let size = UInt32(map.count * MemoryLayout<Int32>.size)
    AudioUnitSetProperty(unit,
                         kAudioOutputUnitProperty_ChannelMap,
                         kAudioUnitScope_Output,
                         0,
                         &map,
                         size)
}

/// Уровень, который пишет аудиопоток и читает UI.
private final class LevelState: @unchecked Sendable {
    private let lock = NSLock()
    private var db: Double = -100

    func set(_ value: Double) {
        lock.lock()
        db = value
        lock.unlock()
    }

    var value: Double {
        lock.lock()
        defer { lock.unlock() }
        return db
    }
}

/// Sink для захвата RME: блок выполняется на аудиопотоке, поэтому он
/// nonisolated и не трогает main actor.
private enum RoomAudioCapture {
    nonisolated static func sink(recorder: SampleRecorder, channel: Int) -> AVAudioSinkNode {
        AVAudioSinkNode { _, _, bufferList in
            recorder.append(bufferList: bufferList, channel: channel)
            return noErr
        }
    }

    nonisolated static func levelSink(state: LevelState, channel: Int) -> AVAudioSinkNode {
        AVAudioSinkNode { _, _, bufferList in
            let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
            guard channel >= 0, channel < list.count,
                  let data = list[channel].mData else { return noErr }
            let count = Int(list[channel].mDataByteSize) / MemoryLayout<Float>.size
            guard count > 0 else { return noErr }
            let pointer = data.bindMemory(to: Float.self, capacity: count)
            var sum = 0.0
            for index in 0..<count {
                let value = Double(pointer[index])
                sum += value * value
            }
            let rms = sqrt(sum / Double(count))
            state.set(20 * log10(max(rms, 1e-9)))
            return noErr
        }
    }
}

/// Накопитель сэмплов для проверки уровня микрофона.
private final class SampleRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []

    func append(bufferList: UnsafePointer<AudioBufferList>, channel: Int) {
        let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
        guard channel >= 0, channel < list.count,
              let data = list[channel].mData else { return }
        let count = Int(list[channel].mDataByteSize) / MemoryLayout<Float>.size
        guard count > 0 else { return }
        let pointer = data.bindMemory(to: Float.self, capacity: count)
        lock.lock()
        samples.reserveCapacity(samples.count + count)
        samples.append(contentsOf: UnsafeBufferPointer(start: pointer, count: count))
        lock.unlock()
    }

    func take() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let result = samples
        samples.removeAll(keepingCapacity: false)
        return result
    }
}
