import Foundation

/// Размеры комнаты в метрах — для Schroeder split в roomeq.
struct RoomDimensions: Codable, Equatable, Sendable {
    var length: Double
    var width: Double
    var height: Double
}

/// Запомненные настройки мастера замера: устройство, выход, микрофон,
/// калибровка и параметры отображения.
struct RoomCorrectionPreferences: Codable, Equatable, Sendable {
    var deviceUID: String?
    var outputID: UUID?
    var inputID: UUID?
    var inputChannel: Int?
    var leftOutputChannel: Int?
    var rightOutputChannel: Int?
    var positionCount: Int = 3
    var smoothing: Double = 1.0 / 6.0
    var targetTilt: Double = 0
    var calibrationPath: String?
    var roomDimensions: RoomDimensions?
}
