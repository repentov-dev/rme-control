import AppKit
import SwiftUI

struct CompressorView: View {
    static let contentSize = NSSize(width: 380, height: 280)

    let viewModel: MixerViewModel
    let target: CompressorTarget
    var onClose: @MainActor () -> Void

    @State private var headerHovered = false

    var body: some View {
        let compressor = viewModel.compressor(target)
        let label = viewModel.eqLabel(EQTarget(bus: target.bus, id: target.id))
        let input = viewModel.compressorInputLevel(target)
        let reduction = viewModel.compressorGainReduction(target)
        let output = viewModel.compressorOutputLevel(target)

        VStack(spacing: 8) {
            header(compressor: compressor, label: label)

            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 8) {
                    CompressorCurve(state: compressor, level: input)
                        .frame(height: 140)

                    HStack(spacing: 1) {
                        ForEach(CompressorParameter.allCases) { parameter in
                            CompressorKnob(
                                parameter: parameter,
                                value: compressor.value(for: parameter)
                            ) { newValue in
                                viewModel.setCompressorParameter(target, parameter, newValue)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                CompressorMeterRail(
                    level: input,
                    reduction: reduction,
                    output: output
                )
                .frame(width: 70)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 12, trailing: 12))
        .frame(width: Self.contentSize.width, height: Self.contentSize.height)
        .popoverSurface(cornerRadius: 12)
    }

    private func header(compressor: CompressorState, label: String) -> some View {
        HStack(spacing: 10) {
            PanelCloseButton(showGlyph: headerHovered, action: onClose)

            WindowDragHandle()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            CompressorPresetPicker(
                viewModel: viewModel,
                target: target,
                compressor: compressor
            )

            Text(label)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .overlay(WindowDragHandle())

            Toggle(
                "Compressor",
                isOn: Binding(
                    get: { compressor.enabled },
                    set: { viewModel.setCompressorEnabled(target, $0) }
                )
            )
            .toggleStyle(.switch)
            .tint(.accentColor)
            .controlSize(.small)
            .labelsHidden()
            .help(compressor.enabled ? "Bypass" : "Enable")
        }
        .frame(height: 28)
        .onHover { headerHovered = $0 }
    }
}

private struct CompressorCurve: View {
    let state: CompressorState
    let level: Double

    var body: some View {
        Canvas { context, size in
            let pad: CGFloat = 7
            let width = max(size.width - pad * 2, 1)
            let height = max(size.height - pad * 2, 1)
            let threshold = state.threshold
            let ratio = max(state.ratio, 1)
            let gain = state.gain

            func dbToX(_ db: Double) -> CGFloat {
                pad + CGFloat((db + 60) / 60) * width
            }

            func dbToY(_ db: Double) -> CGFloat {
                let clamped = min(max(db, -60), 0)
                return pad + height - CGFloat((clamped + 60) / 60) * height
            }

            func compressed(_ db: Double) -> Double {
                if state.enabled, ratio > 1, db > threshold {
                    return threshold + (db - threshold) / ratio + gain
                }
                return db + gain
            }

            let gridColor = Color.primary.opacity(PanelOpacity.grid)
            for db in [-40.0, -20.0] {
                var vertical = Path()
                vertical.move(to: CGPoint(x: dbToX(db), y: pad))
                vertical.addLine(to: CGPoint(x: dbToX(db), y: size.height - pad))
                context.stroke(vertical, with: .color(gridColor), lineWidth: 1)

                var horizontal = Path()
                horizontal.move(to: CGPoint(x: pad, y: dbToY(db)))
                horizontal.addLine(to: CGPoint(x: size.width - pad, y: dbToY(db)))
                context.stroke(horizontal, with: .color(gridColor), lineWidth: 1)
            }

            var thresholdLine = Path()
            thresholdLine.move(to: CGPoint(x: dbToX(threshold), y: pad))
            thresholdLine.addLine(to: CGPoint(x: dbToX(threshold), y: size.height - pad))
            context.stroke(
                thresholdLine,
                with: .color(Color(nsColor: .systemOrange).opacity(PanelOpacity.outline)),
                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
            )

            var identity = Path()
            for index in 0...60 {
                let db = Double(index) - 60
                let point = CGPoint(x: dbToX(db), y: dbToY(db + gain))
                if index == 0 {
                    identity.move(to: point)
                } else {
                    identity.addLine(to: point)
                }
            }
            context.stroke(
                identity,
                with: .color(Color.primary.opacity(PanelOpacity.control)),
                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
            )

            if state.enabled, ratio > 1, threshold < 0 {
                var area = Path()
                let steps = max(Int(0 - threshold), 1)
                for index in 0...steps {
                    let db = threshold + (0 - threshold) * Double(index) / Double(steps)
                    let point = CGPoint(x: dbToX(db), y: dbToY(compressed(db)))
                    if index == 0 {
                        area.move(to: point)
                    } else {
                        area.addLine(to: point)
                    }
                }
                for index in stride(from: steps, through: 0, by: -1) {
                    let db = threshold + (0 - threshold) * Double(index) / Double(steps)
                    area.addLine(to: CGPoint(x: dbToX(db), y: dbToY(db + gain)))
                }
                area.closeSubpath()
                context.fill(area, with: .color(Color(nsColor: .systemIndigo).opacity(PanelOpacity.card)))
            }

            var curve = Path()
            for index in 0...120 {
                let db = Double(index) - 60
                let point = CGPoint(x: dbToX(db), y: dbToY(compressed(db)))
                if index == 0 {
                    curve.move(to: point)
                } else {
                    curve.addLine(to: point)
                }
            }
            context.stroke(
                curve,
                with: .color(Color(nsColor: .systemCyan)),
                style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
            )

            if level > -99.9 {
                let input = min(max(level, -60), 0)
                let dot = CGRect(
                    x: dbToX(input) - 2.6,
                    y: dbToY(compressed(input)) - 2.6,
                    width: 5.2,
                    height: 5.2
                )
                context.fill(Path(ellipseIn: dot), with: .color(.white))
            }
        }
        .background(Color.primary.opacity(PanelOpacity.card))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

private struct CompressorKnob: View {
    let parameter: CompressorParameter
    let value: Double
    let onChange: (Double) -> Void

    @State private var startValue: Double?
    @State private var lastClick: Date?

    private var progress: Double {
        let range = parameter.range
        return min(max((value - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
    }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Color.primary.opacity(PanelOpacity.control), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .padding(4)

                Circle()
                    .trim(from: 0, to: 0.75 * progress)
                    .stroke(
                        parameter.knobColor,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
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
                        Circle()
                            .strokeBorder(Color.primary.opacity(PanelOpacity.card), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.16), radius: 1.5, x: 0, y: 1)
                    .padding(9)

                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let angle = Angle.degrees(135 + 270 * progress).radians
                    let inner = CGPoint(
                        x: center.x + 4 * cos(angle),
                        y: center.y + 4 * sin(angle)
                    )
                    let outer = CGPoint(
                        x: center.x + 11 * cos(angle),
                        y: center.y + 11 * sin(angle)
                    )
                    var pointer = Path()
                    pointer.move(to: inner)
                    pointer.addLine(to: outer)
                    context.stroke(
                        pointer,
                        with: .color(parameter.knobColor),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                }
            }
            .frame(width: 48, height: 48)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if startValue == nil {
                            startValue = value
                        }
                        guard let startValue else { return }
                        let span = parameter.range.upperBound - parameter.range.lowerBound
                        let raw = startValue - Double(gesture.translation.height) / 150 * span
                        onChange(rounded(raw))
                    }
                    .onEnded { gesture in
                        if abs(gesture.translation.height) < 2, abs(gesture.translation.width) < 2 {
                            let now = Date()
                            if let lastClick, now.timeIntervalSince(lastClick) < 0.35 {
                                onChange(parameter.neutral)
                                self.lastClick = nil
                            } else {
                                lastClick = now
                            }
                        }
                        startValue = nil
                    }
            )

            Text(parameter.formatted(value))
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(parameter.shortTitle)
                .font(.system(size: 7.5, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .help(parameter.title)
    }

    private func rounded(_ value: Double) -> Double {
        let range = parameter.range
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        switch parameter {
        case .attack, .release:
            return clamped.rounded()
        default:
            return (clamped * 10).rounded() / 10
        }
    }
}

private struct CompressorMeterRail: View {
    let level: Double
    let reduction: Double
    let output: Double

    var body: some View {
        HStack(spacing: 0) {
            meter(
                label: "IN",
                value: level,
                fraction: Double((level + 60) / 60),
                color: meterColor(level),
                fromTop: false
            )
            meter(
                label: "GR",
                value: -reduction,
                fraction: reduction / 30,
                color: Color(nsColor: .systemIndigo),
                fromTop: true
            )
            meter(
                label: "OUT",
                value: output,
                fraction: Double((output + 60) / 60),
                color: meterColor(output),
                fromTop: false
            )
        }
        .frame(maxHeight: .infinity)
    }

    private func meter(
        label: String,
        value: Double,
        fraction: Double,
        color: Color,
        fromTop: Bool
    ) -> some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.system(size: 7.5, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(.secondary)

            GeometryReader { proxy in
                ZStack(alignment: fromTop ? .top : .bottom) {
                    Capsule()
                        .fill(Color.primary.opacity(PanelOpacity.control))
                    Capsule()
                        .fill(color)
                        .frame(height: max(0, proxy.size.height * min(max(fraction, 0), 1)))
                        .animation(.linear(duration: 0.2), value: fraction)
                }
            }
            .frame(width: 8)

            Text(formatDB(value))
                .font(.system(size: 7, weight: .heavy, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 2)
        .padding(.bottom, 4)
    }

    private func meterColor(_ value: Double) -> Color {
        if value > -6 { return Color(nsColor: .systemRed) }
        if value > -18 { return Color(nsColor: .systemYellow) }
        return Color(nsColor: .systemGreen)
    }

    private func formatDB(_ value: Double) -> String {
        if value <= -99.9 { return "-\u{221E}" }
        return String(format: "%.1f", value)
    }
}

private struct CompressorPresetPicker: View {
    let viewModel: MixerViewModel
    let target: CompressorTarget
    let compressor: CompressorState

    private var groups: [CompressorPresetGroup] {
        CompressorPresets.groups.filter { !$0.outputsOnly || target.bus == .output }
    }

    private var activePreset: CompressorPreset? {
        for group in groups {
            for preset in group.presets where preset.matches(compressor) {
                return preset
            }
        }
        return nil
    }

    private var selection: Binding<String> {
        Binding(
            get: { activePreset?.id ?? "custom" },
            set: { id in
                guard id != "custom",
                      let preset = groups.flatMap(\.presets).first(where: { $0.id == id }) else {
                    return
                }
                apply(preset)
            }
        )
    }

    var body: some View {
        Picker("Preset", selection: selection) {
            Text("Custom").tag("custom")
            ForEach(groups) { group in
                Section(group.name) {
                    ForEach(group.presets) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                }
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .help("Preset")
    }

    private func apply(_ preset: CompressorPreset) {
        viewModel.setCompressorParameter(target, .threshold, preset.threshold)
        viewModel.setCompressorParameter(target, .ratio, preset.ratio)
        viewModel.setCompressorParameter(target, .attack, preset.attack)
        viewModel.setCompressorParameter(target, .release, preset.release)
        viewModel.setCompressorParameter(target, .gain, preset.gain)
        if !compressor.enabled {
            viewModel.setCompressorEnabled(target, true)
        }
    }
}

private struct CompressorPresetGroup: Identifiable, Sendable {
    let name: String
    let presets: [CompressorPreset]
    var outputsOnly = false

    var id: String { name }
}

private struct CompressorPreset: Identifiable, Sendable {
    let id: String
    let name: String
    let threshold: Double
    let ratio: Double
    let attack: Double
    let release: Double
    let gain: Double

    func matches(_ state: CompressorState) -> Bool {
        abs(state.threshold - threshold) < 0.001
            && abs(state.ratio - ratio) < 0.001
            && abs(state.attack - attack) < 0.001
            && abs(state.release - release) < 0.001
            && abs(state.gain - gain) < 0.001
    }
}

private enum CompressorPresets {
    static let groups: [CompressorPresetGroup] = [
        CompressorPresetGroup(name: "Vocals", presets: [
            CompressorPreset(id: "clean", name: "Clean", threshold: -18, ratio: 2.5, attack: 15, release: 150, gain: 2),
            CompressorPreset(id: "male", name: "Male", threshold: -20, ratio: 3.5, attack: 10, release: 180, gain: 3),
            CompressorPreset(id: "female", name: "Female", threshold: -22, ratio: 3, attack: 8, release: 140, gain: 2.5),
            CompressorPreset(id: "rap", name: "Rap", threshold: -24, ratio: 5, attack: 5, release: 120, gain: 4),
            CompressorPreset(id: "speech", name: "Speech", threshold: -20, ratio: 4, attack: 6, release: 200, gain: 3),
            CompressorPreset(id: "soft", name: "Soft", threshold: -16, ratio: 2, attack: 25, release: 260, gain: 1.5),
            CompressorPreset(id: "loud", name: "Loud", threshold: -26, ratio: 7, attack: 3, release: 100, gain: 2)
        ]),
        CompressorPresetGroup(name: "Guitar", presets: [
            CompressorPreset(id: "guitar-electric", name: "Electric", threshold: -22, ratio: 4, attack: 8, release: 120, gain: 3),
            CompressorPreset(id: "guitar-acoustic", name: "Acoustic", threshold: -20, ratio: 2.5, attack: 20, release: 200, gain: 2)
        ]),
        CompressorPresetGroup(name: "Bass", presets: [
            CompressorPreset(id: "bass", name: "Bass Guitar", threshold: -24, ratio: 4, attack: 20, release: 250, gain: 4)
        ]),
        CompressorPresetGroup(name: "Keys", presets: [
            CompressorPreset(id: "keys-piano", name: "Piano", threshold: -20, ratio: 3, attack: 15, release: 250, gain: 2),
            CompressorPreset(id: "keys-synth", name: "Synth", threshold: -26, ratio: 4, attack: 5, release: 150, gain: 3)
        ]),
        CompressorPresetGroup(name: "Drums", presets: [
            CompressorPreset(id: "drums", name: "Drums", threshold: -18, ratio: 5, attack: 15, release: 100, gain: 3)
        ]),
        CompressorPresetGroup(name: "Film", presets: [
            CompressorPreset(id: "cinema", name: "Cinema", threshold: -18, ratio: 4, attack: 5, release: 300, gain: 3)
        ], outputsOnly: true)
    ]
}

private extension CompressorParameter {
    var shortTitle: String {
        switch self {
        case .threshold: return "THRESH"
        case .ratio: return "RATIO"
        case .attack: return "ATTACK"
        case .release: return "RELEASE"
        case .gain: return "GAIN"
        }
    }

    var knobColor: Color {
        switch self {
        case .threshold: return Color(nsColor: .systemOrange)
        case .ratio: return Color(nsColor: .systemPink)
        case .attack: return Color(nsColor: .systemCyan)
        case .release: return Color(nsColor: .systemPurple)
        case .gain: return Color(nsColor: .systemGreen)
        }
    }
}
