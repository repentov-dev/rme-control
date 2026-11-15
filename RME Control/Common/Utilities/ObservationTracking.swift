import Foundation
import Observation

/// Вызывает `onChange` сразу с текущим значением и затем при каждом изменении
/// `@Observable`-свойств, прочитанных в `value`. Замена `$property.sink` из Combine
/// для моделей на Observation (macOS 14+). Наблюдение длится всё время жизни приложения.
@MainActor
func observe<Value>(_ value: @escaping @MainActor @Sendable () -> Value, onChange: @escaping @MainActor @Sendable (Value) -> Void) {
    onChange(trackChanges(of: value, onChange: onChange))
}

@MainActor
private func trackChanges<Value>(of value: @escaping @MainActor @Sendable () -> Value, onChange: @escaping @MainActor @Sendable (Value) -> Void) -> Value {
    withObservationTracking {
        value()
    } onChange: {
        // onChange вызывается до записи нового значения — читаем его на следующем шаге главного потока.
        Task { @MainActor in
            onChange(trackChanges(of: value, onChange: onChange))
        }
    }
}
