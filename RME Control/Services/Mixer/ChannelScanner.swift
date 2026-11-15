import Foundation
import Observation

/// Канал, который TotalMix прислал в ответ на `/sendall`.
/// Номер берётся из адреса: `/input/8` → вход 8, `/output/0` → выход 0.
struct DiscoveredChannel: Identifiable, Equatable, Sendable {
    enum Bus: String, Sendable {
        case input
        case output
    }

    let bus: Bus
    let number: Int
    /// Имя канала из TotalMix; пусто, если пульт имя не прислал.
    var name: String

    var id: String { "\(bus.rawValue)/\(number)" }
    var oscAddress: String { "/\(bus.rawValue)/\(number)" }
}

/// Что удалось считать у TotalMix.
struct ChannelScanResult: Equatable, Sendable {
    var inputs: [DiscoveredChannel] = []
    var outputs: [DiscoveredChannel] = []
    /// TotalMix вообще ответил на запрос (иначе список пуст из-за отсутствия связи).
    var didHearTotalMix = false
    /// Сколько каналов добавилось после сверки с настройками.
    var addedInputs = 0
    var addedOutputs = 0

    var isEmpty: Bool { inputs.isEmpty && outputs.isEmpty }
}

/// Считывает входы и выходы из TotalMix по глобальному OSC.
///
/// По нажатию кнопки в настройках сканер шлёт `/sendall`, а TotalMix в ответ
/// присылает все свои адреса. Из них берутся `/input/<n>/…` и `/output/<n>/…`
/// (имя канала — из `/input/<n>/name`) и собираются два списка.
/// Сканер ничего не меняет: недостающие каналы добавляет `MixerService`,
/// а уже настроенные остаются как есть.
@MainActor
@Observable
final class ChannelScanner {
    /// Идёт сканирование — в это время `handle` записывает входящие сообщения.
    private(set) var isScanning = false

    @ObservationIgnored private let osc: OSCSending
    @ObservationIgnored private var found: [String: DiscoveredChannel] = [:]
    @ObservationIgnored private var isCollecting = false
    @ObservationIgnored private var lastMessageAt = Date.distantPast
    @ObservationIgnored private var lastChangeAt = Date.distantPast

    init(osc: OSCSending) {
        self.osc = osc
    }

    /// Разбирает одно входящее сообщение. Во время сканирования запоминает
    /// каналы и их имена, в остальное время сразу выходит.
    func handle(_ address: String, floatValue: Float?, stringValue: String?) {
        guard isCollecting else { return }
        lastMessageAt = Date()

        let parts = address.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 2, let number = Int(parts[1]), number >= 0 else { return }

        let bus: DiscoveredChannel.Bus
        switch parts[0].lowercased() {
        case "input": bus = .input
        case "output": bus = .output
        default: return
        }

        let key = "\(bus.rawValue)/\(number)"
        var channel = found[key] ?? DiscoveredChannel(bus: bus, number: number, name: "")
        var changed = found[key] == nil

        // Имя приходит строкой: `/input/8/name` = "Mic 1".
        if parts.count == 3, parts[2].lowercased() == "name",
           let name = stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty, name != channel.name {
            channel.name = name
            changed = true
        }

        found[key] = channel
        if changed { lastChangeAt = Date() }
    }

    /// Просит у TotalMix полный список и ждёт, пока ответы перестанут приходить
    /// (не дольше `timeout`, но и не раньше, чем ответы утихнут на `quietPeriod`).
    /// `didHearTotalMix == false` означает, что пульт не ответил вовсе.
    func scan(timeout: Double = 2.5, quietPeriod: Double = 0.35) async -> ChannelScanResult {
        // Если предыдущий опрос ещё идёт (окно закрыли и открыли заново),
        // дожидаемся его и спрашиваем TotalMix ещё раз.
        while isScanning {
            try? await Task.sleep(for: .milliseconds(30))
        }
        isScanning = true
        defer { isScanning = false }

        found.removeAll()
        lastMessageAt = .distantPast
        lastChangeAt = .distantPast
        isCollecting = true
        defer { isCollecting = false }

        let start = Date()
        osc.send(OSCAddress.requestAll, 1.0)

        while Date().timeIntervalSince(start) < timeout {
            try? await Task.sleep(for: .milliseconds(50))
            if Task.isCancelled { break }
            // Ещё ничего не пришло или не нашлось ни одного канала — ждём дальше.
            guard lastMessageAt > start, !found.isEmpty else { continue }
            if Date().timeIntervalSince(lastChangeAt) >= quietPeriod { break }
        }

        var result = ChannelScanResult()
        result.didHearTotalMix = lastMessageAt > start
        result.inputs = found.values.filter { $0.bus == .input }.sorted { $0.number < $1.number }
        result.outputs = found.values.filter { $0.bus == .output }.sorted { $0.number < $1.number }
        return result
    }
}
