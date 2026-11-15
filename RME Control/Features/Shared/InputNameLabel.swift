import SwiftUI

/// Подпись входа, которую можно переименовать двойным кликом.
/// Используется в поповере и на панели уровней.
struct InputNameLabel: View {
    let viewModel: MixerViewModel
    let inputID: UUID
    var width: CGFloat = 44
    var alignment: TextAlignment = .center
    var font: Font = .caption

    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var label: String {
        viewModel.inputLabel(for: inputID)
    }

    private var horizontal: HorizontalAlignment {
        switch alignment {
        case .leading: return .leading
        case .trailing: return .trailing
        case .center: return .center
        }
    }

    private func commit() {
        viewModel.renameInput(inputID, to: draft)
        isEditing = false
    }

    var body: some View {
        if isEditing {
            TextField(label, text: $draft)
                .textFieldStyle(.plain)
                .font(font)
                .multilineTextAlignment(alignment)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .frame(width: width)
                .focused($focused)
                .onSubmit { commit() }
                .onExitCommand { isEditing = false }
                .onChange(of: focused) { _, isFocused in
                    if !isFocused, isEditing { commit() }
                }
        } else {
            Text(label)
                .font(font)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(alignment)
                .frame(width: width, alignment: Alignment(horizontal: horizontal, vertical: .center))
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    draft = viewModel.inputName(for: inputID)
                    isEditing = true
                    Task { @MainActor in
                        MetersPanel.activateForTextInput()
                        focused = true
                    }
                }
        }
    }
}
