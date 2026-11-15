import AppKit
import SwiftUI

struct EqualizerView: View {
    static let contentSize = NSSize(width: 440, height: 330)

    let viewModel: MixerViewModel
    let target: EQTarget
    var onClose: @MainActor () -> Void

    @State private var headerHovered = false

    var body: some View {
        let eq = viewModel.eq(target)

        VStack(spacing: 8) {
            header(eq: eq, name: viewModel.eqLabel(target))
            EQGraph(viewModel: viewModel, target: target, state: eq)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        .frame(width: Self.contentSize.width, height: Self.contentSize.height)
        .panelSurface(cornerRadius: 12)
    }

    private func header(eq: EQState, name: String) -> some View {
        HStack(spacing: 10) {
            PanelCloseButton(showGlyph: headerHovered, action: onClose)

            WindowDragHandle()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text(name)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .overlay(WindowDragHandle())

            Toggle(
                "Equalizer",
                isOn: Binding(
                    get: { eq.enabled },
                    set: { viewModel.setEQEnabled(target, $0) }
                )
            )
            .toggleStyle(.switch)
            .tint(.accentColor)
            .controlSize(.small)
            .labelsHidden()
            .help(eq.enabled ? "Bypass" : "Enable")
        }
        .frame(height: 28)
        .onHover { headerHovered = $0 }
    }
}

private struct EQGraph: View {
    let viewModel: MixerViewModel
    let target: EQTarget
    let state: EQState

    @State private var active: EQNode?
    @State private var tip: EQTip?
    @State private var tipVisible = false
    @State private var dragMode: EQDragMode?
    @State private var dragStartY: CGFloat = 0
    @State private var dragStartQ: Double = 0
    @State private var wheelAccum = 0.0
    @State private var showTask: Task<Void, Never>?
    @State private var hideTask: Task<Void, Never>?
    @State private var clearTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            let geometry = EQGeometry(size: proxy.size)

            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    drawGraph(context: &context, geometry: EQGeometry(size: size))
                }

                EQInteractionLayer(
                    onHover: { point in hover(point, geometry: geometry) },
                    onPress: { point, option, clicks in
                        press(point, option: option, clicks: clicks, geometry: geometry)
                    },
                    onDrag: { point in dragged(point, geometry: geometry) },
                    onRelease: { point in released(point, geometry: geometry) },
                    onScroll: { point, delta in scrolled(point, delta: delta, geometry: geometry) }
                )

                if let tip {
                    tooltip(for: tip)
                        .offset(x: tip.left, y: tip.top + (tipVisible ? 0 : -3))
                        .opacity(tipVisible ? 1 : 0)
                        .allowsHitTesting(tipVisible)
                        .onHover { hovering in
                            if hovering {
                                cancelHide()
                            } else {
                                scheduleHide()
                            }
                        }
                        .animation(.easeOut(duration: 0.13), value: tipVisible)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.primary.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
    }

    private func drawGraph(context: inout GraphicsContext, geometry: EQGeometry) {
        for frequency in [20.0, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000] {
            var path = Path()
            let x = geometry.freqToX(frequency)
            path.move(to: CGPoint(x: x, y: EQGeometry.padTop))
            path.addLine(to: CGPoint(x: x, y: geometry.size.height - EQGeometry.padBottom))
            context.stroke(
                path,
                with: .color(Color.primary.opacity(frequency == 1000 ? 0.13 : 0.055)),
                lineWidth: 1
            )
        }

        for db in [-12.0, 0, 12] {
            var path = Path()
            let y = geometry.dbToY(db)
            path.move(to: CGPoint(x: EQGeometry.padLeft, y: y))
            path.addLine(to: CGPoint(x: geometry.size.width - EQGeometry.padRight, y: y))
            context.stroke(
                path,
                with: .color(Color.primary.opacity(db == 0 ? 0.16 : 0.055)),
                lineWidth: 1
            )
        }

        for frequency in [20.0, 100, 1000, 10000] {
            let label = frequency >= 1000 ? "\(Int(frequency / 1000))k" : "\(Int(frequency))"
            drawText(
                label,
                x: geometry.freqToX(frequency),
                baselineY: geometry.size.height - 4,
                size: 8,
                weight: .medium,
                color: .secondary,
                tracking: 0,
                context: &context
            )
        }

        let zeroY = geometry.dbToY(0)
        let mainPoints = (0...220).map { index -> CGPoint in
            let frequency = 20 * pow(1000, Double(index) / 220)
            let db = min(max(responseDb(at: frequency), -24), 24)
            return CGPoint(x: geometry.freqToX(frequency), y: geometry.dbToY(db))
        }

        if let first = mainPoints.first, let last = mainPoints.last {
            var fill = Path()
            fill.move(to: first)
            for point in mainPoints.dropFirst() {
                fill.addLine(to: point)
            }
            fill.addLine(to: CGPoint(x: last.x, y: zeroY))
            fill.addLine(to: CGPoint(x: first.x, y: zeroY))
            fill.closeSubpath()
            context.fill(
                fill,
                with: .linearGradient(
                    Gradient(colors: [Color.accentColor.opacity(0.20), Color.accentColor.opacity(0.015)]),
                    startPoint: CGPoint(x: 0, y: EQGeometry.padTop),
                    endPoint: CGPoint(x: 0, y: geometry.size.height - EQGeometry.padBottom)
                )
            )
        }

        if state.enabled {
            for band in 1...3 {
                var path = Path()
                for index in 0...160 {
                    let frequency = 20 * pow(1000, Double(index) / 160)
                    let magnitude = bandMagnitude(band: band, frequency: frequency)
                    let db = min(max(20 * log(max(magnitude, 1e-6)) / log(10), -24), 24)
                    let point = CGPoint(x: geometry.freqToX(frequency), y: geometry.dbToY(db))
                    if index == 0 {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                }
                context.stroke(path, with: .color(EQPalette.band(band).opacity(0.42)), lineWidth: 1)
            }
        }

        var curve = Path()
        if let first = mainPoints.first {
            curve.move(to: first)
            for point in mainPoints.dropFirst() {
                curve.addLine(to: point)
            }
        }
        context.stroke(
            curve,
            with: .color(Color.primary.opacity(state.enabled ? 0.9 : 0.35)),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        )

        if state.lowCutEnabled {
            var path = Path()
            let x = geometry.freqToX(state.lowCutFreq)
            path.move(to: CGPoint(x: x, y: EQGeometry.padTop))
            path.addLine(to: CGPoint(x: x, y: geometry.size.height - EQGeometry.padBottom))
            context.stroke(
                path,
                with: .color(EQPalette.cut.opacity(0.5)),
                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
            )
        }

        let lowCutLabel = lowCutLabelInfo(geometry: geometry)
        let labels = bandLabelLayouts(geometry: geometry, lowCutRect: lowCutLabel.rect)

        for layout in labels {
            for (index, line) in layout.lines.enumerated() {
                let baseline = layout.rect.minY + [9, 18, 27][index]
                drawText(
                    line,
                    x: layout.centerX,
                    baselineY: baseline,
                    size: 9,
                    weight: .semibold,
                    color: .secondary,
                    tracking: 0.1,
                    context: &context
                )
            }

            let band = layout.band
            let color = EQPalette.band(band)
            let center = CGPoint(
                x: geometry.freqToX(state.bandFrequency(band)),
                y: geometry.dbToY(state.bandGain(band))
            )

            if active == .band(band) {
                let ring = Path(ellipseIn: CGRect(x: center.x - 9, y: center.y - 9, width: 18, height: 18))
                context.fill(ring, with: .color(color.opacity(0.12)))
                context.stroke(ring, with: .color(color.opacity(0.65)), lineWidth: 1.4)
            }

            let node = Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10))
            context.fill(node, with: .color(color))
            context.stroke(node, with: .color(EQPalette.graphBackground), lineWidth: 1.6)
        }

        let cutX = geometry.freqToX(state.lowCutFreq)
        let cutY = geometry.size.height - EQGeometry.padBottom - 3

        if active == .lowCut {
            let ring = Path(ellipseIn: CGRect(x: cutX - 10, y: cutY - 10, width: 20, height: 20))
            context.fill(ring, with: .color(EQPalette.cut.opacity(0.12)))
            context.stroke(ring, with: .color(EQPalette.cut.opacity(0.65)), lineWidth: 1.4)
        }

        let cutNode = Path(ellipseIn: CGRect(x: cutX - 4, y: cutY - 4, width: 8, height: 8))
        context.fill(
            cutNode,
            with: .color(state.lowCutEnabled ? EQPalette.cut : Color.primary.opacity(0.18))
        )
        context.stroke(
            cutNode,
            with: .color(EQPalette.cut.opacity(state.lowCutEnabled ? 1 : 0.5)),
            lineWidth: 1.2
        )

        drawText(
            lowCutLabel.text,
            x: lowCutLabel.centerX,
            baselineY: lowCutLabel.baselineY,
            size: 9,
            weight: .semibold,
            color: .secondary,
            tracking: 0.1,
            context: &context
        )
    }

    private func drawText(
        _ string: String,
        x: CGFloat,
        baselineY: CGFloat,
        size: CGFloat,
        weight: Font.Weight,
        color: Color,
        tracking: CGFloat,
        context: inout GraphicsContext
    ) {
        let text = Text(string)
            .font(.system(size: size, weight: weight))
            .tracking(tracking)
            .foregroundColor(color)
        context.draw(text, at: CGPoint(x: x, y: baselineY - size * 0.34), anchor: .center)
    }

    private func bandLabelLayouts(geometry: EQGeometry, lowCutRect: CGRect) -> [EQBandLabelLayout] {
        var placed = [lowCutRect]
        var result: [EQBandLabelLayout] = []

        for band in 1...3 {
            let gain = state.bandGain(band)
            let frequency = state.bandFrequency(band)
            let q = state.bandQ(band)
            let centerX = geometry.freqToX(frequency)
            let centerY = geometry.dbToY(gain)
            let lines = [formatFrequency(frequency), String(format: "Q %.1f", q), formatGain(gain)]
            let halfWidth = lines.map { CGFloat($0.count) * 4.7 / 2 }.max() ?? 0
            let labelX = min(max(centerX, halfWidth + 4), geometry.size.width - halfWidth - 4)
            let blockHeight: CGFloat = 30

            var minY = CGFloat.greatestFiniteMagnitude
            var maxY = -CGFloat.greatestFiniteMagnitude
            for sample in 0...10 {
                let x = labelX - halfWidth - 2 + CGFloat(sample) / 10 * (halfWidth * 2 + 4)
                let sampledFrequency = min(max(geometry.xToFreq(x), 20), 20000)
                let y = geometry.dbToY(min(max(responseDb(at: sampledFrequency), -24), 24))
                minY = min(minY, y)
                maxY = max(maxY, y)
            }

            let candidates: [(top: CGFloat, above: Bool)] = [
                (centerY - 10 - blockHeight, true),
                (centerY + 11, false),
                (minY - 4 - blockHeight, true),
                (maxY + 4, false)
            ]

            var chosen: CGRect?
            for candidate in candidates {
                let bottom = candidate.top + blockHeight
                guard candidate.top >= 2, bottom <= geometry.size.height - 2 else { continue }
                if candidate.above, bottom > minY - 2 { continue }
                if !candidate.above, candidate.top < maxY + 2 { continue }

                let rect = CGRect(
                    x: labelX - halfWidth - 2,
                    y: candidate.top,
                    width: halfWidth * 2 + 4,
                    height: blockHeight
                )
                let clash = placed.contains { other in
                    !(rect.maxX < other.minX || rect.minX > other.maxX || rect.maxY < other.minY || rect.minY > other.maxY)
                }
                if !clash {
                    chosen = rect
                    break
                }
            }

            if chosen == nil {
                let top = min(max(centerY - 10 - blockHeight, 2), geometry.size.height - 2 - blockHeight)
                chosen = CGRect(x: labelX - halfWidth - 2, y: top, width: halfWidth * 2 + 4, height: blockHeight)
            }

            guard let rect = chosen else { continue }
            placed.append(rect)
            result.append(EQBandLabelLayout(band: band, lines: lines, centerX: labelX, rect: rect))
        }

        return result
    }

    private func lowCutLabelInfo(geometry: EQGeometry) -> (text: String, centerX: CGFloat, baselineY: CGFloat, rect: CGRect) {
        let text = "LC  " + formatFrequency(state.lowCutFreq)
        let halfWidth = CGFloat(text.count) * 4.7 / 2
        let centerX = min(
            max(geometry.freqToX(state.lowCutFreq), halfWidth + 4),
            geometry.size.width - halfWidth - 4
        )
        let baselineY = geometry.size.height - EQGeometry.padBottom - 17
        let rect = CGRect(x: centerX - halfWidth - 2, y: baselineY - 9, width: halfWidth * 2 + 4, height: 12)
        return (text, centerX, baselineY, rect)
    }

    private func hover(_ point: CGPoint?, geometry: EQGeometry) {
        guard dragMode == nil else { return }
        let current = viewModel.eq(target)

        guard let point else {
            if let active, active.hasTip {
                scheduleHide()
            } else {
                hideNow()
            }
            return
        }

        if tipVisible, let tip, tooltipRect(for: tip).contains(point) {
            keepTipVisible()
            return
        }

        guard let node = node(at: point, geometry: geometry, state: current) else {
            if let active, active.hasTip {
                scheduleHide()
            } else {
                hideNow()
            }
            return
        }

        guard active != node else {
            if node.hasTip {
                keepTipVisible()
            }
            return
        }

        if node.hasTip {
            active = node
            showTip(node, geometry: geometry)
        } else {
            hideNow()
            active = node
        }
    }

    private func tooltipRect(for tip: EQTip) -> CGRect {
        let width: CGFloat = tip.node == .lowCut ? 126 : 102
        return CGRect(x: tip.left, y: tip.top, width: width, height: 30)
    }

    private func chip(at point: CGPoint, tip: EQTip) -> EQTipChip? {
        let items = chips(for: tip.node)
        let x = point.x - tip.left - 4
        let y = point.y - tip.top - 4
        guard y >= 0, y <= 20 else { return nil }

        let index = Int(x / 24)
        guard items.indices.contains(index) else { return nil }
        let start = CGFloat(index) * 24
        guard x >= start, x <= start + 20 else { return nil }
        return items[index]
    }

    private func press(_ point: CGPoint, option: Bool, clicks: Int, geometry: EQGeometry) {
        if tipVisible, let tip, tooltipRect(for: tip).contains(point) {
            chip(at: point, tip: tip)?.action()
            return
        }

        let current = viewModel.eq(target)
        guard let node = node(at: point, geometry: geometry, state: current) else {
            hideNow()
            return
        }

        if clicks >= 2 {
            switch node {
            case .band(let band):
                set(bandParameter(band, "Gain")!, value: 0)
            case .lowCut:
                set(.lowCutFreq, value: 80)
            }
            return
        }

        if node.hasTip {
            pauseTip(node, geometry: geometry)
        } else {
            hideNow()
        }
        active = node

        switch node {
        case .band(let band):
            if option {
                dragMode = .q(band)
                dragStartY = point.y
                dragStartQ = current.bandQ(band)
            } else {
                dragMode = .band(band)
            }
        case .lowCut:
            dragMode = .lowCut
        }
    }

    private func dragged(_ point: CGPoint, geometry: EQGeometry) {
        guard let dragMode else { return }

        switch dragMode {
        case .q(let band):
            let span = 9.9 - 0.4
            let value = dragStartQ + Double(dragStartY - point.y) / 140 * span
            set(bandParameter(band, "Q")!, value: min(max(value, 0.4), 9.9))
            pauseTip(.band(band), geometry: geometry)
        case .band(let band):
            let frequency = min(max(geometry.xToFreq(point.x), 20), 20000)
            let gain = min(max(geometry.yToDb(point.y), -20), 20)
            set(bandParameter(band, "Freq")!, value: frequency)
            set(bandParameter(band, "Gain")!, value: gain)
            pauseTip(.band(band), geometry: geometry)
        case .lowCut:
            let frequency = min(max(geometry.xToFreq(point.x), 20), 500)
            set(.lowCutFreq, value: frequency)
            pauseTip(.lowCut, geometry: geometry)
        }
    }

    private func released(_ point: CGPoint, geometry: EQGeometry) {
        guard dragMode != nil else { return }
        dragMode = nil

        let current = viewModel.eq(target)
        if let node = node(at: point, geometry: geometry, state: current) {
            guard active != node else { return }
            active = node
            if node.hasTip {
                showTip(node, geometry: geometry)
            } else {
                hideNow()
                active = node
            }
        } else if active?.hasTip == true {
            scheduleHide()
        } else {
            active = nil
        }
    }

    private func scrolled(_ point: CGPoint, delta: CGFloat, geometry: EQGeometry) {
        let current = viewModel.eq(target)
        guard let node = node(at: point, geometry: geometry, state: current),
              case .band(let band) = node else { return }

        let raw = min(max(Double(delta), -25), 25)
        let change = -raw * 0.004
        if wheelAccum * change < 0 {
            wheelAccum = 0
        }
        wheelAccum += change
        if abs(wheelAccum) < 0.1 {
            return
        }

        let steps = wheelAccum > 0
            ? floor(wheelAccum / 0.1 + 1e-6)
            : ceil(wheelAccum / 0.1 - 1e-6)
        wheelAccum -= steps * 0.1

        let value = min(max(current.bandQ(band) + steps * 0.1, 0.4), 9.9)
        set(bandParameter(band, "Q")!, value: value)
        if value <= 0.4 || value >= 9.9 {
            wheelAccum = 0
        }
        pauseTip(.band(band), geometry: geometry)
    }

    private func node(at point: CGPoint, geometry: EQGeometry, state: EQState) -> EQNode? {
        let cut = CGPoint(
            x: geometry.freqToX(state.lowCutFreq),
            y: geometry.size.height - EQGeometry.padBottom - 3
        )
        if hypot(point.x - cut.x, point.y - cut.y) <= 11 {
            return .lowCut
        }

        for band in [3, 2, 1] {
            let center = CGPoint(
                x: geometry.freqToX(state.bandFrequency(band)),
                y: geometry.dbToY(state.bandGain(band))
            )
            if hypot(point.x - center.x, point.y - center.y) <= 12 {
                return .band(band)
            }
        }
        return nil
    }

    private func showTip(_ node: EQNode, geometry: EQGeometry) {
        clearTimers()
        guard node.hasTip else { return }
        tip = placeTip(node, geometry: geometry)
        tipVisible = false
        scheduleShow(node)
    }

    private func pauseTip(_ node: EQNode, geometry: EQGeometry) {
        clearTimers()
        if node.hasTip {
            tip = placeTip(node, geometry: geometry)
        }
        tipVisible = false
        scheduleShow(node)
    }

    private func scheduleShow(_ node: EQNode) {
        showTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            showTask = nil
            guard active == node, tip != nil else { return }
            tipVisible = true
        }
    }

    private func keepTipVisible() {
        guard tip != nil, showTask == nil else { return }
        cancelHide()
        guard !tipVisible else { return }
        tipVisible = true
    }

    private func cancelHide() {
        hideTask?.cancel()
        hideTask = nil
        clearTask?.cancel()
        clearTask = nil
    }

    private func scheduleHide() {
        guard hideTask == nil else { return }
        clearTimers()
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            hideTask = nil
            tipVisible = false
            clearTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
                clearTask = nil
                tip = nil
                active = nil
            }
        }
    }

    private func hideNow() {
        clearTimers()
        tipVisible = false
        tip = nil
        active = nil
    }

    private func clearTimers() {
        showTask?.cancel()
        showTask = nil
        hideTask?.cancel()
        hideTask = nil
        clearTask?.cancel()
        clearTask = nil
    }

    private func placeTip(_ node: EQNode, geometry: EQGeometry) -> EQTip {
        let anchor = nodeAnchor(node, geometry: geometry)
        let width: CGFloat = node == .lowCut ? 126 : 102
        let height: CGFloat = 30
        let left = min(max(anchor.x - width / 2, 6), geometry.size.width - width - 6)
        var top = node == .lowCut ? anchor.y - 14 - height : anchor.y + 14
        if node != .lowCut, top + height > geometry.size.height - 4 {
            top = max(4, anchor.y - 14 - height)
        }
        return EQTip(node: node, left: left, top: top)
    }

    private func nodeAnchor(_ node: EQNode, geometry: EQGeometry) -> CGPoint {
        switch node {
        case .band(let band):
            return CGPoint(
                x: geometry.freqToX(state.bandFrequency(band)),
                y: geometry.dbToY(state.bandGain(band))
            )
        case .lowCut:
            return CGPoint(
                x: geometry.freqToX(state.lowCutFreq),
                y: geometry.size.height - EQGeometry.padBottom - 3
            )
        }
    }

    private func responseDb(at frequency: Double) -> Double {
        guard state.enabled else { return 0 }
        var magnitude = bandMagnitude(band: 1, frequency: frequency)
        magnitude *= EQBiquad.magnitude(
            EQBiquad.coefficients(kind: .peak, frequency: state.band2Freq, gain: state.band2Gain, q: state.band2Q),
            at: frequency
        )
        magnitude *= bandMagnitude(band: 3, frequency: frequency)
        if state.lowCutEnabled {
            let order = Double([1, 2, 3, 4][min(max(state.lowCutSlope, 0), 3)])
            magnitude *= 1 / sqrt(1 + pow(state.lowCutFreq / frequency, 2 * order))
        }
        return 20 * log(max(magnitude, 1e-6)) / log(10)
    }

    private func bandMagnitude(band: Int, frequency: Double) -> Double {
        let kind: EQBiquad.Kind
        if band == 1 {
            kind = [.peak, .lowShelf, .highPass, .lowPass][min(max(state.band1Type, 0), 3)]
        } else if band == 3 {
            kind = [.peak, .highShelf, .lowPass, .highPass][min(max(state.band3Type, 0), 3)]
        } else {
            kind = .peak
        }
        return EQBiquad.magnitude(
            EQBiquad.coefficients(
                kind: kind,
                frequency: state.bandFrequency(band),
                gain: state.bandGain(band),
                q: state.bandQ(band)
            ),
            at: frequency
        )
    }

    private func set(_ parameter: EQParameter, value: Double) {
        let clamped = min(max(value, parameter.range.lowerBound), parameter.range.upperBound)
        let rounded: Double
        switch parameter {
        case .band1Type, .band3Type, .lowCutSlope, .band1Freq, .band2Freq, .band3Freq, .lowCutFreq:
            rounded = clamped.rounded()
        default:
            rounded = (clamped * 10).rounded() / 10
        }
        viewModel.setEQParameter(target, parameter, rounded)
    }

    private func bandParameter(_ band: Int, _ suffix: String) -> EQParameter? {
        EQParameter(rawValue: "band\(band)\(suffix)")
    }

    private func formatFrequency(_ frequency: Double) -> String {
        if frequency >= 1000 {
            return String(format: "%.1f kHz", frequency / 1000)
        }
        return String(format: "%.0f Hz", frequency.rounded())
    }

    private func formatGain(_ gain: Double) -> String {
        (gain > 0 ? "+" : "") + String(format: "%.1f dB", gain)
    }

    @ViewBuilder
    private func tooltip(for tip: EQTip) -> some View {
        HStack(spacing: 4) {
            ForEach(chips(for: tip.node)) { chip in
                Button(action: chip.action) {
                    ZStack {
                        Circle()
                            .fill(chip.isOn ? chip.color : Color.primary.opacity(0.07))
                        if let icon = chip.icon {
                            EQTypeIcon(kind: icon)
                                .stroke(
                                    chip.isOn ? Color.white : Color.secondary,
                                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
                                )
                                .frame(width: 14, height: 9)
                        } else {
                            Text(chip.label ?? "")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(chip.isOn ? Color.white : Color.secondary)
                        }
                    }
                    .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.28), radius: 10, x: 0, y: 6)
        .fixedSize()
    }

    private func chips(for node: EQNode) -> [EQTipChip] {
        switch node {
        case .band(let band) where band == 1 || band == 3:
            let color = EQPalette.band(band)
            let kinds: [EQTypeIcon.Kind] = band == 1
                ? [.bell, .lowShelf, .highPass, .lowPass]
                : [.bell, .highShelf, .lowPass, .highPass]
            let current = state.bandType(band)
            return kinds.enumerated().map { index, kind in
                EQTipChip(
                    id: "band\(band)-\(index)",
                    label: nil,
                    icon: kind,
                    isOn: current == index,
                    color: color
                ) {
                    set(bandParameter(band, "Type")!, value: Double(index))
                }
            }
        case .lowCut:
            var result = [
                EQTipChip(id: "lc", label: "LC", icon: nil, isOn: state.lowCutEnabled, color: EQPalette.red) {
                    viewModel.setLowCutEnabled(target, !state.lowCutEnabled)
                }
            ]
            for (index, label) in ["6", "12", "18", "24"].enumerated() {
                result.append(
                    EQTipChip(
                        id: "slope-\(index)",
                        label: label,
                        icon: nil,
                        isOn: state.lowCutSlope == index,
                        color: EQPalette.cut
                    ) {
                        set(.lowCutSlope, value: Double(index))
                    }
                )
            }
            return result
        default:
            return []
        }
    }
}

private struct EQInteractionLayer: NSViewRepresentable {
    var onHover: (CGPoint?) -> Void
    var onPress: (CGPoint, Bool, Int) -> Void
    var onDrag: (CGPoint) -> Void
    var onRelease: (CGPoint) -> Void
    var onScroll: (CGPoint, CGFloat) -> Void

    func makeNSView(context: Context) -> EventView {
        let view = EventView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: EventView, context: Context) {
        update(nsView)
    }

    private func update(_ view: EventView) {
        view.onHover = onHover
        view.onPress = onPress
        view.onDrag = onDrag
        view.onRelease = onRelease
        view.onScroll = onScroll
    }

    final class EventView: NSView {
        var onHover: ((CGPoint?) -> Void)?
        var onPress: ((CGPoint, Bool, Int) -> Void)?
        var onDrag: ((CGPoint) -> Void)?
        var onRelease: ((CGPoint) -> Void)?
        var onScroll: ((CGPoint, CGFloat) -> Void)?

        private var tracking: NSTrackingArea?

        override var isFlipped: Bool { true }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.acceptsMouseMovedEvents = true
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking {
                removeTrackingArea(tracking)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            tracking = area
        }

        private func point(for event: NSEvent) -> CGPoint {
            convert(event.locationInWindow, from: nil)
        }

        override func mouseMoved(with event: NSEvent) {
            onHover?(point(for: event))
        }

        override func mouseEntered(with event: NSEvent) {
            onHover?(point(for: event))
        }

        override func mouseExited(with event: NSEvent) {
            onHover?(nil)
        }

        override func mouseDown(with event: NSEvent) {
            onPress?(
                point(for: event),
                event.modifierFlags.contains(.option),
                event.clickCount
            )
        }

        override func mouseDragged(with event: NSEvent) {
            onDrag?(point(for: event))
        }

        override func mouseUp(with event: NSEvent) {
            onRelease?(point(for: event))
        }

        override func scrollWheel(with event: NSEvent) {
            onScroll?(point(for: event), event.scrollingDeltaY)
        }
    }
}

private struct EQGeometry {
    static let padLeft: CGFloat = 8
    static let padRight: CGFloat = 8
    static let padTop: CGFloat = 24
    static let padBottom: CGFloat = 16

    let size: CGSize

    private var plotWidth: CGFloat {
        size.width - Self.padLeft - Self.padRight
    }

    private var plotHeight: CGFloat {
        size.height - Self.padTop - Self.padBottom
    }

    func freqToX(_ frequency: Double) -> CGFloat {
        Self.padLeft + CGFloat(log(frequency / 20) / log(1000)) * plotWidth
    }

    func xToFreq(_ x: CGFloat) -> Double {
        20 * pow(1000, Double((x - Self.padLeft) / plotWidth))
    }

    func dbToY(_ db: Double) -> CGFloat {
        let y = Self.padTop + CGFloat((20 - db) / 40) * plotHeight
        return min(max(y, Self.padTop), size.height - Self.padBottom)
    }

    func yToDb(_ y: CGFloat) -> Double {
        20 - Double((y - Self.padTop) / plotHeight) * 40
    }
}

private enum EQPalette {
    static var low: Color { .orange }
    static var mid: Color { .teal }
    static var high: Color { .green }
    static var cut: Color { .purple }
    static var red: Color { .red }
    static var graphBackground: Color { Color(nsColor: .textBackgroundColor) }

    static func band(_ band: Int) -> Color {
        switch band {
        case 1: return low
        case 2: return mid
        default: return high
        }
    }
}

private enum EQNode: Hashable {
    case band(Int)
    case lowCut

    var hasTip: Bool {
        switch self {
        case .band(1), .band(3), .lowCut: return true
        default: return false
        }
    }
}

private enum EQDragMode {
    case band(Int)
    case q(Int)
    case lowCut
}

private struct EQTip {
    let node: EQNode
    let left: CGFloat
    let top: CGFloat
}

private struct EQBandLabelLayout {
    let band: Int
    let lines: [String]
    let centerX: CGFloat
    let rect: CGRect
}

private struct EQTipChip: Identifiable {
    let id: String
    let label: String?
    let icon: EQTypeIcon.Kind?
    let isOn: Bool
    let color: Color
    let action: () -> Void
}

private struct EQTypeIcon: Shape {
    enum Kind {
        case bell
        case lowShelf
        case highShelf
        case highPass
        case lowPass
    }

    let kind: Kind

    func path(in rect: CGRect) -> Path {
        let scaleX = rect.width / 20
        let scaleY = rect.height / 12
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scaleX, y: rect.minY + y * scaleY)
        }

        var path = Path()
        switch kind {
        case .bell:
            path.move(to: point(2, 9))
            path.addCurve(to: point(10, 3), control1: point(6, 9), control2: point(6, 3))
            path.addCurve(to: point(18, 9), control1: point(14, 3), control2: point(14, 9))
        case .lowShelf:
            path.move(to: point(2, 3))
            path.addLine(to: point(7, 3))
            path.addCurve(to: point(11, 9), control1: point(9, 3), control2: point(9, 9))
            path.addLine(to: point(18, 9))
        case .highShelf:
            path.move(to: point(2, 9))
            path.addLine(to: point(7, 9))
            path.addCurve(to: point(11, 3), control1: point(9, 9), control2: point(9, 3))
            path.addLine(to: point(18, 3))
        case .highPass:
            path.move(to: point(2, 9))
            path.addCurve(to: point(12, 3), control1: point(7, 9), control2: point(7, 3))
            path.addLine(to: point(18, 3))
        case .lowPass:
            path.move(to: point(2, 3))
            path.addLine(to: point(8, 3))
            path.addCurve(to: point(18, 9), control1: point(13, 3), control2: point(13, 9))
        }
        return path
    }
}

private enum EQBiquad {
    enum Kind {
        case peak
        case lowShelf
        case highShelf
        case highPass
        case lowPass
    }

    static let sampleRate = 48000.0

    static func coefficients(kind: Kind, frequency: Double, gain: Double, q: Double) -> [Double] {
        let a = pow(10, gain / 40)
        let w0 = 2 * Double.pi * min(max(frequency, 10), sampleRate / 2 - 10) / sampleRate
        let cosW = cos(w0)
        let sinW = sin(w0)

        switch kind {
        case .peak:
            let alpha = sinW / (2 * max(q, 0.05))
            return [
                1 + alpha * a, -2 * cosW, 1 - alpha * a,
                1 + alpha / a, -2 * cosW, 1 - alpha / a
            ]
        case .lowShelf:
            let alpha = sinW / (2 * max(q, 0.05))
            let sqrtA = sqrt(a)
            let twoSqrtAAlpha = 2 * sqrtA * alpha
            return [
                a * ((a + 1) - (a - 1) * cosW + twoSqrtAAlpha),
                2 * a * ((a - 1) - (a + 1) * cosW),
                a * ((a + 1) - (a - 1) * cosW - twoSqrtAAlpha),
                (a + 1) + (a - 1) * cosW + twoSqrtAAlpha,
                -2 * ((a - 1) + (a + 1) * cosW),
                (a + 1) + (a - 1) * cosW - twoSqrtAAlpha
            ]
        case .highShelf:
            let alpha = sinW / (2 * max(q, 0.05))
            let sqrtA = sqrt(a)
            let twoSqrtAAlpha = 2 * sqrtA * alpha
            return [
                a * ((a + 1) + (a - 1) * cosW + twoSqrtAAlpha),
                -2 * a * ((a - 1) + (a + 1) * cosW),
                a * ((a + 1) + (a - 1) * cosW - twoSqrtAAlpha),
                (a + 1) - (a - 1) * cosW + twoSqrtAAlpha,
                2 * ((a - 1) - (a + 1) * cosW),
                (a + 1) - (a - 1) * cosW - twoSqrtAAlpha
            ]
        case .highPass:
            let alpha = sinW / (2 * max(q, 0.05))
            return [
                (1 + cosW) / 2, -(1 + cosW), (1 + cosW) / 2,
                1 + alpha, -2 * cosW, 1 - alpha
            ]
        case .lowPass:
            let alpha = sinW / (2 * max(q, 0.05))
            return [
                (1 - cosW) / 2, 1 - cosW, (1 - cosW) / 2,
                1 + alpha, -2 * cosW, 1 - alpha
            ]
        }
    }

    static func magnitude(_ coefficients: [Double], at frequency: Double) -> Double {
        let w = 2 * Double.pi * frequency / sampleRate
        let cosW = cos(w)
        let sinW = sin(w)
        let cos2W = cos(2 * w)
        let sin2W = sin(2 * w)

        let numeratorReal = coefficients[0] + coefficients[1] * cosW + coefficients[2] * cos2W
        let numeratorImaginary = -(coefficients[1] * sinW + coefficients[2] * sin2W)
        let denominatorReal = coefficients[3] + coefficients[4] * cosW + coefficients[5] * cos2W
        let denominatorImaginary = -(coefficients[4] * sinW + coefficients[5] * sin2W)
        let denominator = denominatorReal * denominatorReal + denominatorImaginary * denominatorImaginary
        if denominator < 1e-12 {
            return 1
        }
        return sqrt((numeratorReal * numeratorReal + numeratorImaginary * numeratorImaginary) / denominator)
    }
}

private extension EQState {
    func bandGain(_ band: Int) -> Double {
        switch band {
        case 1: return band1Gain
        case 2: return band2Gain
        default: return band3Gain
        }
    }

    func bandFrequency(_ band: Int) -> Double {
        switch band {
        case 1: return band1Freq
        case 2: return band2Freq
        default: return band3Freq
        }
    }

    func bandQ(_ band: Int) -> Double {
        switch band {
        case 1: return band1Q
        case 2: return band2Q
        default: return band3Q
        }
    }

    func bandType(_ band: Int) -> Int {
        band == 1 ? band1Type : band3Type
    }
}
