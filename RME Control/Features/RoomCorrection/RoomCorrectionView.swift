import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Мастер замера АЧХ, выравнивания и коррекции Room EQ.
struct RoomCorrectionView: View {
    static let contentSize = NSSize(width: 660, height: 700)

    @State private var model: RoomCorrectionViewModel
    @State private var headerHovered = false
    @State private var showingSavePreset = false
    @State private var presetName = ""
    @State private var showBands = false
    @State private var hostWindow: NSWindow?
    @State private var contentHeight: CGFloat = 0

    var onClose: @MainActor () -> Void

    init(mixer: MixerViewModel, target: RoomEQTarget, onClose: @escaping @MainActor () -> Void) {
        _model = State(initialValue: RoomCorrectionViewModel(mixer: mixer, target: target))
        self.onClose = onClose
    }

    init(model: RoomCorrectionViewModel, onClose: @escaping @MainActor () -> Void) {
        _model = State(initialValue: model)
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            steps
            Divider().opacity(0.55)
            content
                .padding(18)
            if let error = model.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color(nsColor: .systemRed))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .systemRed).opacity(0.07))
            }
            footer
        }
        .frame(width: Self.contentSize.width)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: RoomCorrectionHeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(RoomCorrectionHeightKey.self) { height in
            contentHeight = height
            resizeWindow()
        }
        .background(WindowAccessor { window in
            guard hostWindow !== window else { return }
            hostWindow = window
            resizeWindow()
        })
        .panelSurface(cornerRadius: 12)
        .onDisappear { model.cancel() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            guard let window = note.object as? NSWindow, window === hostWindow else { return }
            model.cancel()
        }
        .task { await model.requestMicrophoneAccess() }
        .task { await model.startCalibrationSession() }
        .sheet(isPresented: $showingSavePreset) {
            SavePresetSheet(name: $presetName) {
                model.presetName = presetName
                model.savePreset()
                showingSavePreset = false
            } onCancel: {
                showingSavePreset = false
            }
        }
    }

    private func close() {
        model.cancel()
        onClose()
    }

    private func resizeWindow() {
        guard let window = hostWindow, contentHeight > 0 else { return }
        let targetSize = NSSize(width: Self.contentSize.width, height: contentHeight)
        guard abs(window.contentView?.frame.height ?? 0 - targetSize.height) > 0.5 else { return }
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

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            PanelCloseButton(showGlyph: headerHovered, action: close)
            WindowDragHandle()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .leading) {
                    HStack(spacing: 8) {
                        Text("Measure")
                            .font(.headline)
                        Text(model.target.label)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            if model.stage != .setup {
                Button("Start over") { model.rescan() }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 34)
        .padding(.horizontal, 16)
        .padding(.top, 9)
        .onHover { headerHovered = $0 }
    }

    // MARK: - Steps

    private var steps: some View {
        HStack(spacing: 8) {
            WizardStep(number: 1, title: "Setup", state: setupStepState)
            connector(filled: model.stage != .setup)
            WizardStep(number: 2, title: "Measure", state: measureStepState)
            connector(filled: model.stage == .computing || model.stage == .results)
            WizardStep(number: 3, title: "Result", state: resultStepState)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
    }

    private var setupStepState: WizardStep.State {
        model.stage == .setup ? .active : .done
    }

    private var measureStepState: WizardStep.State {
        switch model.stage {
        case .setup: return .upcoming
        case .position, .measuring: return .active
        case .computing, .results: return .done
        }
    }

    private var resultStepState: WizardStep.State {
        switch model.stage {
        case .computing, .results: return .active
        default: return .upcoming
        }
    }

    private func connector(filled: Bool) -> some View {
        Rectangle()
            .fill(filled ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.10))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch model.stage {
        case .setup:
            setup
        case .position, .measuring:
            measure
        case .computing:
            computing
        case .results:
            results
        }
    }

    // MARK: - Setup

    private var setup: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Text("Measure your room")
                    .font(.title2.weight(.semibold))
                Spacer(minLength: 8)
                Button("Open result…") { openCalibrationResult() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            HStack(alignment: .top, spacing: 12) {
                outputCard
                microphoneCard
            }

            Label("Beta: the calibrator has been tested only on the Fireface 802 FS. It may work incorrectly with other interfaces.",
                  systemImage: "info.circle")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let rate = model.selectedDevice?.sampleRate, rate > 0, abs(rate - 48_000) > 1 {
                Label("Set the interface to 48 kHz before measuring. The measurement engine runs at 48 kHz.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.usesOSCRouting {
                Label("Only the selected output is active while Measure is open. All other outputs are muted and will be restored when the measurement finishes or you close Measure.",
                      systemImage: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label("Sound goes to software playback \(model.playbackPairTitle). Make sure TotalMix routes it to the selected output.",
                      systemImage: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            levelCard
        }
    }

    private var outputCard: some View {
        @Bindable var model = model
        return WizardCard(icon: "hifispeaker.2", title: "Output") {
            WizardField("RME interface") {
                if model.devices.isEmpty {
                    Text("No RME device found. Connect the interface and reopen Measure.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Picker("", selection: Binding(
                        get: { model.selectedDeviceID },
                        set: { model.selectDevice($0) }
                    )) {
                        ForEach(model.devices) { device in
                            Text(device.name).tag(Optional(device.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            WizardField("Output") {
                if model.outputs.isEmpty {
                    Text("No outputs in RME Control. Add one in Settings → Channels.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Picker("", selection: Binding(
                        get: { model.selectedOutputID },
                        set: { model.selectOutput($0) }
                    )) {
                        ForEach(model.outputs) { output in
                            Text(output.name.isEmpty ? output.oscAddress : output.name)
                                .tag(Optional(output.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Divider().opacity(0.5)

            HStack(spacing: 8) {
                Text("Test")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Left") { model.playTest(left: true) }
                    .controlSize(.small)
                Button("Right") { model.playTest(left: false) }
                    .controlSize(.small)
            }
            .disabled(!model.hasValidOutput || model.isTestingOutput)
        }
    }

    private var microphoneCard: some View {
        @Bindable var model = model
        return WizardCard(icon: "mic", title: "Microphone") {
            WizardField("Microphone") {
                if model.inputs.isEmpty {
                    Text("No microphones in RME Control. Add one in Settings → Channels.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Picker("", selection: Binding(
                        get: { model.selectedInputID },
                        set: { model.selectInput($0) }
                    )) {
                        ForEach(model.inputs) { input in
                            Text(input.name.isEmpty ? input.oscAddress : input.name)
                                .tag(Optional(input.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let title = model.selectedInputChannelTitle {
                        Text(String(format: String(localized: "Card input: %@"), title))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("This microphone is not present on the selected interface.")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Divider().opacity(0.5)

            HStack(spacing: 9) {
                Image(systemName: model.calibration == nil ? "doc.badge.plus" : "checkmark.seal.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(model.calibration == nil ? Color.secondary : Color.green)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.primary.opacity(0.06)))

                VStack(alignment: .leading, spacing: 1) {
                    Text("Mic calibration")
                        .font(.callout)
                    Text(model.calibration?.name ?? String(localized: "Not loaded"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 6)

                Button(model.calibration == nil ? "Choose…" : "Change…") {
                    chooseCalibration()
                }
                .controlSize(.small)

                if model.calibration != nil {
                    Button("Clear") { model.clearCalibration() }
                        .controlSize(.small)
                }
            }

        }
    }

    private var levelCard: some View {
        WizardCard(icon: "waveform", title: "Level test") {
            HStack(spacing: 10) {
                LevelMeter(level: model.levelTestDB ?? -100)
                    .frame(height: 24)

                if let level = model.levelTestDB {
                    Text(String(format: "%.1f dBFS", level))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(levelColor)
                        .lineLimit(1)
                }

                Button(model.isLevelTestRunning ? "Stop" : "Start") {
                    model.toggleLevelTest()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!model.hasValidChannels)
            }

            HStack {
                Text("Target −30…−10 dBFS, aim around −18 dBFS. Peaks should stay below −6.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if model.isLevelTestRunning {
                    HStack(spacing: 4) {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                        Text("Live")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
            }
        }
    }

    private var levelColor: Color {
        guard let level = model.levelTestDB else { return .secondary }
        if level > -10 { return .orange }
        if level < -30 { return .secondary }
        return .green
    }

    // MARK: - Measure

    private var measure: some View {
        Group {
            if let countdown = model.countdown {
                countdownView(countdown)
            } else {
                measureContent
            }
        }
    }

    private func countdownView(_ countdown: Int) -> some View {
        VStack(spacing: 12) {
            Text("Measurement starts in")
                .font(.headline)
            Text("\(countdown)")
                .font(.system(size: 76, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.accentColor)
            Text("Move away from the microphone.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Left and Right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 390)
    }

    private var measureContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Color.accentColor.opacity(0.8))
                .padding(.top, 16)

            VStack(spacing: 6) {
                Text(model.stage.isMeasuring ? String(localized: "Measuring") : String(localized: "Ready to measure"))
                    .font(.title3.weight(.semibold))
                Text("Both L and R are measured with 4 sweeps each. Keep the microphone at the same height and orientation.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if case .measuring = model.stage, let progress = model.progress {
                VStack(spacing: 5) {
                    ProgressView(value: progress.fraction)
                        .progressViewStyle(.linear)
                    HStack {
                        Text(progress.label)
                        Spacer()
                        Text("\(Int(progress.fraction * 100))%")
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 320)
            } else {
                Text("4 sweeps per channel")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 390)
    }

    // MARK: - Computing

    private var computing: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("Calculating corrections")
                .font(.headline)
            Text("Left, Right and Stereo are calculated at once. This usually takes a few seconds.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 390)
    }

    // MARK: - Results

    private var results: some View {
        @Bindable var model = model
        return VStack(spacing: 14) {
            WizardCard(icon: "chart.xyaxis.line", title: "Frequency response") {
                HStack(spacing: 8) {
                    channelPill
                    Spacer()
                    smoothingPicker
                }

                HStack(spacing: 8) {
                    Text("Target tilt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $model.targetTilt, in: -1...0, step: 0.1) { editing in
                        if !editing { model.recompute() }
                    }
                    .frame(maxWidth: 200)
                    Text(String(format: "%.1f dB/oct", model.targetTilt))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 72, alignment: .leading)
                    Spacer()
                    if model.isRecalculating {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .disabled(model.isRecalculating)

                if let correction = model.selectedCorrection {
                    CorrectionGraph(measured: correction.measured,
                                    predicted: correction.predicted,
                                    targetTilt: model.targetTilt,
                                    smoothing: model.smoothing)
                        .frame(height: 210)

                    HStack(spacing: 14) {
                        legendDot(Color.primary.opacity(0.4), String(localized: "Measured"))
                        legendDot(Color.accentColor, String(localized: "Corrected"))
                        legendDot(.pink, String(localized: "Target tilt"))
                        Spacer()
                        Text("roomeq correction")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        StatTile(value: String(format: "%.2f dB", correction.residualRMS),
                                 label: "Residual")
                        StatTile(value: String(format: "%+.1f dB", correction.preamp),
                                 label: "Gain")
                        StatTile(value: "9", label: "Bands")
                    }

                    if !correction.engineAccepted {
                        Label("roomeq: unchanged — correction is below its acceptance threshold.",
                              systemImage: "exclamationmark.triangle")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }

            if let correction = model.selectedCorrection {
                levelCard(correction)

                WizardCard(icon: "slider.horizontal.3", title: "Correction bands") {
                    DisclosureGroup(isExpanded: $showBands) {
                        BandGrid(bands: correction.bands)
                            .padding(.top, 8)
                    } label: {
                        Text(showBands ? String(localized: "Hide bands") : String(localized: "Show nine bands"))
                            .font(.callout)
                    }
                }
            }
        }
    }

    private var channelPill: some View {
        HStack(spacing: 3) {
            channelButton(.left, color: .orange)
            channelButton(.stereo, color: .accentColor)
            channelButton(.right, color: .blue)
        }
        .padding(3)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }

    private func channelButton(_ channel: RoomCorrectionChannel, color: Color) -> some View {
        let selected = model.selectedChannel == channel
        return Button {
            model.selectedChannel = channel
        } label: {
            Text(channel.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(selected ? color : Color.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(selected ? color.opacity(0.16) : Color.clear))
        }
        .buttonStyle(.plain)
    }

    private var smoothingPicker: some View {
        @Bindable var model = model
        return HStack(spacing: 6) {
            Text("Smoothing")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("", selection: $model.smoothing) {
                Text("1/6").tag(1.0 / 6.0)
                Text("1/3").tag(1.0 / 3.0)
                Text("1/2").tag(0.5)
                Text("1").tag(1.0)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 210)
        }
    }

    private func legendDot(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func levelCard(_ correction: RoomCorrection) -> some View {
        let common = min(correction.preamp,
                         model.corrections[.left]?.preamp ?? correction.preamp,
                         model.corrections[.right]?.preamp ?? correction.preamp)
        return WizardCard(icon: "speaker.wave.2", title: "Volume calibration",
                          subtitle: "One common value for both channels — headroom for the EQ. Delay is not touched; set it manually in Room EQ.") {
            HStack(spacing: 8) {
                StatTile(value: String(format: "%+.1f dB", common), label: "Both channels")
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.55)
            HStack(spacing: 10) {
                Text(footerStatus)
                    .font(.caption)
                    .foregroundStyle(model.didApply ? Color.green : Color.secondary)
                    .lineLimit(1)
                Spacer(minLength: 12)
                footerButtons
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var footerStatus: String {
        switch model.stage {
        case .setup: return String(localized: "Your choices are remembered for next time.")
        case .results: return model.statusText
        default: return model.statusText
        }
    }

    @ViewBuilder
    private var footerButtons: some View {
        switch model.stage {
        case .setup:
            Button("Cancel", action: close)
                .buttonStyle(.borderless)
                .controlSize(.large)
            Button("Continue") { model.startMeasurement() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!model.hasValidChannels || model.isLevelTestRunning)

        case .position:
            Button("Cancel") { model.rescan() }
                .buttonStyle(.borderless)
                .controlSize(.large)
            Button("Measure") { model.measurePosition() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!model.canMeasure)

        case .measuring, .computing:
            Button("Cancel") { model.rescan() }
                .buttonStyle(.borderless)
                .controlSize(.large)
            Button(model.countdown != nil ? "Get ready…" : (model.stage.isMeasuring ? "Measuring…" : "Calculating…")) {}
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(true)

        case .results:
            Button("Save result…") { saveCalibrationResult() }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(model.selectedCorrection == nil || model.isRecalculating)
            Button("Save preset") {
                presetName = ""
                showingSavePreset = true
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(model.selectedCorrection == nil || model.isRecalculating)
            Button(model.didApply ? "Apply again" : "Apply to Room EQ") { model.apply() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.selectedCorrection == nil || model.isRecalculating)
        }
    }

    // MARK: - Helpers

    private func saveCalibrationResult() {
        guard let result = model.calibrationResult() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Room Calibration \(result.outputLabel).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(result).write(to: url, options: .atomic)
            model.status = String(format: String(localized: "Saved calibration result: %@"),
                                  url.lastPathComponent)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func openCalibrationResult() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.loadCalibrationResult(from: url)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func chooseCalibration() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText, .text]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.setCalibration(url: url)
    }
}

// MARK: - Components

private struct RoomCorrectionHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

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

private struct WizardStep: View {
    enum State { case upcoming, active, done }
    let number: Int
    let title: LocalizedStringKey
    let state: State

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(fill)
                if state == .done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(state == .active ? .white : Color.secondary)
                }
            }
            .frame(width: 20, height: 20)
            .overlay(Circle().strokeBorder(border, lineWidth: 1))

            Text(title)
                .font(.caption.weight(state == .active ? .semibold : .regular))
                .foregroundStyle(state == .upcoming ? Color.secondary : Color.primary)
        }
        .fixedSize()
    }

    private var fill: Color {
        switch state {
        case .done: return .green
        case .active: return .accentColor
        case .upcoming: return .clear
        }
    }

    private var border: Color {
        switch state {
        case .done: return .green
        case .active: return .accentColor
        case .upcoming: return Color.primary.opacity(0.16)
        }
    }
}

private struct WizardCard<Content: View>: View {
    let icon: String
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil
    let content: Content

    init(icon: String, title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil,
         @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.accentColor.opacity(0.12)))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.headline)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            content
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}

private struct WizardField<Content: View>: View {
    let label: LocalizedStringKey
    let content: Content

    init(_ label: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            content
        }
    }
}

private struct WizardStepperRow: View {
    let title: LocalizedStringKey
    @Binding var value: Int
    let upper: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.callout)
            Spacer()
            Stepper(value: $value, in: 0...max(upper, 0)) {
                Text("\(value)")
                    .font(.callout.monospacedDigit())
                    .frame(minWidth: 22, alignment: .trailing)
            }
            .controlSize(.small)
            .frame(width: 108)
        }
    }
}

private struct LevelMeter: View {
    let level: Double

    var body: some View {
        VStack(spacing: 3) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let x: (Double) -> CGFloat = { db in
                    CGFloat(min(max((db + 60) / 60, 0), 1)) * width
                }
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 8)

                    Capsule()
                        .fill(Color.green.opacity(0.16))
                        .frame(width: max(x(-10) - x(-30), 0), height: 8)
                        .offset(x: x(-30))

                    Rectangle()
                        .fill(Color.primary.opacity(0.28))
                        .frame(width: 1, height: 12)
                        .offset(x: x(-18))

                    Capsule()
                        .fill(color)
                        .frame(width: max(x(level), 2), height: 8)
                }
            }
            .frame(height: 12)

            HStack {
                Text("-60").frame(maxWidth: .infinity, alignment: .leading)
                Text("-30").frame(maxWidth: .infinity, alignment: .center)
                Text("-18").frame(maxWidth: .infinity, alignment: .center)
                Text("-10").frame(maxWidth: .infinity, alignment: .center)
                Text("0").frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.system(size: 7))
            .foregroundStyle(.secondary)
        }
    }

    private var color: Color {
        if level > -10 { return .orange }
        if level < -30 { return Color.secondary.opacity(0.5) }
        return .green
    }
}

private struct StatTile: View {
    let value: String
    let label: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Color.primary.opacity(0.04)))
    }
}

private struct BandGrid: View {
    let bands: [RoomCorrectionBand]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
            ForEach(Array(bands.enumerated()), id: \.offset) { index, band in
                BandCell(index: index + 1, band: band)
            }
        }
    }
}

private struct BandCell: View {
    let index: Int
    let band: RoomCorrectionBand

    private var type: (String, Color) {
        if index == 1 { return ("LS", .orange) }
        if index == 9 { return ("HS", .green) }
        return ("PK", .blue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(type.0)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(type.1)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(type.1.opacity(0.14)))
                Text(String(format: "%.0f Hz", band.frequency))
                    .font(.system(size: 8, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
            }
            Text(String(format: "%+.1f dB · Q %.1f", band.gain, band.q))
                .font(.system(size: 8).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.primary.opacity(0.035)))
    }
}

private struct SavePresetSheet: View {
    @Binding var name: String
    let onSave: () -> Void
    let onCancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save preset")
                .font(.headline)
            Text("The nine bands, delay and volume calibration will be saved together.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Preset name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onAppear { focused = true }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 350)
    }
}

/// График измеренной и предсказанной АЧХ.
private struct CorrectionGraph: View {
    let measured: [RoomResponsePoint]
    let predicted: [RoomResponsePoint]
    let targetTilt: Double
    let smoothing: Double

    var body: some View {
        Canvas { context, size in
            let pad: CGFloat = 18
            let width = max(size.width - pad * 2, 1)
            let height = max(size.height - pad * 2, 1)
            let minimumDB = -18.0
            let maximumDB = 12.0

            func x(_ frequency: Double) -> CGFloat {
                pad + CGFloat(log(frequency / 20) / log(1000)) * width
            }
            func y(_ db: Double) -> CGFloat {
                let clamped = min(max(db, minimumDB), maximumDB)
                return pad + height - CGFloat((clamped - minimumDB) / (maximumDB - minimumDB)) * height
            }

            for frequency in [20.0, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000] {
                var path = Path()
                path.move(to: CGPoint(x: x(frequency), y: pad))
                path.addLine(to: CGPoint(x: x(frequency), y: size.height - pad))
                context.stroke(path, with: .color(Color.primary.opacity(0.05)), lineWidth: 1)
            }
            for db in [-12.0, 0, 12] {
                var path = Path()
                path.move(to: CGPoint(x: pad, y: y(db)))
                path.addLine(to: CGPoint(x: size.width - pad, y: y(db)))
                context.stroke(path, with: .color(Color.primary.opacity(db == 0 ? 0.16 : 0.055)), lineWidth: 1)
            }

            let shownMeasured = smoothing > 1.0 / 6.0 + 0.001
                ? RoomMeasurementAnalyzer.smoothed(measured, octaves: smoothing)
                : measured
            let shownPredicted = smoothing > 1.0 / 6.0 + 0.001
                ? RoomMeasurementAnalyzer.smoothed(predicted, octaves: smoothing)
                : predicted

            func path(for points: [RoomResponsePoint]) -> Path {
                var path = Path()
                for (index, point) in points.enumerated() {
                    let target = CGPoint(x: x(point.frequency), y: y(point.db))
                    if index == 0 { path.move(to: target) } else { path.addLine(to: target) }
                }
                return path
            }

            // Целевой наклон — прямая в логарифмическом масштабе, 0 дБ на 1 кГц.
            let tilt = RoomCorrectionTarget(tiltDBPerOctave: targetTilt)
            var targetPath = Path()
            let tiltSamples = 64
            for index in 0...tiltSamples {
                let frequency = 20 * pow(1_000, Double(index) / Double(tiltSamples))
                let point = CGPoint(x: x(frequency), y: y(tilt.db(at: frequency)))
                if index == 0 { targetPath.move(to: point) } else { targetPath.addLine(to: point) }
            }
            context.stroke(targetPath,
                           with: .color(.pink.opacity(0.9)),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [5, 3]))

            context.stroke(path(for: shownMeasured),
                           with: .color(Color.primary.opacity(0.42)),
                           style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
            context.stroke(path(for: shownPredicted),
                           with: .color(Color.accentColor),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            for frequency in [20.0, 100, 1000, 10000] {
                let label = frequency >= 1000 ? "\(Int(frequency / 1000))k" : "\(Int(frequency))"
                context.draw(
                    Text(label).font(.system(size: 8)).foregroundStyle(.secondary),
                    at: CGPoint(x: x(frequency), y: size.height - 5)
                )
            }
        }
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private extension RoomCorrectionViewModel.Stage {
    var isMeasuring: Bool {
        if case .measuring = self { return true }
        return false
    }
}
