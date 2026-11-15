import Foundation
import Observation

/// Одно OSC-сообщение, прошедшее через приложение: входящее от TotalMix
/// или любого другого отправителя либо исходящее из RME Control.
struct OSCActivity: Identifiable, Sendable {
    enum Direction: Sendable {
        case incoming
        case outgoing
    }

    let id = UUID()
    let date: Date
    let direction: Direction
    let address: String
    let value: String

    init(direction: Direction, address: String, floatValue: Float) {
        self.init(direction: direction, address: address, value: Self.format(floatValue))
    }

    init(direction: Direction, address: String, stringValue: String) {
        self.init(direction: direction, address: address, value: stringValue)
    }

    init(direction: Direction, address: String) {
        self.init(direction: direction, address: address, value: "—")
    }

    private init(direction: Direction, address: String, value: String) {
        self.date = Date()
        self.direction = direction
        self.address = address
        self.value = value
    }

    private static func format(_ value: Float) -> String {
        value.rounded() == value ? String(format: "%.0f", value) : String(format: "%.3f", value)
    }
}

/// Журнал OSC-обмена для отладочного окна. Пишет все сообщения, которые
/// разбирает `OSCClient`, включая адреса, не используемые остальным приложением.
/// Запись выключается флагом `isEnabled`; хранится только последние `limit` сообщений.
@MainActor
@Observable
final class OSCMonitor {
    private(set) var activities: [OSCActivity] = []
    var isEnabled = false

    private let limit = 500

    func record(_ activity: OSCActivity) {
        guard isEnabled else { return }
        activities.append(activity)
        if activities.count > limit {
            activities.removeFirst(activities.count - limit)
        }
    }

    func clear() {
        activities.removeAll()
    }
}
