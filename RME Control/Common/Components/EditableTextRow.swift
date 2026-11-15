import SwiftUI

/// Строка «подпись — текстовое поле» для адресов и портов в настройках.
struct EditableTextRow: View {
    let label: LocalizedStringKey
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 200)
        }
    }
}
