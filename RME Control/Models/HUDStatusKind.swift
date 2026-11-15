import Foundation

/// Вид короткого всплывающего уведомления (HUD) под иконкой в строке меню.
enum HUDStatusKind: Equatable {
    case dim
    case mono
    case mute
    case deviceConnected(String)
    case deviceDisconnected(String)
}
