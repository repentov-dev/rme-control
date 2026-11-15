import SwiftUI

/// Кнопка-переключатель Control Room (Speaker B, Dim, Mono) с индикатором состояния.
/// Сама ничего не отправляет — действие передаётся через `onToggle`.
struct MomentaryOscButton: View {
    let label: LocalizedStringKey
    let isOn: Bool
    let isEnabled: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.callout)
                .lineLimit(1)
            Spacer(minLength: 4)
            Circle()
                .fill(isOn ? Color.green : Color.primary.opacity(0.3))
                .frame(width: 10, height: 10)
        }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isOn ? Color.accentColor : Color.primary.opacity(0.2))
            )
            .foregroundStyle(isOn ? .white : .primary)
            .contentShape(Rectangle())
            .onTapGesture {
                onToggle()
            }
            .disabled(!isEnabled)
    }
}
