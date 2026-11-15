import SwiftUI

/// Строка посыла в поповере: выглядит как выход, но управляет `/mix/in/.../fader`.
struct SendRow: View {
    let viewModel: MixerViewModel
    let sendID: UUID

    @State private var isEditing = false

    private var value: Double { viewModel.sendValue(sendID) }
    private var muted: Bool { viewModel.isSendMuted(sendID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Label(viewModel.sendName(for: sendID), systemImage: "arrow.turn.up.right")
                    .font(.callout)
                Spacer()
                Text(muted ? "-∞ dB" : String(format: "%.1f dB", viewModel.sendDB(sendID)))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Button {
                    viewModel.setSendMuted(!muted, for: sendID)
                } label: {
                    Image(systemName: muted ? "speaker.slash.fill" : "speaker.fill")
                        .foregroundStyle(muted ? Color.orange : Color.secondary)
                }
                .buttonStyle(.borderless)
                .disabled(!viewModel.isConnected)

                Slider(value: Binding(
                    get: { value },
                    set: { viewModel.setSendValueLocally($0, for: sendID) }
                ), in: 0...1) { editing in
                    viewModel.setSendDragInProgress(editing, for: sendID)
                    if editing, muted {
                        viewModel.setSendMuted(false, for: sendID)
                    }
                    if !editing {
                        viewModel.setSendVolume(value, for: sendID)
                    }
                    isEditing = editing
                }
                .disabled(!viewModel.isConnected)
                .onChange(of: value) { _, newValue in
                    if isEditing {
                        viewModel.setSendVolume(newValue, for: sendID)
                    }
                }
                .controlSize(.small)
            }
        }
    }
}
