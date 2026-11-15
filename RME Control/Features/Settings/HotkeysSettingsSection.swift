import SwiftUI

/// Страница «Hotkeys»: поведение аппаратных клавиш и настраиваемые
/// глобальные комбинации.
struct HotkeysSettingsSection: View {
    let viewModel: SettingsViewModel
    @State private var showsResetConfirmation = false

    var body: some View {
        VStack(spacing: 16) {
            SettingsCard(
                "Hardware keys",
                subtitle: "The physical volume and Mute keys always control the selected output. Choose what Mute does and how the output changes."
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Mute key action")
                        .font(.callout)
                    Picker("", selection: viewModel.binding(\.muteKeyAction)) {
                        Text("Dim").tag(MuteKeyAction.dim)
                        Text("Mute").tag(MuteKeyAction.mute)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Divider()

                SettingsToggleRow(
                    title: "Unmute on volume change",
                    description: "Remove mute when the output volume changes.",
                    isOn: viewModel.binding(\.unmuteOnVolumeChange)
                )

                Divider()

                SettingsToggleRow(
                    title: "Mute other outputs on switch",
                    description: "When switching outputs with a shortcut, mute all outputs except the selected one.",
                    isOn: viewModel.binding(\.muteOtherOutputsOnSwitch)
                )

                Divider()

                SettingsPickerRow(
                    "Volume keys control",
                    description: "Which output the physical volume buttons change.",
                    selection: viewModel.binding(\.volumeKeyOutputID)
                ) {
                    ForEach(viewModel.outputs) { output in
                        Text(verbatim: viewModel.outputName(for: output.id))
                            .tag(output.id as UUID?)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Volume step")
                            .font(.callout)
                        Spacer()
                        Text(verbatim: "\(Int(viewModel.volumeStepDB)) dB")
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: viewModel.binding(\.volumeStepDB), in: 1...10, step: 1)
                    Text("How much the volume changes with one press.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsCard(
                "Keyboard shortcuts",
                subtitle: "These shortcuts work in any app while TotalMix FX is running. All of them are enabled by default; turn off the ones you do not need. A shortcut can only be used by one action, and assigning it again turns it off for the other action."
            ) {
                ForEach(HotkeyAction.allCases) { action in
                    HotkeyRow(viewModel: viewModel, action: action)
                    if action != HotkeyAction.allCases.last {
                        Divider()
                    }
                }

                Divider()

                HStack {
                    Spacer(minLength: 0)
                    Button("Restore to Defaults") {
                        showsResetConfirmation = true
                    }
                    .disabled(viewModel.hotkeysAreDefault)
                }
            }
        }
        .confirmationDialog(
            "Restore hotkeys to defaults?",
            isPresented: $showsResetConfirmation
        ) {
            Button("Restore to Defaults", role: .destructive) {
                viewModel.resetHotkeys()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only the keyboard shortcuts are reset. Channels, presets and other settings stay as they are.")
        }
    }
}

/// Строка действия: описание, комбинация и переключатель включения.
private struct HotkeyRow: View {
    let viewModel: SettingsViewModel
    let action: HotkeyAction

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Label {
                    Text(verbatim: action.title)
                        .font(.callout)
                } icon: {
                    Image(systemName: action.symbol)
                        .foregroundStyle(.secondary)
                }
                Text(verbatim: action.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            HotkeyRecorderButton(viewModel: viewModel, action: action)

            Toggle("", isOn: viewModel.hotkeyEnabledBinding(action))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!viewModel.hotkey(for: action).isAssigned)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
