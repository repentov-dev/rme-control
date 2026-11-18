import AppKit
import SwiftUI

// MARK: - General

/// Язык интерфейса, запуск при входе, пресеты настроек и разрешение Accessibility.
struct GeneralSettingsSection: View {
    let viewModel: SettingsViewModel
    @State private var launchAtLogin = false
    @State private var accessibilityGranted = false
    @State private var presetName = ""

    var body: some View {
        VStack(spacing: 16) {
            SettingsCard("Presets", subtitle: "Save the current channels and settings under a name, then restore them later.") {
                HStack(spacing: 8) {
                    TextField("Preset name", text: $presetName)
                        .textFieldStyle(.roundedBorder)
                    Button("Save") {
                        viewModel.savePreset(named: presetName)
                        presetName = ""
                    }
                    .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if viewModel.presets.isEmpty {
                    Text("No presets saved.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.presets) { preset in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: preset.name)
                                    .font(.callout)
                                HStack(spacing: 10) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "hifispeaker.2")
                                        Text(verbatim: "\(preset.snapshot.outputs.count)")
                                    }
                                    HStack(spacing: 4) {
                                        Image(systemName: "mic")
                                        Text(verbatim: "\(preset.snapshot.inputs.count)")
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Button("Apply") {
                                viewModel.applyPreset(preset)
                            }
                            Button(role: .destructive) {
                                viewModel.removePreset(preset)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Delete preset")
                        }
                        if preset.id != viewModel.presets.last?.id {
                            Divider()
                        }
                    }
                }
            }

            SettingsCard("Interface", subtitle: "Choose the language of buttons, menus and settings.") {
                SettingsPickerRow("Language", selection: viewModel.languageBinding) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(verbatim: language.displayName).tag(language)
                    }
                }

                if viewModel.languageNeedsRestart {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Restart RME Control to apply the language.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Restart now") {
                            viewModel.relaunch()
                        }
                    }
                }
            }

            SettingsCard("Startup", subtitle: "RME Control lives in the menu bar, so it can start quietly with your Mac.") {
                SettingsToggleRow(
                    title: "Launch at login",
                    description: "Start RME Control automatically when you log in.",
                    isOn: Binding(
                        get: { launchAtLogin },
                        set: { newValue in
                            viewModel.setLaunchAtLogin(newValue)
                            launchAtLogin = viewModel.launchAtLoginEnabled
                        }
                    )
                )
            }

            SettingsCard("Settings file", subtitle: "Channels, shortcuts and preferences are stored in this file. Show it in Finder to back it up or inspect it.") {
                HStack(spacing: 10) {
                    Button {
                        viewModel.showSettingsFile()
                    } label: {
                        Label("Show Settings File", systemImage: "doc.text.magnifyingglass")
                    }
                    Spacer(minLength: 0)
                }
                Text(verbatim: viewModel.settingsFilePath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            SettingsCard("Accessibility", subtitle: "RME Control needs this macOS permission to intercept the hardware keys.") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(accessibilityGranted ? .green : .orange)
                        Text(accessibilityGranted ? "Permission granted" : "Permission not granted")
                            .font(.callout)
                        Spacer(minLength: 0)
                    }
                    Button("Open System Settings") {
                        viewModel.openAccessibilitySettings()
                    }
                }

                Text("After changing the permission, restart RME Control.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            launchAtLogin = viewModel.launchAtLoginEnabled
            refreshAccessibility()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccessibility()
        }
    }

    private func refreshAccessibility() {
        accessibilityGranted = viewModel.accessibilityGranted
    }
}

// MARK: - Menu bar panel

/// Что показывать в поповере из строки меню.
struct MenuBarSettingsSection: View {
    let viewModel: SettingsViewModel

    var body: some View {
        VStack(spacing: 16) {
            SettingsCard("Controls", subtitle: "Choose which buttons appear in the menu bar panel.") {
                SettingsToggleRow(
                    title: "Mute buttons",
                    description: "A mute button for every output.",
                    isOn: viewModel.binding(\.showMuteButtons)
                )
                SettingsToggleRow(
                    title: "Speaker B",
                    description: "Switch the control room to the alternate speaker pair.",
                    isOn: viewModel.binding(\.showSpeakerB)
                )
                SettingsToggleRow(
                    title: "Dim",
                    description: "Temporarily lower the control room volume.",
                    isOn: viewModel.binding(\.showDim)
                )
                SettingsToggleRow(
                    title: "Mono",
                    description: "Sum the control room to mono. Also available with Cmd+Shift+M.",
                    isOn: viewModel.binding(\.showMono)
                )
            }

            SettingsCard("Compressor & EQ", subtitle: "Show the Comp and EQ buttons on channels in the menu bar panel.") {
                SettingsToggleRow(
                    title: "Inputs: Compressor",
                    description: "Show the Comp button on inputs that support it.",
                    isOn: viewModel.binding(\.showInputCompressor)
                )
                SettingsToggleRow(
                    title: "Inputs: EQ",
                    description: "Show the EQ button on inputs.",
                    isOn: viewModel.binding(\.showInputEQ)
                )
                SettingsToggleRow(
                    title: "Outputs: Compressor",
                    description: "Show the Comp button on outputs.",
                    isOn: viewModel.binding(\.showOutputCompressor)
                )
                SettingsToggleRow(
                    title: "Outputs: EQ",
                    description: "Show the EQ button on outputs.",
                    isOn: viewModel.binding(\.showOutputEQ)
                )
                SettingsToggleRow(
                    title: "Outputs: Room EQ",
                    description: "Show the Room EQ button on outputs. It opens the nine-band Room EQ of that output.",
                    isOn: viewModel.binding(\.showOutputRoomEQ)
                )
            }
        }
    }
}

// MARK: - Channels

/// Входы и выходы на одной странице: два списка каналов друг под другом.
struct ChannelsSettingsSection: View {
    let viewModel: SettingsViewModel
    @Binding var expandedOutputs: Set<UUID>
    @Binding var expandedInputs: Set<UUID>
    @Binding var expandedSends: Set<UUID>

    var body: some View {
        VStack(spacing: 16) {
            ReadChannelsSection(viewModel: viewModel)
            InputsSettingsSection(viewModel: viewModel, expanded: $expandedInputs)
            OutputsSettingsSection(viewModel: viewModel, expanded: $expandedOutputs)
            SendsSettingsSection(viewModel: viewModel, expanded: $expandedSends)
        }
    }
}

/// Кнопка, открывающая окно со всеми входами и выходами, которые прислал
/// TotalMix: в этом окне пользователь отмечает каналы для добавления.
struct ReadChannelsSection: View {
    let viewModel: SettingsViewModel

    var body: some View {
        SettingsCard(
            "Read from TotalMix",
            subtitle: "Open a window with every input and output TotalMix reports, then choose the ones to add. Channels that are already configured here stay untouched."
        ) {
            HStack(spacing: 10) {
                Button {
                    viewModel.openChannelDiscovery()
                } label: {
                    Label("Scan channels…", systemImage: "arrow.down.circle")
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// Список выходов: имя, OSC-адрес, иконка и видимость.
struct OutputsSettingsSection: View {
    let viewModel: SettingsViewModel
    @Binding var expanded: Set<UUID>

    var body: some View {
        SettingsCard(
            "Output channels",
            subtitle: "Each output is controlled over OSC. The levels address is derived from the channel number in the OSC address."
        ) {
            if viewModel.outputs.isEmpty {
                Text("No outputs configured.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ForEach(viewModel.outputs) { output in
                OutputSettingsCard(
                    viewModel: viewModel,
                    outputID: output.id,
                    isExpanded: $expanded.contains(output.id)
                )
            }

            Button {
                viewModel.addOutput()
            } label: {
                Label("Add channel", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
        }
    }
}

/// Сворачиваемая карточка выхода.
struct OutputSettingsCard: View {
    let viewModel: SettingsViewModel
    let outputID: UUID
    @Binding var isExpanded: Bool

    var body: some View {
        ExpandableChannelCard(
            title: viewModel.outputName(for: outputID),
            isExpanded: $isExpanded,
            onDelete: { viewModel.removeOutput(outputID) }
        ) {
            LabeledTextField(caption: "Channel name", text: viewModel.outputNameBinding(outputID))
            LabeledTextField(caption: "Channel OSC address", text: viewModel.outputAddressBinding(outputID))
            LabeledValue(caption: "Levels address", value: viewModel.outputLevelAddress(for: outputID))

            SettingsPickerRow("Icon", selection: viewModel.outputIconBinding(outputID)) {
                ForEach(OutputIcon.allCases) { icon in
                    Label(icon.displayName, systemImage: icon.symbolName).tag(icon)
                }
            }

            Divider()

            SettingsToggleRow(
                title: "Show in menu bar",
                isOn: viewModel.outputShowBinding(outputID)
            )

            Divider()

            LabeledTextField(
                caption: "Partner channel for Room EQ",
                text: viewModel.outputPartnerBinding(outputID)
            )
            LabeledValue(caption: "Room EQ address", value: viewModel.partnerLevelHint(outputID))

            Button {
                viewModel.openRoomEQ(outputID)
            } label: {
                Label("Room EQ", systemImage: "waveform.path")
            }
            .disabled(viewModel.roomEQTarget(for: outputID) == nil)
        }
    }
}

// MARK: - Sends

/// Отдельный список посылов: маршрут вход → выход, имя и видимость в поповере.
struct SendsSettingsSection: View {
    let viewModel: SettingsViewModel
    @Binding var expanded: Set<UUID>

    private var canAddSend: Bool {
        viewModel.inputs.contains { !viewModel.availableSendOutputs(for: $0.id).isEmpty }
    }

    var body: some View {
        SettingsCard(
            "Sends",
            subtitle: "Route an input to an output."
        ) {
            if viewModel.sends.isEmpty {
                Text("No sends configured.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ForEach(viewModel.sends) { send in
                SendSettingsCard(
                    viewModel: viewModel,
                    sendID: send.id,
                    isExpanded: $expanded.contains(send.id)
                )
            }

            Menu {
                ForEach(viewModel.inputs.filter { !viewModel.availableSendOutputs(for: $0.id).isEmpty }) { input in
                    Menu {
                        ForEach(viewModel.availableSendOutputs(for: input.id)) { output in
                            Button {
                                viewModel.addSend(inputID: input.id, outputID: output.id)
                            } label: {
                                Text(verbatim: viewModel.outputName(for: output.id))
                            }
                        }
                    } label: {
                        Text(verbatim: viewModel.inputLabel(for: input.id))
                    }
                }
            } label: {
                Label("Add send", systemImage: "plus.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(!canAddSend)
        }
    }
}

/// Сворачиваемая карточка посыла.
struct SendSettingsCard: View {
    let viewModel: SettingsViewModel
    let sendID: UUID
    @Binding var isExpanded: Bool

    var body: some View {
        ExpandableChannelCard(
            title: viewModel.sendName(for: sendID),
            isExpanded: $isExpanded,
            onDelete: { viewModel.removeSend(sendID) },
            deleteHelp: "Delete send"
        ) {
            LabeledTextField(caption: "Name", text: viewModel.sendNameBinding(sendID))
            LabeledValue(caption: "From", value: viewModel.sendInputLabel(for: sendID))
            LabeledValue(caption: "To", value: viewModel.sendOutputName(for: sendID))

            Divider()

            SettingsToggleRow(
                title: "Show in menu bar",
                isOn: viewModel.sendShowBinding(sendID)
            )
        }
    }
}

// MARK: - Inputs

/// Список входов: имя, OSC-адрес, тип и видимость.
struct InputsSettingsSection: View {
    let viewModel: SettingsViewModel
    @Binding var expanded: Set<UUID>

    var body: some View {
        SettingsCard(
            "Input channels",
            subtitle: "Input type controls which preamp buttons are available and where the channel appears."
        ) {
            if viewModel.inputs.isEmpty {
                Text("No inputs configured.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ForEach(viewModel.inputs) { input in
                InputSettingsCard(
                    viewModel: viewModel,
                    inputID: input.id,
                    isExpanded: $expanded.contains(input.id)
                )
            }

            Button {
                viewModel.addInput()
            } label: {
                Label("Add channel", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
        }
    }
}

/// Сворачиваемая карточка входа.
struct InputSettingsCard: View {
    let viewModel: SettingsViewModel
    let inputID: UUID
    @Binding var isExpanded: Bool

    var body: some View {
        ExpandableChannelCard(
            title: viewModel.inputLabel(for: inputID),
            isExpanded: $isExpanded,
            onDelete: { viewModel.removeInput(inputID) }
        ) {
            LabeledTextField(caption: "Channel name", text: viewModel.inputNameBinding(inputID))
            LabeledTextField(caption: "Channel OSC address", text: viewModel.inputAddressBinding(inputID))
            LabeledValue(caption: "Levels address", value: viewModel.inputLevelAddress(for: inputID))

            SettingsPickerRow("Input type", selection: viewModel.inputTypeBinding(inputID)) {
                ForEach(InputType.allCases) { type in
                    Text(verbatim: type.displayName).tag(type)
                }
            }

            Divider()

            SettingsToggleRow(
                title: "Show in menu bar",
                isOn: viewModel.inputShowInPopoverBinding(inputID)
            )

            SettingsToggleRow(
                title: "Show in levels",
                isOn: viewModel.inputShowInLevelsBinding(inputID)
            )
        }
    }
}

// MARK: - Connection

/// Подключение к TotalMix: OSC-хост, порты, адреса Control Room и поведение устройства.
struct ConnectionSettingsSection: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        VStack(spacing: 16) {
            SettingsCard(
                "TotalMix OSC",
                subtitle: "Use Global OSC: TotalMix FX → Options → Mixer Settings → OSC."
            ) {
                EditableTextRow(label: "Host", text: $viewModel.oscHost)
                EditableTextRow(label: "Send port", text: $viewModel.oscSendPort)
                EditableTextRow(label: "Recv port", text: $viewModel.oscRecvPort)

                HStack(spacing: 10) {
                    Button("Apply") {
                        viewModel.applyOSCSettings()
                    }
                    if viewModel.showOSCError {
                        Label("Invalid ports", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Divider()

                Button {
                    viewModel.openOSCMonitor()
                } label: {
                    Label("OSC Monitor", systemImage: "waveform.path.ecg")
                }
            }

            SettingsCard(
                "Control Room commands",
                subtitle: "OSC addresses for the Speaker B, Dim and Mono buttons. Change them only if your TotalMix setup uses different addresses."
            ) {
                EditableTextRow(label: "Speaker B", text: viewModel.binding(\.speakerBAddress))
                EditableTextRow(label: "Dim", text: viewModel.binding(\.dimAddress))
                EditableTextRow(label: "Mono", text: viewModel.binding(\.monoAddress))
            }

            SettingsCard(
                "Device",
                subtitle: "How RME Control treats a missing audio interface."
            ) {
                SettingsToggleRow(
                    title: "Disconnect when no device",
                    description: "Treat a missing audio interface as a disconnected TotalMix.",
                    isOn: viewModel.binding(\.watchDeviceConnection)
                )
            }
        }
    }
}

// MARK: - Web remote

/// Встроенный веб-сервер, его адрес, QR-код и состав страницы.
struct RemoteSettingsSection: View {
    let viewModel: SettingsViewModel

    var body: some View {
        VStack(spacing: 16) {
            SettingsCard(
                "HTTP server",
                subtitle: "The web remote works in any browser on the same Wi-Fi network."
            ) {
                SettingsToggleRow(
                    title: "Enable web remote",
                    description: "Start the built-in HTTP server.",
                    isOn: viewModel.binding(\.webServerEnabled)
                )

                if viewModel.webServerEnabled {
                    Divider()
                    HStack(spacing: 12) {
                        Text("Port")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 12)
                        TextField("", value: viewModel.webServerPortBinding, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }

                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Address")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Text(verbatim: viewModel.webURLString)
                                .font(.callout)
                                .monospaced()
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .textSelection(.enabled)
                        }
                        Spacer(minLength: 12)
                        Button {
                            viewModel.copyWebURL()
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("Copy address")
                    }

                    if let qr = viewModel.webQRCode {
                        HStack {
                            Spacer()
                            Image(nsImage: qr)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: 150, height: 150)
                            Spacer()
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Link("Open on this Mac", destination: URL(string: viewModel.webURLString)!)
                        Text("Scan with your phone camera — same Wi-Fi")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }

            SettingsCard(
                "Web Remote Layout",
                subtitle: "Choose which controls are visible on the web page. These options apply immediately."
            ) {
                SettingsToggleRow(
                    title: "Buttons",
                    description: "Dim, Mono and Speaker B.",
                    isOn: viewModel.binding(\.webShowButtons)
                )
                SettingsToggleRow(
                    title: "Inputs",
                    description: "Preamp switches for +48V and Inst.",
                    isOn: viewModel.binding(\.webShowInputs)
                )
                SettingsToggleRow(
                    title: "Levels",
                    description: "Input level meters.",
                    isOn: viewModel.binding(\.webShowLevels)
                )
            }
        }
    }
}

// MARK: - About

/// Версия и разработчик.
struct AboutSettingsSection: View {
    let viewModel: SettingsViewModel

    var body: some View {
        VStack(spacing: 16) {
            SettingsCard("RME Control", subtitle: "Menu bar control for RME TotalMix FX over OSC.") {
                HStack(alignment: .top, spacing: 14) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: "RME Control")
                            .font(.headline)
                        Text("Version \(viewModel.appVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            Text("Developed by")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Link("Egor Repentov",
                                 destination: URL(string: "https://repentov-dev.github.io/repentov-site/")!)
                                .font(.caption)
                        }
                        Link("Project website",
                             destination: URL(string: "https://repentov-dev.github.io/rme-control/")!)
                            .font(.caption)
                        Link("Room EQ engine: roomeq / AutoEQ (GPL-3.0)",
                             destination: URL(string: "https://github.com/pierreaubert/autoeq")!)
                            .font(.caption)
                        Link("Measurement engine: sotf-capture (GPL-3.0)",
                             destination: URL(string: "https://github.com/pierreaubert/sotf-capture")!)
                            .font(.caption)
                    }
                }
            }

            Text("RME, TotalMix and the RME logo are trademarks of RME Audio AG. This project is an independent tool and is not affiliated with, endorsed by, or supported by RME Audio.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Helpers

private extension Binding where Value == Set<UUID> {
    /// Привязка «раскрыта ли карточка канала» к множеству раскрытых id.
    func contains(_ id: UUID) -> Binding<Bool> {
        Binding<Bool>(
            get: { wrappedValue.contains(id) },
            set: { expanded in
                if expanded {
                    wrappedValue.insert(id)
                } else {
                    wrappedValue.remove(id)
                }
            }
        )
    }
}

// MARK: - Calibration

/// Маршрутизация мастера замера: через матрицу TotalMix или напрямую
/// в software playback-пару.
struct CalibrationSettingsSection: View {
    let viewModel: SettingsViewModel

    var body: some View {
        VStack(spacing: 16) {
            SettingsCard("Routing", subtitle: "How the measurement wizard sends sound to the interface. OSC routes the playback pair and mutes other outputs in TotalMix; software playback sends audio directly and leaves the matrix untouched.") {
                HStack {
                    Text("Mode")
                        .font(.callout)
                    Spacer(minLength: 12)
                    Picker("", selection: viewModel.binding(\.calibrationRouting)) {
                        Text("OSC (TotalMix)").tag(CalibrationRoutingMode.osc)
                        Text("Software playback").tag(CalibrationRoutingMode.softwarePlayback)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 220)
                }

                Divider().opacity(0.5)

                HStack {
                    Text("Software playback output")
                        .font(.callout)
                    Spacer(minLength: 12)
                    Picker("", selection: viewModel.binding(\.calibrationPlaybackPair)) {
                        ForEach(0..<16, id: \.self) { left in
                            Text(verbatim: "\(left * 2 + 1)/\(left * 2 + 2)").tag(left)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 220)
                    .disabled(viewModel.calibrationRouting == .osc)
                }

                Text(viewModel.calibrationRouting == .osc
                     ? "Default: the wizard routes the selected output through OSC and restores TotalMix when the measurement finishes."
                     : "The wizard plays into the chosen playback pair only. Make sure TotalMix routes it to the speakers you are measuring.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
