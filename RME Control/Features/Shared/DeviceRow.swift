import SwiftUI

/// Строка выхода: название, громкость в dB, кнопка mute и фейдер.
/// Используется в поповере и в HUD громкости. Во время перетаскивания громкость
/// отправляется в TotalMix непрерывно, при отпускании — финальное значение.
struct DeviceRow: View {
    let viewModel: MixerViewModel
    let outputID: UUID
    var showMute: Bool = true
    var onOpenEQ: (() -> Void)? = nil
    var onOpenCompressor: (() -> Void)? = nil

    @State private var isEditing = false

    private var value: Double { viewModel.outputValue(outputID) }
    private var muted: Bool { viewModel.isOutputMuted(outputID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Label(viewModel.outputName(for: outputID), systemImage: viewModel.outputSymbolName(for: outputID))
                    .font(.callout)
                Spacer()
                Text(value <= 0.005 ? "-∞ dB" : String(format: "%.1f dB", FaderMath.db(for: value)))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                if showMute {
                    Button {
                        viewModel.setOutputMuted(!muted, for: outputID)
                    } label: {
                        Image(systemName: muted ? "speaker.slash.fill" : "speaker.fill")
                            .foregroundStyle(muted ? Color.orange : Color.secondary)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!viewModel.isConnected)
                }

                if let onOpenCompressor {
                    Button(action: onOpenCompressor) {
                        Text("Comp")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(
                                viewModel.isCompressorOn(CompressorTarget(bus: .output, id: outputID)) ? Color.green : Color.secondary
                            )
                    }
                    .buttonStyle(.borderless)
                    .disabled(!viewModel.isConnected)
                }

                if let onOpenEQ {
                    Button(action: onOpenEQ) {
                        Text("EQ")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(
                                viewModel.isEQOn(EQTarget(bus: .output, id: outputID)) ? Color.green : Color.secondary
                            )
                    }
                    .buttonStyle(.borderless)
                    .disabled(!viewModel.isConnected)
                }

                Slider(value: Binding(
                    get: { value },
                    set: { viewModel.setOutputValueLocally($0, for: outputID) }
                ), in: 0...1) { editing in
                    viewModel.setDragInProgress(editing)
                    if editing, muted, viewModel.unmuteOnVolumeChange {
                        viewModel.setOutputMuted(false, for: outputID)
                    }
                    if !editing {
                        viewModel.sendVolume(value, for: outputID)
                    }
                    isEditing = editing
                }
                .disabled(!viewModel.isConnected)
                .onChange(of: value) { _, newValue in
                    if isEditing {
                        viewModel.sendVolume(newValue, for: outputID)
                    }
                }
                .controlSize(.small)
            }
        }
    }
}
