import SwiftUI

/// Окно «каналы из TotalMix»: показывает всё, что прислал пульт, и даёт
/// отметить входы и выходы, которые нужно добавить в RME Control.
/// Используется и как отдельное окно, и как шаг мастера настройки.
struct ChannelDiscoveryView: View {
    let viewModel: ChannelDiscoveryViewModel

    /// Вызывается после добавления отмеченных каналов.
    var onDone: () -> Void = {}
    /// Вызывается по кнопке Cancel (в мастере — «Skip»).
    var onCancel: () -> Void = {}
    var doneTitle: LocalizedStringKey = "Add selected"
    var cancelTitle: LocalizedStringKey = "Cancel"
    /// Разрешает продолжить, ничего не выбрав (шаг мастера можно пропустить).
    var allowsEmptyDone = false
    var showsHeader = true
    var showsFooter = true

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                header
                Divider()
            }
            content
            if showsFooter {
                Divider()
                footer
            }
        }
        .frame(minWidth: 460, minHeight: 300)
        .task { await viewModel.scan() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Channels from TotalMix")
                    .font(.headline)
                Text("Pick the channels to add to RME Control. Channels that are already here are marked and cannot be selected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if viewModel.isScanning {
                ProgressView()
                    .controlSize(.small)
            }
            Button("Scan again") { viewModel.rescan() }
                .disabled(viewModel.isScanning)
        }
        .padding(14)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.didFail {
            VStack(spacing: 10) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 26))
                    .foregroundStyle(.orange)
                Text("TotalMix did not answer. Check that TotalMix FX is running and its global OSC is enabled.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                Button("Scan again") { viewModel.rescan() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        } else if viewModel.isEmpty && !viewModel.hasScanned {
            VStack(spacing: 10) {
                ProgressView()
                Text("Talking to TotalMix…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "mic.slash")
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)
                Text("TotalMix reported no inputs or outputs.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                if !viewModel.inputs.isEmpty {
                    Section("Inputs") {
                        ForEach(viewModel.inputs) { row in
                            ChannelDiscoveryRow(viewModel: viewModel, row: row)
                        }
                    }
                }
                if !viewModel.outputs.isEmpty {
                    Section("Outputs") {
                        ForEach(viewModel.outputs) { row in
                            ChannelDiscoveryRow(viewModel: viewModel, row: row)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(String(format: String(localized: "Selected: %lld"), viewModel.selectedCount))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Button("Select all") { viewModel.selectAll() }
                .disabled(viewModel.selectableCount == 0 || viewModel.selectedCount == viewModel.selectableCount)
            Button("Clear") { viewModel.clearSelection() }
                .disabled(viewModel.selectedCount == 0)

            Spacer(minLength: 8)

            Button(cancelTitle) { onCancel() }
                .keyboardShortcut(.cancelAction)
            Button(doneTitle) {
                viewModel.addSelected()
                onDone()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!allowsEmptyDone && viewModel.selectedCount == 0)
        }
        .padding(12)
    }
}

/// Одна строка списка: отметка, имя канала из TotalMix и его OSC-адрес.
/// Канал, который уже настроен, отмечен серым и выбрать его нельзя.
private struct ChannelDiscoveryRow: View {
    let viewModel: ChannelDiscoveryViewModel
    let row: ChannelDiscoveryViewModel.Row

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { viewModel.isSelected(row) },
                set: { viewModel.setSelected(row, $0) }))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(row.isConfigured)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .font(.callout)
                    .lineLimit(1)
                Text(verbatim: row.channel.oscAddress)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if row.isConfigured {
                Text("Already added")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
