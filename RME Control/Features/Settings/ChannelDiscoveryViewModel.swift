import Foundation
import Observation

/// Состояние окна «каналы из TotalMix»: один опрос пульта, полный список того,
/// что он прислал, и отметки пользователя. В программу попадают только
/// отмеченные каналы; то, что уже настроено, помечено и не выбирается.
@MainActor
@Observable
final class ChannelDiscoveryViewModel {
    struct Row: Identifiable, Equatable {
        let channel: DiscoveredChannel
        /// Канал с таким OSC-адресом уже есть в настройках: добавлять нечего.
        let isConfigured: Bool

        var id: String { channel.id }
        var title: String { channel.name.isEmpty ? channel.oscAddress : channel.name }
    }

    private(set) var isScanning = false
    private(set) var didFail = false
    /// Сканирование уже завершалось: пустой список — это ответ пульта, а не ожидание.
    private(set) var hasScanned = false
    private(set) var inputs: [Row] = []
    private(set) var outputs: [Row] = []
    private(set) var selectedInputs: Set<String> = []
    private(set) var selectedOutputs: Set<String> = []

    @ObservationIgnored private let scanner: ChannelScanner
    @ObservationIgnored private let mixer: MixerService
    @ObservationIgnored private let settings: AppSettings

    init(scanner: ChannelScanner, mixer: MixerService, settings: AppSettings) {
        self.scanner = scanner
        self.mixer = mixer
        self.settings = settings
    }

    // MARK: - Данные

    var isEmpty: Bool { inputs.isEmpty && outputs.isEmpty }

    var selectedCount: Int { selectedInputs.count + selectedOutputs.count }

    /// Сколько каналов вообще можно добавить (всё, чего ещё нет в настройках).
    var selectableCount: Int {
        inputs.filter { !$0.isConfigured }.count + outputs.filter { !$0.isConfigured }.count
    }

    func isSelected(_ row: Row) -> Bool {
        row.channel.bus == .input ? selectedInputs.contains(row.id) : selectedOutputs.contains(row.id)
    }

    func setSelected(_ row: Row, _ isSelected: Bool) {
        guard !row.isConfigured else { return }
        switch row.channel.bus {
        case .input:
            if isSelected { selectedInputs.insert(row.id) } else { selectedInputs.remove(row.id) }
        case .output:
            if isSelected { selectedOutputs.insert(row.id) } else { selectedOutputs.remove(row.id) }
        }
    }

    // MARK: - Опрос TotalMix

    func rescan() {
        Task { await scan() }
    }

    /// Спрашивает у TotalMix все входы и выходы и отмечает те, которых ещё нет
    /// в настройках. Ничего не добавляет — это делает `addSelected`.
    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        didFail = false
        defer { isScanning = false }

        let result = await scanner.scan()
        hasScanned = true
        clearSelection()

        guard result.didHearTotalMix else {
            didFail = true
            inputs = []
            outputs = []
            return
        }

        inputs = result.inputs.map { channel in
            Row(channel: channel, isConfigured: settings.hasInput(address: channel.oscAddress))
        }
        outputs = result.outputs.map { channel in
            Row(channel: channel, isConfigured: settings.hasOutput(address: channel.oscAddress))
        }
    }

    // MARK: - Выбор

    func selectAll() {
        selectedInputs = Set(inputs.filter { !$0.isConfigured }.map(\.id))
        selectedOutputs = Set(outputs.filter { !$0.isConfigured }.map(\.id))
    }

    func clearSelection() {
        selectedInputs.removeAll()
        selectedOutputs.removeAll()
    }

    /// Добавляет отмеченные каналы в настройки. Возвращает `true`, если что-то добавилось.
    @discardableResult
    func addSelected() -> Bool {
        let chosenInputs = inputs.filter { selectedInputs.contains($0.id) }.map(\.channel)
        let chosenOutputs = outputs.filter { selectedOutputs.contains($0.id) }.map(\.channel)
        guard !chosenInputs.isEmpty || !chosenOutputs.isEmpty else { return false }
        mixer.addDiscoveredChannels(inputs: chosenInputs, outputs: chosenOutputs)
        return true
    }
}
