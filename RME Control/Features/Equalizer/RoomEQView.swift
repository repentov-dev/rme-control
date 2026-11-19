import AppKit
import SwiftUI

/// Окно Room EQ выходного канала. Выглядит и управляется как эквалайзер канала:
/// та же шапка, тот же график с подписями и тултипами, те же жесты. Ниже —
/// полоса функций Room EQ: выбор канала стереопары, задержка, калибровка
/// громкости и crossfeed.
struct RoomEQView: View {
    static let contentSize = NSSize(width: 560, height: 560)
    static let parametricPanelHeight: CGFloat = 280

    let viewModel: MixerViewModel
    let target: RoomEQTarget
    var onClose: @MainActor () -> Void
    var onMeasure: (@MainActor () -> Void)? = nil

    /// Какой канал пары показан. `.both` живёт только в `editChannel`.
    @State private var side: RoomEQChannel = .left
    /// Связь каналов: правки уходят в оба. По умолчанию включена, как раньше.
    @State private var linked = true
    @State private var headerHovered = false
    @State private var showingSavePreset = false
    @State private var showingManagePresets = false
    @State private var module = MeasurementModule.shared
    @State private var showingParametricEQ = false
    @State private var hostWindow: NSWindow?
    @State private var presetName = ""

    /// Канал, в который уходят правки.
    private var editChannel: RoomEQChannel { linked ? .both : side }

    var body: some View {
        let room = viewModel.roomEQ(target, channel: side)

        VStack(spacing: 8) {
            header(room: room)
            EQGraphView(model: model(for: room), actions: actions)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                showingParametricEQ.toggle()
            } label: {
                Image(systemName: showingParametricEQ ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 13)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .help("Parametric EQ")

            if showingParametricEQ {
                RoomEQParametricPanel(
                    state: viewModel.roomEQ(target, channel: side),
                    channel: editChannel,
                    linked: linked,
                    onSet: { parameter, value in set(parameter, value) },
                    onClose: { showingParametricEQ = false }
                )
            }

            controls(left: viewModel.roomEQ(target, channel: .left),
                     right: viewModel.roomEQ(target, channel: .right))
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        .frame(width: Self.contentSize.width,
               height: Self.contentSize.height
                    + (showingParametricEQ ? Self.parametricPanelHeight : 0))
        .background(WindowAccessor { window in
            guard hostWindow !== window else { return }
            hostWindow = window
            if showingParametricEQ { resizeWindow(expanded: true) }
        })
        .panelSurface(cornerRadius: 12)
        .onChange(of: showingParametricEQ) { _, expanded in
            resizeWindow(expanded: expanded)
        }
        .alert("Save preset", isPresented: $showingSavePreset) {
            TextField("Preset name", text: $presetName)
            Button("Save") { saveCurrentPreset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Save the current nine bands and calibration as a preset.")
        }
        .sheet(isPresented: $showingManagePresets) {
            RoomEQPresetManagerView(mixer: viewModel)
        }
    }

    private func resizeWindow(expanded: Bool) {
        guard let window = hostWindow else { return }
        let targetHeight = Self.contentSize.height + (expanded ? Self.parametricPanelHeight : 0)
        let targetSize = NSSize(width: Self.contentSize.width, height: targetHeight)
        let top = window.frame.maxY
        window.minSize = targetSize
        window.maxSize = targetSize
        window.contentView?.frame = NSRect(origin: .zero, size: targetSize)
        window.setContentSize(targetSize)
        var frame = window.frame
        frame.origin.y = top - frame.height
        if let screen = window.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            if frame.minY < visible.minY { frame.origin.y = visible.minY }
        }
        window.setFrame(frame, display: true, animate: true)
    }

    // MARK: - Шапка

    /// Включён ли Room EQ у окна целиком: хотя бы один канал пары.
    private var windowRoomEQEnabled: Bool {
        if viewModel.roomEQ(target, channel: .left).enabled { return true }
        guard target.hasPartner else { return false }
        return viewModel.roomEQ(target, channel: .right).enabled
    }

    private func header(room: RoomEQState) -> some View {
        let roomOn = windowRoomEQEnabled
        return HStack(spacing: 10) {
            PanelCloseButton(showGlyph: headerHovered, action: onClose)

            WindowDragHandle()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            RoomEQPresetPicker(
                state: room,
                userPresets: viewModel.roomEQUserPresets,
                onApply: { preset in apply(preset) },
                onApplyUser: { preset in apply(preset) },
                onApplyDefault: { applyDefault() }
            )

            Menu {
                Button("Save current as…") {
                    presetName = ""
                    showingSavePreset = true
                }
                Button("Manage presets…") {
                    showingManagePresets = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 11, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Room EQ presets")

            if let onMeasure {
                measureButton(onMeasure)
            }

            Text(target.label)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .overlay(WindowDragHandle())

            Toggle(
                "Room EQ",
                isOn: Binding(
                    get: { roomOn },
                    set: { viewModel.setRoomEQEnabled(target, channel: .both, $0) }
                )
            )
            .toggleStyle(.switch)
            .tint(.accentColor)
            .controlSize(.small)
            .labelsHidden()
            .help(roomOn ? "Bypass" : "Enable")
        }
        .frame(height: 28)
        .onHover { headerHovered = $0 }
    }

    // MARK: - Полоса функций Room EQ

    private func controls(left: RoomEQState, right: RoomEQState) -> some View {
        RoomEQControls(
            target: target,
            left: left,
            right: right,
            side: $side,
            linked: $linked,
            onSet: { parameter, value, channel in
                set(parameter, value, channel: linked ? .both : channel)
            },
            onMix: { value, _ in
                viewModel.setRoomEQMix(target, channel: .both, value)
            }
        )
    }

    /// Нет модуля замера — кнопка качает его с GitHub, есть — открывает Measure.
    @ViewBuilder
    private func measureButton(_ onMeasure: @escaping @MainActor () -> Void) -> some View {
        switch module.phase {
        case .installed:
            Button(String(format: String(localized: "Measure (%@)"), MeasurementModule.version),
                   action: onMeasure)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Measure the room and calculate a correction")
        case .downloading(let progress):
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.mini)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
            }
            .padding(.horizontal, 8)
            .frame(height: 18)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
        case .missing, .failed:
            Button("Download measure") {
                Task { await module.download() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .help("Download the measurement module")
        }
    }

    // MARK: - Модель графика

    private func model(for room: RoomEQState) -> EQGraphModel {
        let otherSide: RoomEQChannel = side == .right ? .left : .right
        let other = target.hasPartner ? viewModel.roomEQ(target, channel: otherSide) : nil
        let selectedColor = roomEQChannelColor(side)
        let otherColor = roomEQChannelColor(otherSide)
        // Коэффициенты полос считаются один раз на отрисовку, а не на каждую
        // точку кривой — иначе перетаскивание ручки упирается в ~30 кадров.
        let prepared = RoomEQResponse.Prepared(state: room)
        let preparedOther = other.map { RoomEQResponse.Prepared(state: $0) }

        return EQGraphModel(
            bands: (1...RoomEQState.bandCount).map { number in
                let band = room.band(number)
                return EQGraphBand(
                    number: number,
                    frequency: band.frequency,
                    gain: band.gain,
                    q: band.q,
                    type: band.type
                )
            },
            enabled: room.enabled,
            cut: nil,
            labelMode: .focused,
            typedKinds: Dictionary(
                uniqueKeysWithValues: RoomEQBand.typedBands.map { ($0, RoomEQFilterKinds.kinds(for: $0)) }
            ),
            bandColor: { RoomEQStyle.color(for: $0) },
            cutColor: .purple,
            responseDb: { prepared.db(at: $0) },
            bandResponseDb: { number, frequency in
                prepared.bandDb(number, at: frequency)
            },
            curveColor: target.hasPartner ? selectedColor : nil,
            fillColor: target.hasPartner ? selectedColor : nil,
            reference: other.map { state in
                EQGraphReference(
                    responseDb: { preparedOther?.db(at: $0) ?? 0 },
                    color: otherColor,
                    enabled: state.enabled
                )
            }
        )
    }

    private var actions: EQGraphActions {
        EQGraphActions(
            setPosition: { band, frequency, gain in
                set(.bandFrequency(band), frequency)
                set(.bandGain(band), gain)
            },
            setQ: { band, q in
                set(.bandQ(band), q)
            },
            addQ: { band, delta in
                let current = viewModel.roomEQ(target, channel: side).band(band).q
                set(.bandQ(band), current + delta)
            },
            currentQ: { band in
                viewModel.roomEQ(target, channel: side).band(band).q
            },
            setType: { band, index in
                set(.bandType(band), Double(index))
            },
            resetBand: { band in
                set(.bandGain(band), 0)
            },
            setCutFrequency: { _ in },
            toggleCut: {},
            setCutSlope: { _ in }
        )
    }

    private func apply(_ preset: RoomEQUserPreset) {
        let channel: RoomEQChannel
        switch preset.mode {
        case "left": channel = .left
        case "right": channel = .right
        case "stereo": channel = .both
        default: channel = editChannel
        }
        let bands = preset.bands.map {
            RoomEQBand(frequency: $0.frequency, gain: $0.gain, q: $0.q, type: $0.type)
        }
        viewModel.applyRoomEQBands(target, channel: channel, bands, preamp: preset.preamp)
        // Delay не восстанавливаем: он остаётся ручным.
        let common = min(preset.preamp,
                         preset.calibrationLeft ?? preset.preamp,
                         preset.calibrationRight ?? preset.preamp)
        viewModel.setRoomEQParameter(target, channel: .both, .volumeCalibration, common)
        viewModel.setRoomEQEnabled(target, channel: .both, true)
    }

    private func applyDefault() {
        let flat = RoomEQState.factoryBands.map { band -> RoomEQBand in
            var copy = band
            copy.gain = 0
            return copy
        }
        viewModel.applyRoomEQBands(target, channel: .both, flat, preamp: 0)
        viewModel.setRoomEQParameter(target, channel: .both, .crossfeed, 0)
        viewModel.setRoomEQEnabled(target, channel: .both, true)
    }

    private func saveCurrentPreset() {
        let state = viewModel.roomEQ(target, channel: side)
        let trimmed = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Сохраняем полный набор, а не текущий Mix.
        let bands = state.baseBands.map {
            RoomEQPresetBand(frequency: $0.frequency, gain: $0.gain, q: $0.q, type: $0.type)
        }
        let mode: RoomCorrectionChannel = linked ? .stereo : (side == .left ? .left : .right)
        let left = viewModel.roomEQ(target, channel: .left)
        let right = viewModel.roomEQ(target, channel: .right)
        let common = min(left.volumeCalibration, right.volumeCalibration)
        viewModel.saveRoomEQUserPreset(
            name: trimmed,
            bands: bands,
            preamp: state.volumeCalibration,
            mode: mode,
            delayLeft: nil,
            delayRight: nil,
            calibrationLeft: target.hasPartner ? common : nil,
            calibrationRight: target.hasPartner ? common : nil
        )
    }

    private func set(_ parameter: RoomEQParameter, _ value: Double,
                     channel: RoomEQChannel? = nil) {
        let clamped = min(max(value, parameter.range.lowerBound), parameter.range.upperBound)
        let rounded: Double
        switch parameter {
        case .bandFrequency, .bandType:
            rounded = clamped.rounded()
        case .delay:
            rounded = (clamped * 100).rounded() / 100
        default:
            rounded = (clamped * 10).rounded() / 10
        }
        let destination: RoomEQChannel = linked ? .both : (channel ?? side)
        viewModel.setRoomEQParameter(target, channel: destination, parameter, rounded)
    }

    /// Ставит все девять полос пресета и включает Room EQ, если он выключен.
    private func apply(_ preset: RoomEQPreset) {
        let bands = preset.bands.map {
            RoomEQBand(frequency: $0.frequency, gain: $0.gain, q: $0.q, type: $0.type)
        }
        viewModel.applyRoomEQBands(target, channel: editChannel, bands, preamp: preset.preamp)
        if !viewModel.roomEQ(target, channel: side).enabled {
            viewModel.setRoomEQEnabled(target, channel: editChannel, true)
        }
    }
}

/// Меню пресетов в шапке — как у компрессора: пользовательские и по брендам.
private struct RoomEQPresetPicker: View {
    let state: RoomEQState
    let userPresets: [RoomEQUserPreset]
    let onApply: (RoomEQPreset) -> Void
    let onApplyUser: (RoomEQUserPreset) -> Void
    let onApplyDefault: () -> Void

    private var activeBuiltIn: RoomEQPreset? {
        RoomEQPresets.all.first { $0.matches(state) }
    }

    private var activeUser: RoomEQUserPreset? {
        userPresets.first { preset in
            guard preset.bands.count == state.bands.count else { return false }
            for (index, band) in preset.bands.enumerated() {
                let current = state.bands[index]
                if abs(current.frequency - band.frequency) > 0.5
                    || abs(current.gain - band.gain) > 0.05
                    || abs(current.q - band.q) > 0.05
                    || current.type != band.type {
                    return false
                }
            }
            return true
        }
    }

    private var isDefault: Bool {
        state.mix > 0.99
            && abs(state.delay) < 0.001
            && abs(state.crossfeed) < 0.001
            && abs(state.volumeCalibration) < 0.05
            && state.bands.allSatisfy { abs($0.gain) < 0.05 }
    }

    private var activeID: String {
        if let activeUser { return activeUser.id.uuidString }
        if let activeBuiltIn { return activeBuiltIn.id }
        if isDefault { return "default" }
        return "custom"
    }

    private var selection: Binding<String> {
        Binding(
            get: { activeID },
            set: { id in
                if id == "default" {
                    onApplyDefault()
                    return
                }
                if let preset = RoomEQPresets.all.first(where: { $0.id == id }) {
                    onApply(preset)
                } else if let preset = userPresets.first(where: { $0.id.uuidString == id }) {
                    onApplyUser(preset)
                }
            }
        )
    }

    var body: some View {
        Picker("Preset", selection: selection) {
            Text("Custom").tag("custom")
            Text("Default").tag("default")
            if !userPresets.isEmpty {
                Section("My presets") {
                    ForEach(userPresets) { preset in
                        Text(preset.name).tag(preset.id.uuidString)
                    }
                }
            }
            ForEach(RoomEQPresets.groups) { group in
                Section(group.brand) {
                    ForEach(group.presets) { preset in
                        Text(preset.model).tag(preset.id)
                    }
                }
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .help("Headphone and room correction preset")
    }
}

/// Управление пользовательскими пресетами: переименование и удаление.
private struct RoomEQPresetManagerView: View {
    let mixer: MixerViewModel
    @State private var presets: [RoomEQUserPreset]
    @Environment(\.dismiss) private var dismiss

    init(mixer: MixerViewModel) {
        self.mixer = mixer
        _presets = State(initialValue: mixer.roomEQUserPresets)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("My presets")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            if presets.isEmpty {
                Text("No saved presets yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach($presets) { $preset in
                            RoomEQPresetManagerRow(
                                preset: $preset,
                                onRename: { name in
                                    mixer.renameRoomEQUserPreset(id: preset.id, name: name)
                                },
                                onDelete: {
                                    let id = preset.id
                                    presets.removeAll { $0.id == id }
                                    mixer.deleteRoomEQUserPreset(id: id)
                                }
                            )
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 380, height: 400)
    }
}

private struct RoomEQPresetManagerRow: View {
    @Binding var preset: RoomEQUserPreset
    let onRename: (String) -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("Name", text: $preset.name)
                .textFieldStyle(.roundedBorder)
                .onChange(of: preset.name) { _, newValue in
                    onRename(newValue)
                }
            Button("Rename") {
                onRename(preset.name)
            }
            .controlSize(.small)
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
    }
}

/// Цвет канала: LEFT оранжевый, RIGHT синий — как у кнопок и кривых.
private func roomEQChannelColor(_ channel: RoomEQChannel) -> Color {
    channel == .left ? .orange : .blue
}

// MARK: - Полоса управления

/// Нижняя полоса: канал стереопары и параметры Room EQ отдельно для L и R.
/// При включённом link обе ручки двигают оба канала в TotalMix.
private struct RoomEQControls: View {
    let target: RoomEQTarget
    let left: RoomEQState
    let right: RoomEQState
    @Binding var side: RoomEQChannel
    @Binding var linked: Bool
    let onSet: (RoomEQParameter, Double, RoomEQChannel) -> Void
    let onMix: (Double, RoomEQChannel) -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                if target.hasPartner {
                    channelColumn
                }

                parameterColumn(
                    title: "Delay ms",
                    left: left.delay,
                    right: right.delay,
                    range: RoomEQParameter.delay.range,
                    divisions: nil,
                    neutral: 0,
                    format: { String(format: "%.2f ms", $0) }
                ) { value, channel in
                    onSet(.delay, value, channel)
                }

                parameterColumn(
                    title: "Volume calibration dB",
                    left: left.volumeCalibration,
                    right: right.volumeCalibration,
                    range: RoomEQParameter.volumeCalibration.range,
                    divisions: nil,
                    neutral: 0,
                    format: { $0 == 0 ? "0.0 dB" : String(format: "%+.1f dB", $0) }
                ) { value, channel in
                    onSet(.volumeCalibration, value, channel)
                }
                .disabled(!(left.enabled || right.enabled))
                .opacity((left.enabled || right.enabled) ? 1 : 0.45)
            }

            Divider()
                .opacity(0.35)

            HStack(spacing: 12) {
                globalControl(
                    title: "Mix",
                    value: left.mix,
                    range: 0...1,
                    divisions: nil,
                    neutral: 1,
                    format: { "\(Int(($0 * 100).rounded()))%" }
                ) { onMix($0, .both) }

                Rectangle()
                    .fill(Color.primary.opacity(0.10))
                    .frame(width: 1, height: 18)

                globalControl(
                    title: "Crossfeed",
                    value: left.crossfeed,
                    range: RoomEQParameter.crossfeed.range,
                    divisions: 5,
                    neutral: 0,
                    format: { $0 < 0.5 ? String(localized: "Off") : String(format: "%.0f", $0) }
                ) { onSet(.crossfeed, $0, .both) }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var channelColumn: some View {
        VStack(alignment: .leading, spacing: 7) {
            RoomEQSectionLabel("Channel")
            RoomEQChannelSelector(side: $side, linked: $linked) { _ in }
            HStack(spacing: 4) {
                Circle()
                    .fill(linked ? Color.green : Color.secondary.opacity(0.6))
                    .frame(width: 5, height: 5)
                Text(linked ? String(localized: "Linked") : side.title)
                    .font(.system(size: 9))
                    .foregroundStyle(linked ? Color.green : Color.secondary)
                    .lineLimit(1)
            }
            .padding(.leading, 1)
        }
        .frame(width: 148, alignment: .leading)
    }

    private func parameterColumn(
        title: LocalizedStringKey,
        left leftValue: Double,
        right rightValue: Double,
        range: ClosedRange<Double>,
        divisions: Int?,
        neutral: Double,
        format: @escaping (Double) -> String,
        onChange: @escaping (Double, RoomEQChannel) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            RoomEQSectionLabel(title)
            row(.left, value: leftValue, range: range, divisions: divisions,
                neutral: neutral, format: format, onChange: onChange)
            row(.right, value: rightValue, range: range, divisions: divisions,
                neutral: neutral, format: format, onChange: onChange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ channel: RoomEQChannel,
                     value: Double,
                     range: ClosedRange<Double>,
                     divisions: Int?,
                     neutral: Double,
                     format: @escaping (Double) -> String,
                     onChange: @escaping (Double, RoomEQChannel) -> Void) -> some View {
        let color = roomEQChannelColor(channel)
        return HStack(spacing: 6) {
            Text(channel == .left ? "L" : "R")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 10, alignment: .leading)

            RoomEQMiniSlider(
                value: value,
                range: range,
                origin: 0,
                divisions: divisions,
                neutral: neutral,
                color: color
            ) { newValue in
                onChange(newValue, channel)
            }

            RoomEQEditableValue(
                value: value,
                range: range,
                format: format,
                channel: channel,
                onChange: onChange
            )
            .frame(width: 54, alignment: .trailing)
        }
        .frame(height: 19)
    }

    private func globalControl(
        title: LocalizedStringKey,
        value: Double,
        range: ClosedRange<Double>,
        divisions: Int?,
        neutral: Double,
        format: @escaping (Double) -> String,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            RoomEQSectionLabel(title)
                .frame(width: 62, alignment: .leading)
            RoomEQMiniSlider(
                value: value,
                range: range,
                origin: 0,
                divisions: divisions,
                neutral: neutral,
                color: .accentColor
            ) { newValue in
                onChange(newValue)
            }
            Text(format(value))
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct RoomEQEditableValue: View {
    let value: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String
    let channel: RoomEQChannel
    let onChange: (Double, RoomEQChannel) -> Void

    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if editing {
                TextField("", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 9).monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .focused($focused)
                    .onAppear { focused = true }
                    .onSubmit { commit() }
                    .onExitCommand { cancel() }
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused, editing { commit() }
                    }
            } else {
                Text(format(value))
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { beginEditing() }
                    .help("Double-click to type a value")
            }
        }
    }

    private func beginEditing() {
        draft = format(value)
            .filter { $0.isNumber || $0 == "." || $0 == "," || $0 == "-" }
        editing = true
    }

    private func commit() {
        let parsed = draft.replacingOccurrences(of: ",", with: ".")
        if let number = Double(parsed), number.isFinite {
            onChange(min(max(number, range.lowerBound), range.upperBound), channel)
        }
        editing = false
        focused = false
    }

    private func cancel() {
        editing = false
        focused = false
    }
}

private struct RoomEQSectionLabel: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 8, weight: .semibold))
            .textCase(.uppercase)
            .tracking(0.65)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

/// Тонкая шкала без подписи: L/R строка параметра.
private struct RoomEQMiniSlider: View {
    let value: Double
    let range: ClosedRange<Double>
    let origin: Double
    let divisions: Int?
    let neutral: Double
    let color: Color
    let onChange: (Double) -> Void

    private var progress: Double {
        min(max((value - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
    }

    private var originProgress: Double {
        min(max((origin - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
    }

    private var position: Double {
        guard let divisions, divisions > 0 else { return progress }
        return (progress * Double(divisions)).rounded() / Double(divisions)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.10))
                    .frame(height: 4)

                if originProgress > 0.001 {
                    Rectangle()
                        .fill(Color.primary.opacity(0.22))
                        .frame(width: 1, height: 8)
                        .offset(x: width * originProgress)
                }

                if let divisions, divisions > 0 {
                    ForEach(0...divisions, id: \.self) { index in
                        Rectangle()
                            .fill(Color.primary.opacity(0.16))
                            .frame(width: 1, height: 5)
                            .offset(x: width * CGFloat(index) / CGFloat(divisions))
                    }
                }

                Capsule()
                    .fill(color.opacity(0.85))
                    .frame(width: max(2, abs(position - originProgress) * width), height: 4)
                    .offset(x: min(position, originProgress) * width)

                Circle()
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .overlay(Circle().strokeBorder(color.opacity(0.7), lineWidth: 0.6))
                    .frame(width: 9, height: 9)
                    .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 0.5)
                    .offset(x: max(0, min(width * position - 4.5, width - 9)))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let fraction = min(max(gesture.location.x / width, 0), 1)
                        let snapped: Double
                        if let divisions, divisions > 0 {
                            snapped = (fraction * Double(divisions)).rounded() / Double(divisions)
                        } else {
                            snapped = fraction
                        }
                        onChange(range.lowerBound + snapped * (range.upperBound - range.lowerBound))
                    }
            )
            .simultaneousGesture(
                TapGesture(count: 2).onEnded { onChange(neutral) }
            )
        }
        .frame(height: 12)
    }
}

/// Переключатель канала и связи — как LEFT / link / RIGHT в Room EQ TotalMix.
/// Пока связь включена, кнопки каналов нейтральные, а цепочка зелёная.
private struct WindowAccessor: NSViewRepresentable {
    let onChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onChange(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onChange(nsView.window) }
    }
}

private struct RoomEQParametricPanel: View {
    let state: RoomEQState
    let channel: RoomEQChannel
    let linked: Bool
    let onSet: (RoomEQParameter, Double) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Parametric EQ")
                    .font(.headline)
                Spacer()
                Text(linked ? String(localized: "Linked") : channel.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.borderless)
            }

            HStack(alignment: .top, spacing: 0) {
                labels
                ForEach(1...RoomEQState.bandCount, id: \.self) { number in
                    bandColumn(number)
                    if number == 3 || number == 6 {
                        Rectangle()
                            .fill(Color.primary.opacity(0.10))
                            .frame(width: 1, height: 222)
                            .padding(.horizontal, 3)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Band").frame(height: 20, alignment: .leading)
            Text("Gain dB").frame(height: 60, alignment: .center)
            Text("Freq Hz").frame(height: 60, alignment: .center)
            Text("Q").frame(height: 60, alignment: .center)
            Text("Type").frame(height: 22, alignment: .center)
        }
        .font(.system(size: 7.5, weight: .heavy))
        .textCase(.uppercase)
        .foregroundStyle(.secondary)
        .frame(width: 40, alignment: .leading)
    }

    private func bandColumn(_ number: Int) -> some View {
        let band = state.band(number)
        let color = bandColor(number)
        return VStack(spacing: 0) {
            Text("\(number)")
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(height: 20)

            RoomEQKnob(value: band.gain, range: -20...20,
                       logarithmic: false, neutral: 0, color: color,
                       format: { String(format: "%+.1f", $0) },
                       editFormat: { String(format: "%.1f", $0) }) {
                onSet(.bandGain(number), $0)
            }
            .frame(height: 60)

            RoomEQKnob(value: band.frequency, range: 20...20_000,
                       logarithmic: true, neutral: 1_000, color: color,
                       format: { formatFrequency($0) },
                       editFormat: { String(format: "%.0f", $0) }) {
                onSet(.bandFrequency(number), $0)
            }
            .frame(height: 60)

            RoomEQKnob(value: band.q, range: 0.4...9.9,
                       logarithmic: true, neutral: 1, color: color,
                       format: { String(format: "%.2f", $0) },
                       editFormat: { String(format: "%.2f", $0) }) {
                onSet(.bandQ(number), $0)
            }
            .frame(height: 60)

            typeControl(number: number, band: band, color: color)
                .frame(height: 22)
        }
        .frame(width: 50)
    }

    private func typeControl(number: Int, band: RoomEQBand, color: Color) -> some View {
        let kinds = RoomEQFilterKinds.kinds(for: number)
        let selected = min(max(band.type, 0), kinds.count - 1)
        if RoomEQBand.typedBands.contains(number) {
            return AnyView(
                BandTypeMenu(kinds: kinds,
                             selected: selected,
                             names: kinds.map { typeName($0) },
                             color: color) { index in
                    onSet(.bandType(number), Double(index))
                }
            )
        } else {
            return AnyView(
                EQTypeIcon(kind: kinds[selected])
                    .stroke(color.opacity(0.55), lineWidth: 1.2)
                    .frame(width: 22, height: 12)
            )
        }
    }

    private func bandColor(_ number: Int) -> Color {
        switch number {
        case 1...3: return EQPalette.low
        case 4...6: return EQPalette.mid
        default: return EQPalette.high
        }
    }

    private func typeName(_ kind: EQTypeIcon.Kind) -> String {
        switch kind {
        case .bell: return "PK"
        case .lowShelf: return "LS"
        case .highShelf: return "HS"
        case .highPass: return "HP"
        case .lowPass: return "LP"
        }
    }

    private func formatFrequency(_ frequency: Double) -> String {
        if frequency >= 1_000 {
            return String(format: "%.2gk", frequency / 1_000)
        }
        return String(format: "%.0f", frequency)
    }
}

private struct RoomEQKnob: View {
    let value: Double
    let range: ClosedRange<Double>
    let logarithmic: Bool
    let neutral: Double
    let color: Color
    let format: (Double) -> String
    let editFormat: (Double) -> String
    let onChange: (Double) -> Void

    @State private var dragStart: Double?
    @State private var lastClick: Date?
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var progress: Double {
        let raw: Double
        if logarithmic {
            raw = (log(value) - log(range.lowerBound))
                / (log(range.upperBound) - log(range.lowerBound))
        } else {
            raw = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        }
        return min(max(raw, 0), 1)
    }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Color.primary.opacity(PanelOpacity.control),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .padding(4)

                Circle()
                    .trim(from: 0, to: 0.75 * progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .padding(4)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.primary.opacity(PanelOpacity.card),
                                Color.primary.opacity(PanelOpacity.control)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        Circle().strokeBorder(Color.primary.opacity(PanelOpacity.card), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.16), radius: 1.5, x: 0, y: 1)
                    .padding(9)

                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let angle = Angle.degrees(135 + 270 * progress).radians
                    let inner = CGPoint(x: center.x + 4 * cos(angle), y: center.y + 4 * sin(angle))
                    let outer = CGPoint(x: center.x + 11 * cos(angle), y: center.y + 11 * sin(angle))
                    var pointer = Path()
                    pointer.move(to: inner)
                    pointer.addLine(to: outer)
                    context.stroke(pointer, with: .color(color),
                                   style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            }
            .frame(width: 48, height: 48)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let start = dragStart ?? progress
                        if dragStart == nil { dragStart = start }
                        let next = min(max(start - gesture.translation.height / 130, 0), 1)
                        onChange(value(for: next))
                    }
                    .onEnded { gesture in
                        if abs(gesture.translation.height) < 2, abs(gesture.translation.width) < 2 {
                            let now = Date()
                            if let lastClick, now.timeIntervalSince(lastClick) < 0.35 {
                                onChange(neutral)
                                self.lastClick = nil
                            } else {
                                lastClick = now
                            }
                        }
                        dragStart = nil
                    }
            )

            Group {
                if editing {
                    TextField("", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 9).monospacedDigit())
                        .multilineTextAlignment(.center)
                        .focused($focused)
                        .onAppear { focused = true }
                        .onSubmit { commit() }
                        .onExitCommand { cancel() }
                        .onChange(of: focused) { _, isFocused in
                            if !isFocused, editing { commit() }
                        }
                        .frame(width: 50)
                } else {
                    Text(format(value))
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: 50)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { beginEditing() }
                        .help("Double-click to type a value")
                }
            }
            .frame(height: 14)
        }
        .frame(height: 60)
    }

    private func beginEditing() {
        draft = editFormat(value)
        editing = true
    }

    private func commit() {
        if let number = Double(draft.replacingOccurrences(of: ",", with: ".")),
           number.isFinite {
            onChange(min(max(number, range.lowerBound), range.upperBound))
        }
        editing = false
        focused = false
    }

    private func cancel() {
        editing = false
        focused = false
    }

    private func value(for normalized: Double) -> Double {
        if logarithmic {
            let lower = log(range.lowerBound)
            let upper = log(range.upperBound)
            return exp(lower + normalized * (upper - lower))
        }
        return range.lowerBound + normalized * (range.upperBound - range.lowerBound)
    }
}

private struct RoomEQChannelSelector: View {
    @Binding var side: RoomEQChannel
    @Binding var linked: Bool
    let onLinkChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: 4) {
            channelButton(.left)
            linkButton
            channelButton(.right)
        }
        .frame(height: 24)
    }

    private func channelButton(_ channel: RoomEQChannel) -> some View {
        let isSelected = side == channel
        let color = roomEQChannelColor(channel)
        let textColor = isSelected && !linked ? color : (isSelected ? Color.primary : Color.secondary)
        let borderColor = isSelected && !linked
            ? color.opacity(0.9)
            : (isSelected ? Color.primary.opacity(0.35) : Color.primary.opacity(0.18))

        return Button {
            side = channel
            if linked {
                linked = false
                onLinkChange(false)
            }
        } label: {
            Text(channel.title)
                .font(.system(size: 9, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.4)
                .foregroundStyle(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(width: 54, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected && !linked ? color.opacity(0.16) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(borderColor, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(channel == .left ? String(localized: "Left channel") : String(localized: "Right channel"))
    }

    private var linkButton: some View {
        Button {
            let value = !linked
            linked = value
            onLinkChange(value)
        } label: {
            Image(systemName: "link")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(linked ? Color.green : Color.secondary)
                .frame(width: 26, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(linked ? Color.green.opacity(0.16) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(linked ? Color.green.opacity(0.9) : Color.primary.opacity(0.18), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(linked ? String(localized: "Unlink left and right") : String(localized: "Link left and right"))
    }
}

// MARK: - Стиль и типы полос

private enum RoomEQStyle {
    /// Полосы идут тройками, как в окне TotalMix: 1–3, 4–6, 7–9.
    static func color(for band: Int) -> Color {
        switch band {
        case 1...3: return EQPalette.low
        case 4...6: return EQPalette.mid
        default: return EQPalette.high
        }
    }
}

/// Наборы типов для полос Room EQ: у первой полосы низ, у восьмой и девятой верх.
nonisolated enum RoomEQFilterKinds {
    static func kinds(for band: Int) -> [EQTypeIcon.Kind] {
        switch band {
        case 1: return [.bell, .lowShelf, .highPass, .lowPass]
        case 9: return [.bell, .highShelf, .lowPass, .highPass]
        default: return [.bell, .highShelf, .lowPass, .highPass]
        }
    }
}

/// Суммарная АЧХ девяти полос — для кривой на графике.
enum RoomEQResponse {
    static let sampleRate = 48000.0

    static func totalDb(state: RoomEQState, at frequency: Double) -> Double {
        (1...RoomEQState.bandCount).reduce(0) { partial, number in
            partial + db(band: state.band(number), bandNumber: number, at: frequency)
        }
    }

    static func db(band: RoomEQBand, bandNumber: Int, at frequency: Double) -> Double {
        let kinds = RoomEQFilterKinds.kinds(for: bandNumber)
        let index = min(max(band.type, 0), kinds.count - 1)
        let coefficient = coefficients(kind: kinds[index], frequency: band.frequency,
                                       gain: band.gain, q: band.q)
        return 20 * log10(max(magnitude(coefficient, at: frequency), 1e-6))
    }

    /// Коэффициенты всех полос, посчитанные заранее. Каждая полоса — шесть
    /// чисел; дальше остаётся только арифметика на точку кривой.
    struct Prepared {
        private let coefficients: [[Double]]

        init(state: RoomEQState) {
            coefficients = (1...RoomEQState.bandCount).map { number in
                let band = state.band(number)
                let kinds = RoomEQFilterKinds.kinds(for: number)
                let index = min(max(band.type, 0), kinds.count - 1)
                return RoomEQResponse.coefficients(kind: kinds[index],
                                                   frequency: band.frequency,
                                                   gain: band.gain,
                                                   q: band.q)
            }
        }

        func db(at frequency: Double) -> Double {
            let w = 2 * Double.pi * frequency / RoomEQResponse.sampleRate
            let cosW = cos(w), sinW = sin(w)
            let cos2W = cos(2 * w), sin2W = sin(2 * w)
            var sum = 0.0
            for c in coefficients {
                sum += RoomEQResponse.db(c, cosW: cosW, sinW: sinW, cos2W: cos2W, sin2W: sin2W)
            }
            return sum
        }

        func bandDb(_ number: Int, at frequency: Double) -> Double {
            guard coefficients.indices.contains(number - 1) else { return 0 }
            let w = 2 * Double.pi * frequency / RoomEQResponse.sampleRate
            return RoomEQResponse.db(coefficients[number - 1],
                                     cosW: cos(w), sinW: sin(w),
                                     cos2W: cos(2 * w), sin2W: sin(2 * w))
        }
    }

    /// Отклик одной полосы по готовым коэффициентам и общим sin/cos.
    static func db(_ c: [Double], cosW: Double, sinW: Double,
                   cos2W: Double, sin2W: Double) -> Double {
        let nr = c[0] + c[1] * cosW + c[2] * cos2W
        let ni = -(c[1] * sinW + c[2] * sin2W)
        let dr = c[3] + c[4] * cosW + c[5] * cos2W
        let di = -(c[4] * sinW + c[5] * sin2W)
        let d = dr * dr + di * di
        let magnitude = d < 1e-12 ? 1 : sqrt((nr * nr + ni * ni) / d)
        return 20 * log10(max(magnitude, 1e-6))
    }

    static func coefficients(kind: EQTypeIcon.Kind, frequency: Double,
                                     gain: Double, q: Double) -> [Double] {
        let w = 2 * Double.pi * min(max(frequency, 10), sampleRate / 2 - 10) / sampleRate
        let cosW = cos(w), sinW = sin(w)
        let a = pow(10, gain / 40)
        let alpha = sinW / (2 * max(q, 0.05))
        switch kind {
        case .bell:
            return [1 + alpha * a, -2 * cosW, 1 - alpha * a,
                    1 + alpha / a, -2 * cosW, 1 - alpha / a]
        case .lowShelf:
            let sqrtA = sqrt(a), two = 2 * sqrtA * alpha
            return [a * ((a + 1) - (a - 1) * cosW + two), 2 * a * ((a - 1) - (a + 1) * cosW),
                    a * ((a + 1) - (a - 1) * cosW - two), (a + 1) + (a - 1) * cosW + two,
                    -2 * ((a - 1) + (a + 1) * cosW), (a + 1) + (a - 1) * cosW - two]
        case .highShelf:
            let sqrtA = sqrt(a), two = 2 * sqrtA * alpha
            return [a * ((a + 1) + (a - 1) * cosW + two), -2 * a * ((a - 1) + (a + 1) * cosW),
                    a * ((a + 1) + (a - 1) * cosW - two), (a + 1) - (a - 1) * cosW + two,
                    2 * ((a - 1) - (a + 1) * cosW), (a + 1) - (a - 1) * cosW - two]
        case .highPass:
            return [(1 + cosW) / 2, -(1 + cosW), (1 + cosW) / 2, 1 + alpha, -2 * cosW, 1 - alpha]
        case .lowPass:
            return [(1 - cosW) / 2, 1 - cosW, (1 - cosW) / 2, 1 + alpha, -2 * cosW, 1 - alpha]
        }
    }

    private static func magnitude(_ c: [Double], at frequency: Double) -> Double {
        let w = 2 * Double.pi * frequency / sampleRate
        let cosW = cos(w), sinW = sin(w), cos2W = cos(2 * w), sin2W = sin(2 * w)
        let nr = c[0] + c[1] * cosW + c[2] * cos2W
        let ni = -(c[1] * sinW + c[2] * sin2W)
        let dr = c[3] + c[4] * cosW + c[5] * cos2W
        let di = -(c[4] * sinW + c[5] * sin2W)
        let d = dr * dr + di * di
        return d < 1e-12 ? 1 : sqrt((nr * nr + ni * ni) / d)
    }
}


/// Выпадающий список типа полосы с иконками кривых: в закрытом виде — сама
/// кривая, в списке — кривая и название.
private struct BandTypeMenu: View {
    let kinds: [EQTypeIcon.Kind]
    let selected: Int
    let names: [String]
    let color: Color
    let onSelect: (Int) -> Void

    @State private var showing = false

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            EQTypeIcon(kind: kinds[selected])
                .stroke(color, lineWidth: 1.2)
                .frame(width: 22, height: 12)
                .frame(width: 40, height: 18)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.06)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(kinds.enumerated()), id: \.offset) { index, kind in
                    Button {
                        onSelect(index)
                        showing = false
                    } label: {
                        HStack(spacing: 8) {
                            EQTypeIcon(kind: kind)
                                .stroke(color, lineWidth: 1.3)
                                .frame(width: 22, height: 12)
                            Text(names[index])
                                .font(.caption)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            // Список обнимает содержимое: лишняя ширина справа только тянет руку.
            .padding(6)
            .fixedSize()
        }
    }
}
