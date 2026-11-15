import SwiftUI

/// Колонка входа в поповере: имя (переименование двойным кликом)
/// и кнопки +48V / Inst / компрессор, если тип входа их поддерживает.
struct InputControlColumn: View {
    let viewModel: MixerViewModel
    let inputID: UUID
    var onOpenEQ: (UUID) -> Void = { _ in }
    var onOpenCompressor: (UUID) -> Void = { _ in }

    var body: some View {
        let inputType = viewModel.inputType(inputID)
        VStack(spacing: 5) {
            InputNameLabel(viewModel: viewModel, inputID: inputID, width: 44, alignment: .center, font: .caption)
            if inputType?.hasPhantom == true {
                PreampToggleButton(systemImage: "bolt.fill", isOn: viewModel.isPhantomOn(inputID), onColor: .red, isEnabled: viewModel.isConnected) {
                    viewModel.togglePhantom(inputID)
                }
            }
            if inputType?.hasInstrument == true {
                PreampToggleButton(systemImage: "guitars", isOn: viewModel.isInstrumentOn(inputID), onColor: .orange, isEnabled: viewModel.isConnected) {
                    viewModel.toggleInstrument(inputID)
                }
            }
            if inputType?.showsCompressor == true && viewModel.showInputCompressor {
                CompressorButton(isOn: viewModel.isCompressorOn(CompressorTarget(bus: .input, id: inputID)), isEnabled: viewModel.isConnected) {
                    onOpenCompressor(inputID)
                }
            }
            if inputType != nil && viewModel.showInputEQ {
                EQButton(
                    isOn: viewModel.isEQOn(EQTarget(bus: .input, id: inputID)),
                    isEnabled: viewModel.isConnected
                ) {
                    onOpenEQ(inputID)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(PanelOpacity.card))
        )
    }
}

/// Кнопка-капсула предусилителя: +48V (красная, когда включено) или Inst (оранжевая).
struct PreampToggleButton: View {
    let systemImage: String
    let isOn: Bool
    let onColor: Color
    let isEnabled: Bool
    let onToggle: () -> Void

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 12))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isOn ? onColor : Color.primary.opacity(PanelOpacity.control))
            )
            .foregroundStyle(isOn ? .white : .primary)
            .contentShape(Rectangle())
            .onTapGesture {
                onToggle()
            }
            .disabled(!isEnabled)
    }
}

/// Кнопка эквалайзера: загорается, когда EQ включён, по нажатию открывает окно.
struct EQButton: View {
    let isOn: Bool
    let isEnabled: Bool
    let onOpen: () -> Void

    var body: some View {
        Text("EQ")
            .font(.system(size: 10, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isOn ? Color.green : Color.primary.opacity(PanelOpacity.control))
            )
            .foregroundStyle(isOn ? .white : .primary)
            .overlay(
                Capsule()
                    .strokeBorder(Color.green.opacity(isOn ? 0 : PanelOpacity.outline), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                onOpen()
            }
            .disabled(!isEnabled)
    }
}

/// Кнопка компрессора: загорается, когда Dynamics включена, по нажатию открывает окно.
struct CompressorButton: View {
    let isOn: Bool
    let isEnabled: Bool
    let onOpen: () -> Void

    var body: some View {
        Text("Comp")
            .font(.system(size: 10, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isOn ? Color.green : Color.primary.opacity(PanelOpacity.control))
            )
            .foregroundStyle(isOn ? .white : .primary)
            .overlay(
                Capsule()
                    .strokeBorder(Color.green.opacity(isOn ? 0 : PanelOpacity.outline), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                onOpen()
            }
            .disabled(!isEnabled)
    }
}
