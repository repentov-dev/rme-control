import Foundation

/// Что делает аппаратная клавиша Mute на клавиатуре: включает Dim или Mute выбранного выхода.
enum MuteKeyAction: String, Codable, CaseIterable {
    case dim
    case mute
}
