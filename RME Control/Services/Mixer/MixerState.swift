import Foundation
import Combine
import Observation

/// Живое состояние пульта TotalMix, полученное по OSC: громкость и mute выходов,
/// Dim/Mono/Speaker B, +48V/Inst и уровни входов, статус подключения.
/// Каналы хранятся в словарях по `id` из `AppSettings`, поэтому порядок и удаление
/// каналов не могут рассинхронизировать состояние. Ничего не сохраняется на диск:
/// после запуска TotalMix присылает актуальное состояние по `/sendall`.
@MainActor
@Observable
final class MixerState {
    // MARK: - Подключение

    var isConnected = false
    var deviceOffline = false
    var deviceName = ""
    /// TotalMix сообщил, что аудиоинтерфейс подключён (`/status/connection`).
    @ObservationIgnored var devicePresent = false

    // MARK: - Каналы

    private(set) var outputs: [UUID: OutputState] = [:]
    private(set) var inputs: [UUID: InputState] = [:]
    private(set) var sends: [UUID: SendState] = [:]
    /// Пока пользователь тянет фейдер, входящие значения громкости не перезаписывают его.
    @ObservationIgnored var mainDragInProgress = false
    @ObservationIgnored var sendDragInProgress = Set<UUID>()

    // MARK: - Кнопки Control Room

    var speakerBOn = false
    var dimOn = false
    var monoOn = false

    // MARK: - Уровни входов

    /// Уровни входов в dBFS. Отдельное свойство, чтобы обновления 20 раз в секунду
    /// перерисовывали только View, которые читают уровни.
    private(set) var micLevels: [UUID: Double] = [:]
    static let silentLevel: Double = -100

    @ObservationIgnored private var rawLevels: [UUID: Double] = [:]
    @ObservationIgnored private let levelsSubject = CurrentValueSubject<[UUID: Double], Never>([:])
    @ObservationIgnored private var levelsCancellable: AnyCancellable?

    // MARK: - Уровни выходов

    /// Уровни выходов в dBFS (`/level/out/N`), для индикаторов окна компрессора.
    private(set) var outputLevels: [UUID: Double] = [:]

    @ObservationIgnored private var rawOutputLevels: [UUID: Double] = [:]
    @ObservationIgnored private let outputLevelsSubject = CurrentValueSubject<[UUID: Double], Never>([:])
    @ObservationIgnored private var outputLevelsCancellable: AnyCancellable?

    init() {
        levelsCancellable = levelsSubject
            .throttle(for: .milliseconds(33), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] levels in
                MainActor.assumeIsolated { self?.micLevels = levels }
            }
        outputLevelsCancellable = outputLevelsSubject
            .throttle(for: .milliseconds(33), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] levels in
                MainActor.assumeIsolated { self?.outputLevels = levels }
            }
    }

    // MARK: - Выходы

    /// Состояние выхода; для неизвестного id — значения по умолчанию.
    func output(_ id: UUID) -> OutputState {
        outputs[id] ?? OutputState()
    }

    func updateOutput(_ id: UUID, _ mutate: (inout OutputState) -> Void) {
        var state = output(id)
        mutate(&state)
        outputs[id] = state
    }

    // MARK: - Входы

    func input(_ id: UUID) -> InputState {
        inputs[id] ?? InputState()
    }

    func updateInput(_ id: UUID, _ mutate: (inout InputState) -> Void) {
        var state = input(id)
        mutate(&state)
        inputs[id] = state
    }

    // MARK: - Посылы

    func send(_ id: UUID) -> SendState {
        sends[id] ?? SendState()
    }

    func updateSend(_ id: UUID, _ mutate: (inout SendState) -> Void) {
        var state = send(id)
        mutate(&state)
        sends[id] = state
    }

    func level(_ id: UUID) -> Double {
        micLevels[id] ?? Self.silentLevel
    }

    /// Записывает новый уровень входа; в UI он попадёт через throttle.
    func updateLevel(_ level: Double, for id: UUID) {
        rawLevels[id] = level
        levelsSubject.send(rawLevels)
    }

    /// Уровень выхода в dBFS; для неизвестного id — тишина.
    func outputLevel(_ id: UUID) -> Double {
        outputLevels[id] ?? Self.silentLevel
    }

    /// Записывает новый уровень выхода; в UI он попадёт через throttle.
    func updateOutputLevel(_ level: Double, for id: UUID) {
        rawOutputLevels[id] = level
        outputLevelsSubject.send(rawOutputLevels)
    }

    // MARK: - Синхронизация с конфигурацией каналов

    /// Удаляет состояние удалённых выходов и заводит его для новых.
    func syncOutputs(ids: [UUID]) {
        outputs = Dictionary(uniqueKeysWithValues: ids.map { ($0, output($0)) })
        rawOutputLevels = Dictionary(uniqueKeysWithValues: ids.map { ($0, Self.silentLevel) })
        outputLevelsSubject.send(rawOutputLevels)
    }

    /// Удаляет состояние удалённых входов, заводит его для новых и сбрасывает уровни.
    func syncInputs(ids: [UUID]) {
        inputs = Dictionary(uniqueKeysWithValues: ids.map { ($0, input($0)) })
        rawLevels = Dictionary(uniqueKeysWithValues: ids.map { ($0, Self.silentLevel) })
        levelsSubject.send(rawLevels)
    }

    func syncSends(ids: [UUID]) {
        sends = Dictionary(uniqueKeysWithValues: ids.map { ($0, send($0)) })
    }
}
