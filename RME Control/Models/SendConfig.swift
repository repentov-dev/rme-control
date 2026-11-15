import Foundation

/// Пользовательский посыл из входа на выход. Хранит только маршрут и имя;
/// уровень и mute живут в `MixerState`, как у обычных каналов.
struct SendConfig: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String = ""
    var inputID: UUID
    var outputID: UUID
    var showInMain: Bool = true

    init(id: UUID = UUID(), name: String = "", inputID: UUID, outputID: UUID, showInMain: Bool = true) {
        self.id = id
        self.name = name
        self.inputID = inputID
        self.outputID = outputID
        self.showInMain = showInMain
    }
}
