import SwiftUI

/// Полоса на общем графике EQ: номер с единицы, частота, усиление, добротность
/// и индекс типа кривой. Так график не зависит от того, чей это эквалайзер —
/// трёхполосный канала или девятиполосный Room EQ.
struct EQGraphBand: Identifiable, Equatable {
    let number: Int
    var frequency: Double
    var gain: Double
    var q: Double
    var type: Int

    var id: Int { number }
}

/// Режим подписей полос на графике.
enum EQGraphLabelMode {
    case all
    case focused
}

/// Low Cut канального EQ: у Room EQ такого узла нет.
struct EQGraphCut: Equatable {
    var enabled: Bool
    var frequency: Double
    var slope: Int
}

/// Кривая второго канала стереопары: рисуется как ориентир, без узлов и подписей.
struct EQGraphReference {
    var responseDb: (Double) -> Double
    var color: Color
    var opacity: Double = 0.65
    var lineWidth: CGFloat = 1.4
    /// Выключенный канал рисуется серым, но его кривая остаётся видимой.
    var enabled: Bool = true
}

/// Всё, что нужно графику, чтобы нарисовать кривую и подписи.
struct EQGraphModel {
    var bands: [EQGraphBand]
    var enabled: Bool
    var cut: EQGraphCut?
    /// Какие подписи показывать: все полосы (канальный EQ) или только активную
    /// (девять полос Room EQ иначе перекрывают друг друга).
    var labelMode: EQGraphLabelMode = .all
    /// Типы кривой по номеру полосы. Полосы без записи типа не показывают тултип.
    var typedKinds: [Int: [EQTypeIcon.Kind]]
    var bandColor: (Int) -> Color
    var cutColor: Color
    var responseDb: (Double) -> Double
    var bandResponseDb: (_ band: Int, _ frequency: Double) -> Double
    /// Цвет основной кривой; `nil` — системный, как в канальном EQ.
    var curveColor: Color? = nil
    /// Цвет заливки под основной кривой; `nil` — акцентный.
    var fillColor: Color? = nil
    /// Кривая второго канала в стереопаре Room EQ.
    var reference: EQGraphReference? = nil

    func band(_ number: Int) -> EQGraphBand? {
        bands.first { $0.number == number }
    }
}

/// Действия графика. Частота и усиление приходят готовыми значениями, Q — как
/// приращение (`addQ`) или абсолютное значение (`setQ`), чтобы график не хранил
/// состояние, которое живёт в модели канала.
struct EQGraphActions {
    var setPosition: (_ band: Int, _ frequency: Double, _ gain: Double) -> Void
    var setQ: (_ band: Int, _ q: Double) -> Void
    var addQ: (_ band: Int, _ delta: Double) -> Void
    var currentQ: (_ band: Int) -> Double
    var setType: (_ band: Int, _ index: Int) -> Void
    var resetBand: (_ band: Int) -> Void
    var setCutFrequency: (_ frequency: Double) -> Void
    var toggleCut: () -> Void
    var setCutSlope: (_ index: Int) -> Void
}

/// График эквалайзера: сетка, суммарная кривая, кривые полос, узлы с подписями
/// и тултип с типами фильтра. Общий для `EqualizerView` и `RoomEQView`, чтобы
/// окна выглядели и вели себя одинаково.
struct EQGraphView: View {
    let model: EQGraphModel
    let actions: EQGraphActions

    @State private var active: EQGraphNode?
    @State private var tip: EQTip?
    @State private var tipVisible = false
    @State private var dragMode: EQDragMode?
    @State private var dragStartY: CGFloat = 0
    @State private var dragStartQ: Double = 0
    @State private var wheelAccum = 0.0
    @State private var focusedBand: Int?
    @State private var showTask: Task<Void, Never>?
    @State private var hideTask: Task<Void, Never>?
    @State private var clearTask: Task<Void, Never>?
    /// Положение мыши над графиком: по нему рисуется считывание и живёт подсказка.
    @State private var pointer: CGPoint?

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
                    onScroll: { point, delta in scrolled(point, delta: delta, geometry: geometry) },
                    cursorFor: { point in
                        guard let point else { return .arrow }
                        return node(at: point, geometry: geometry) == nil ? .arrow : .pointingHand
                    }
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

                gestureHint(geometry: geometry)
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

    // MARK: - Рисование

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

        for db in stride(from: -18.0, through: 18.0, by: 6.0) {
            let y = geometry.dbToY(db)
            var path = Path()
            path.move(to: CGPoint(x: EQGeometry.padLeft, y: y))
            path.addLine(to: CGPoint(x: geometry.size.width - EQGeometry.padRight, y: y))
            context.stroke(
                path,
                with: .color(Color.primary.opacity(db == 0 ? 0.16 : 0.055)),
                lineWidth: 1
            )

            var tick = Path()
            tick.move(to: CGPoint(x: EQGeometry.padLeft - 3, y: y))
            tick.addLine(to: CGPoint(x: EQGeometry.padLeft, y: y))
            context.stroke(tick, with: .color(Color.primary.opacity(0.18)), lineWidth: 1)

            let label = db > 0 ? "+\(Int(db))" : "\(Int(db))"
            drawText(
                label,
                x: EQGeometry.padLeft / 2,
                baselineY: y + 2.5,
                size: 7.5,
                weight: .medium,
                color: .secondary,
                tracking: 0,
                context: &context
            )
        }

        // Частотная ось повторяет децибельную: насечка у каждой опорной частоты
        // и подпись под ней. В узком графике подписи прореживаются, чтобы не липнуть.
        let frequencyTicks: [(frequency: Double, label: String)] = [
            (20, "20"), (50, "50"), (100, "100"), (200, "200"), (500, "500"),
            (1_000, "1k"), (2_000, "2k"), (5_000, "5k"), (10_000, "10k"), (20_000, "20k")
        ]
        let plotWidth = geometry.size.width - EQGeometry.padLeft - EQGeometry.padRight
        let labelled: Set<Double> = plotWidth >= 360
            ? Set(frequencyTicks.map(\.frequency))
            : [20, 100, 1_000, 10_000]

        for tick in frequencyTicks {
            let x = geometry.freqToX(tick.frequency)

            var mark = Path()
            mark.move(to: CGPoint(x: x, y: geometry.size.height - EQGeometry.padBottom))
            mark.addLine(to: CGPoint(x: x, y: geometry.size.height - EQGeometry.padBottom + 4))
            context.stroke(mark, with: .color(Color.primary.opacity(0.22)), lineWidth: 1)

            guard labelled.contains(tick.frequency) else { continue }
            drawText(
                tick.label,
                x: min(max(x, 10), geometry.size.width - 10),
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
            let db = min(max(model.responseDb(frequency), -24), 24)
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
            let fillTint = model.enabled ? (model.fillColor ?? Color.accentColor) : Color.primary
            context.fill(
                fill,
                with: .linearGradient(
                    Gradient(colors: [
                        fillTint.opacity(model.enabled ? 0.20 : 0.06),
                        fillTint.opacity(model.enabled ? 0.015 : 0.005)
                    ]),
                    startPoint: CGPoint(x: 0, y: EQGeometry.padTop),
                    endPoint: CGPoint(x: 0, y: geometry.size.height - EQGeometry.padBottom)
                )
            )
        }

        if model.enabled {
            for band in model.bands {
                var path = Path()
                for index in 0...160 {
                    let frequency = 20 * pow(1000, Double(index) / 160)
                    let db = min(max(model.bandResponseDb(band.number, frequency), -24), 24)
                    let point = CGPoint(x: geometry.freqToX(frequency), y: geometry.dbToY(db))
                    if index == 0 {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                }
                context.stroke(path, with: .color(model.bandColor(band.number).opacity(0.42)), lineWidth: 1)
            }
        }

        if let reference = model.reference {
            var path = Path()
            for index in 0...220 {
                let frequency = 20 * pow(1000, Double(index) / 220)
                let db = min(max(reference.responseDb(frequency), -24), 24)
                let point = CGPoint(x: geometry.freqToX(frequency), y: geometry.dbToY(db))
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            context.stroke(
                path,
                with: .color(reference.enabled
                             ? reference.color.opacity(reference.opacity)
                             : Color.primary.opacity(0.3)),
                style: StrokeStyle(lineWidth: reference.lineWidth, lineCap: .round, lineJoin: .round)
            )
        }

        var curve = Path()
        if let first = mainPoints.first {
            curve.move(to: first)
            for point in mainPoints.dropFirst() {
                curve.addLine(to: point)
            }
        }
        let primaryColor = model.enabled ? (model.curveColor ?? Color.primary) : Color.primary
        let primaryOpacity = model.enabled
            ? (model.curveColor == nil ? 0.9 : 0.95)
            : 0.35
        context.stroke(
            curve,
            with: .color(primaryColor.opacity(primaryOpacity)),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        )

        if let cut = model.cut, cut.enabled {
            var path = Path()
            let x = geometry.freqToX(cut.frequency)
            path.move(to: CGPoint(x: x, y: EQGeometry.padTop))
            path.addLine(to: CGPoint(x: x, y: geometry.size.height - EQGeometry.padBottom))
            context.stroke(
                path,
                with: .color(model.cutColor.opacity(0.5)),
                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
            )
        }

        let cutLabel = model.cut.map { cutLabelInfo($0, geometry: geometry) }
        let labels = bandLabelLayouts(geometry: geometry, cutRect: cutLabel?.rect)

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
        }

        for band in model.bands {
            let color = model.bandColor(band.number)
            let center = CGPoint(
                x: geometry.freqToX(band.frequency),
                y: geometry.dbToY(band.gain)
            )

            if active == .band(band.number) {
                let ring = Path(ellipseIn: CGRect(x: center.x - 9, y: center.y - 9, width: 18, height: 18))
                context.fill(ring, with: .color(color.opacity(0.12)))
                context.stroke(ring, with: .color(color.opacity(0.65)), lineWidth: 1.4)
            }

            let node = Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10))
            context.fill(node, with: .color(color))
            context.stroke(node, with: .color(EQPalette.graphBackground), lineWidth: 1.6)
        }

        if let cut = model.cut, let cutLabel {
            let cutX = geometry.freqToX(cut.frequency)
            let cutY = geometry.size.height - EQGeometry.padBottom - 3

            if active == .cut {
                let ring = Path(ellipseIn: CGRect(x: cutX - 10, y: cutY - 10, width: 20, height: 20))
                context.fill(ring, with: .color(model.cutColor.opacity(0.12)))
                context.stroke(ring, with: .color(model.cutColor.opacity(0.65)), lineWidth: 1.4)
            }

            let cutNode = Path(ellipseIn: CGRect(x: cutX - 4, y: cutY - 4, width: 8, height: 8))
            context.fill(
                cutNode,
                with: .color(cut.enabled ? model.cutColor : Color.primary.opacity(0.18))
            )
            context.stroke(
                cutNode,
                with: .color(model.cutColor.opacity(cut.enabled ? 1 : 0.5)),
                lineWidth: 1.2
            )

            drawText(
                cutLabel.text,
                x: cutLabel.centerX,
                baselineY: cutLabel.baselineY,
                size: 9,
                weight: .semibold,
                color: .secondary,
                tracking: 0.1,
                context: &context
            )
        }

        drawPointerReadout(context: &context, geometry: geometry)
    }

    // MARK: - Считывание под курсором

    /// Пока курсор в пустой части графика, под ним живёт вертикаль, точка на
    /// кривой и плашка с частотой и уровнем: АЧХ можно прочитать, не трогая полосы.
    private func drawPointerReadout(context: inout GraphicsContext, geometry: EQGeometry) {
        guard let pointer, active == nil, dragMode == nil, !tipVisible else { return }
        let plotLeft = EQGeometry.padLeft
        let plotRight = geometry.size.width - EQGeometry.padRight
        let plotBottom = geometry.size.height - EQGeometry.padBottom
        guard pointer.x >= plotLeft, pointer.x <= plotRight,
              pointer.y >= EQGeometry.padTop, pointer.y <= plotBottom else { return }

        let frequency = min(max(geometry.xToFreq(pointer.x), 20), 20_000)
        let db = min(max(model.responseDb(frequency), -20), 20)

        var hair = Path()
        hair.move(to: CGPoint(x: pointer.x, y: EQGeometry.padTop))
        hair.addLine(to: CGPoint(x: pointer.x, y: plotBottom))
        context.stroke(hair,
                       with: .color(Color.primary.opacity(0.16)),
                       style: StrokeStyle(lineWidth: 1, dash: [2, 3]))

        let dotY = geometry.dbToY(db)
        let dot = Path(ellipseIn: CGRect(x: pointer.x - 3, y: dotY - 3, width: 6, height: 6))
        context.fill(dot, with: .color(model.enabled ? Color.accentColor : Color.primary.opacity(0.5)))

        let caption = "\(formatFrequency(frequency)) · \(formatGain(db))"
        let width = CGFloat(caption.count) * 5.1 + 12
        let height: CGFloat = 17
        var left = pointer.x + 12
        if left + width > plotRight { left = pointer.x - 12 - width }
        left = min(max(left, plotLeft), max(plotRight - width, plotLeft))
        var top = pointer.y - height - 10
        if top < EQGeometry.padTop { top = pointer.y + 12 }
        top = min(max(top, EQGeometry.padTop), max(plotBottom - height, EQGeometry.padTop))

        let pill = Path(roundedRect: CGRect(x: left, y: top, width: width, height: height),
                        cornerRadius: 5)
        context.fill(pill, with: .color(Color.primary.opacity(0.07)))
        context.stroke(pill, with: .color(Color.primary.opacity(0.10)), lineWidth: 1)
        context.draw(
            Text(caption)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary),
            at: CGPoint(x: left + width / 2, y: top + height / 2),
            anchor: .center
        )
    }

    /// Подсказка по жестам: появляется только над пустым графиком и сразу гаснет,
    /// когда курсор уходит на полосу — постоянной строкой она бы мешала.
    @ViewBuilder
    private func gestureHint(geometry: EQGeometry) -> some View {
        Text("Drag to move · Scroll to change Q · Double-click to flatten")
            .font(.system(size: 9))
            .foregroundStyle(Color.secondary.opacity(0.75))
            .lineLimit(1)
            .padding(.leading, EQGeometry.padLeft + 6)
            .padding(.top, 5)
            .opacity(hintVisible(geometry) ? 1 : 0)
            .animation(.easeOut(duration: 0.16), value: hintVisible(geometry))
            .allowsHitTesting(false)
    }

    private func hintVisible(_ geometry: EQGeometry) -> Bool {
        guard let pointer, active == nil, dragMode == nil, !tipVisible else { return false }
        return pointer.x >= EQGeometry.padLeft
            && pointer.x <= geometry.size.width - EQGeometry.padRight
            && pointer.y >= EQGeometry.padTop
            && pointer.y <= geometry.size.height - EQGeometry.padBottom
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

    private var labelledBands: [EQGraphBand] {
        switch model.labelMode {
        case .all:
            return model.bands
        case .focused:
            guard let focusedBand else { return [] }
            return model.bands.filter { $0.number == focusedBand }
        }
    }

    private func bandLabelLayouts(geometry: EQGeometry, cutRect: CGRect?) -> [EQBandLabelLayout] {
        var placed = cutRect.map { [$0] } ?? []
        var result: [EQBandLabelLayout] = []

        for band in labelledBands {
            let centerX = geometry.freqToX(band.frequency)
            let centerY = geometry.dbToY(band.gain)
            let lines = [formatFrequency(band.frequency), String(format: "Q %.1f", band.q), formatGain(band.gain)]
            let halfWidth = lines.map { CGFloat($0.count) * 4.7 / 2 }.max() ?? 0
            let labelX = min(max(centerX, halfWidth + 4), geometry.size.width - halfWidth - 4)
            let blockHeight: CGFloat = 30

            var minY = CGFloat.greatestFiniteMagnitude
            var maxY = -CGFloat.greatestFiniteMagnitude
            for sample in 0...10 {
                let x = labelX - halfWidth - 2 + CGFloat(sample) / 10 * (halfWidth * 2 + 4)
                let sampledFrequency = min(max(geometry.xToFreq(x), 20), 20000)
                let y = geometry.dbToY(min(max(model.responseDb(sampledFrequency), -24), 24))
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

    private func cutLabelInfo(_ cut: EQGraphCut, geometry: EQGeometry) -> (text: String, centerX: CGFloat, baselineY: CGFloat, rect: CGRect) {
        let text = "LC  " + formatFrequency(cut.frequency)
        let halfWidth = CGFloat(text.count) * 4.7 / 2
        let centerX = min(
            max(geometry.freqToX(cut.frequency), halfWidth + 4),
            geometry.size.width - halfWidth - 4
        )
        let baselineY = geometry.size.height - EQGeometry.padBottom - 17
        let rect = CGRect(x: centerX - halfWidth - 2, y: baselineY - 9, width: halfWidth * 2 + 4, height: 12)
        return (text, centerX, baselineY, rect)
    }

    // MARK: - Наведение и подсказки

    private func hover(_ point: CGPoint?, geometry: EQGeometry) {
        guard dragMode == nil else { return }
        // Сдвиг меньше пикселя не меняет картинку — не гоняем лишний кадр.
        if let point, let pointer, hypot(pointer.x - point.x, pointer.y - point.y) < 1 {
            return
        }
        pointer = point

        guard let point else {
            focusedBand = nil
            if let active, hasTip(active) {
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

        guard let node = node(at: point, geometry: geometry) else {
            focusedBand = nil
            if let active, hasTip(active) {
                scheduleHide()
            } else {
                hideNow()
            }
            return
        }

        if case .band(let number) = node {
            focusedBand = number
        }

        guard active != node else {
            if hasTip(node) {
                keepTipVisible()
            }
            return
        }

        if hasTip(node) {
            active = node
            showTip(node, geometry: geometry)
        } else {
            hideNow()
            active = node
        }
    }

    private func hasTip(_ node: EQGraphNode) -> Bool {
        switch node {
        case .band(let number): return model.typedKinds[number] != nil
        case .cut: return model.cut != nil
        }
    }

    private func tooltipRect(for tip: EQTip) -> CGRect {
        let width: CGFloat = tip.node == .cut ? 126 : 102
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

    // MARK: - Мышь

    private func press(_ point: CGPoint, option: Bool, clicks: Int, geometry: EQGeometry) {
        if tipVisible, let tip, tooltipRect(for: tip).contains(point) {
            chip(at: point, tip: tip)?.action()
            return
        }

        guard let node = node(at: point, geometry: geometry) else {
            hideNow()
            return
        }

        if clicks >= 2 {
            switch node {
            case .band(let band):
                actions.resetBand(band)
            case .cut:
                actions.setCutFrequency(80)
            }
            return
        }

        if case .band(let number) = node {
            focusedBand = number
        }

        if hasTip(node) {
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
                dragStartQ = model.band(band)?.q ?? 1
            } else {
                dragMode = .band(band)
            }
        case .cut:
            dragMode = .cut
        }
    }

    private func dragged(_ point: CGPoint, geometry: EQGeometry) {
        guard let dragMode else { return }

        switch dragMode {
        case .q(let band):
            focusedBand = band
            let span = 9.9 - 0.4
            let value = dragStartQ + Double(dragStartY - point.y) / 140 * span
            actions.setQ(band, min(max(value, 0.4), 9.9))
            pauseTip(.band(band), geometry: geometry)
        case .band(let band):
            focusedBand = band
            let frequency = min(max(geometry.xToFreq(point.x), 20), 20000)
            let gain = min(max(geometry.yToDb(point.y), -20), 20)
            // Мышь шлёт события чаще кадров: микросдвиг не записываем, иначе
            // каждое движение впустую перерисовывает всё окно.
            if let current = model.band(band),
               abs(current.gain - gain) < 0.01,
               abs(log(current.frequency / frequency)) < 0.0005 {
                return
            }
            actions.setPosition(band, frequency, gain)
            pauseTip(.band(band), geometry: geometry)
        case .cut:
            let frequency = min(max(geometry.xToFreq(point.x), 20), 500)
            actions.setCutFrequency(frequency)
            pauseTip(.cut, geometry: geometry)
        }
    }

    private func released(_ point: CGPoint, geometry: EQGeometry) {
        guard dragMode != nil else { return }
        dragMode = nil

        if let node = node(at: point, geometry: geometry) {
            guard active != node else { return }
            active = node
            if hasTip(node) {
                showTip(node, geometry: geometry)
            } else {
                hideNow()
                active = node
            }
        } else if active.map(hasTip) == true {
            focusedBand = nil
            scheduleHide()
        } else {
            focusedBand = nil
            active = nil
        }
    }

    private func scrolled(_ point: CGPoint, delta: CGFloat, geometry: EQGeometry) {
        guard let node = node(at: point, geometry: geometry),
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

        focusedBand = band
        let value = min(max(actions.currentQ(band) + steps * 0.1, 0.4), 9.9)
        actions.setQ(band, value)
        if value <= 0.4 || value >= 9.9 {
            wheelAccum = 0
        }
        pauseTip(.band(band), geometry: geometry)
    }

    private func node(at point: CGPoint, geometry: EQGeometry) -> EQGraphNode? {
        if let cut = model.cut {
            let cutPoint = CGPoint(
                x: geometry.freqToX(cut.frequency),
                y: geometry.size.height - EQGeometry.padBottom - 3
            )
            if hypot(point.x - cutPoint.x, point.y - cutPoint.y) <= 11 {
                return .cut
            }
        }

        for band in model.bands.reversed() {
            let center = CGPoint(
                x: geometry.freqToX(band.frequency),
                y: geometry.dbToY(band.gain)
            )
            if hypot(point.x - center.x, point.y - center.y) <= 12 {
                return .band(band.number)
            }
        }
        return nil
    }

    // MARK: - Видимость тултипа

    private func showTip(_ node: EQGraphNode, geometry: EQGeometry) {
        clearTimers()
        guard hasTip(node) else { return }
        tip = placeTip(node, geometry: geometry)
        tipVisible = false
        scheduleShow(node)
    }

    private func pauseTip(_ node: EQGraphNode, geometry: EQGeometry) {
        clearTimers()
        if hasTip(node) {
            tip = placeTip(node, geometry: geometry)
        }
        tipVisible = false
        scheduleShow(node)
    }

    private func scheduleShow(_ node: EQGraphNode) {
        showTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
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

    private func placeTip(_ node: EQGraphNode, geometry: EQGeometry) -> EQTip {
        let anchor = nodeAnchor(node, geometry: geometry)
        let width: CGFloat = node == .cut ? 126 : 102
        let height: CGFloat = 30
        let left = min(max(anchor.x - width / 2, 6), geometry.size.width - width - 6)

        // Рядом с ручкой нарисованы frequency/Q/gain. Выбор типа должен быть
        // с противоположной стороны ручки и при этом рядом с ней.
        if case .band(let number) = node, model.typedKinds[number] != nil,
           let label = bandLabelLayouts(geometry: geometry, cutRect: nil)
               .first(where: { $0.band.number == number }) {
            let labelAbove = label.rect.midY < anchor.y
            let preferredTop = labelAbove
                ? anchor.y + 12
                : anchor.y - 12 - height
            let oppositeRect = CGRect(x: left, y: preferredTop, width: width, height: height)

            if preferredTop >= 4,
               preferredTop + height <= geometry.size.height - 4,
               !oppositeRect.intersects(label.rect) {
                return EQTip(node: node, left: left, top: preferredTop)
            }

            // Если с противоположной стороны нет места — ставим сбоку от ручки,
            // не накрывая ни её, ни подпись.
            let sideY = min(max(anchor.y - height / 2, 4), geometry.size.height - height - 4)
            for sideLeft in [anchor.x + 14, anchor.x - width - 14] {
                let clampedLeft = min(max(sideLeft, 6), geometry.size.width - width - 6)
                let rect = CGRect(x: clampedLeft, y: sideY, width: width, height: height)
                if !rect.intersects(label.rect) {
                    return EQTip(node: node, left: clampedLeft, top: sideY)
                }
            }

            let fallback = min(max(preferredTop, 4), geometry.size.height - height - 4)
            return EQTip(node: node, left: left, top: fallback)
        }

        var top = node == .cut ? anchor.y - 14 - height : anchor.y + 12
        if node != .cut, top + height > geometry.size.height - 4 {
            top = max(4, anchor.y - 12 - height)
        }
        return EQTip(node: node, left: left, top: top)
    }

    private func nodeAnchor(_ node: EQGraphNode, geometry: EQGeometry) -> CGPoint {
        switch node {
        case .band(let band):
            let bandState = model.band(band) ?? EQGraphBand(number: band, frequency: 1000, gain: 0, q: 1, type: 0)
            return CGPoint(
                x: geometry.freqToX(bandState.frequency),
                y: geometry.dbToY(bandState.gain)
            )
        case .cut:
            let frequency = model.cut?.frequency ?? 80
            return CGPoint(
                x: geometry.freqToX(frequency),
                y: geometry.size.height - EQGeometry.padBottom - 3
            )
        }
    }

    // MARK: - Тултип

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

    private func chips(for node: EQGraphNode) -> [EQTipChip] {
        switch node {
        case .band(let number):
            guard let kinds = model.typedKinds[number] else { return [] }
            let color = model.bandColor(number)
            let current = model.band(number)?.type ?? 0
            return kinds.enumerated().map { index, kind in
                EQTipChip(
                    id: "band\(number)-\(index)",
                    label: nil,
                    icon: kind,
                    isOn: current == index,
                    color: color
                ) {
                    actions.setType(number, index)
                }
            }
        case .cut:
            guard let cut = model.cut else { return [] }
            var result = [
                EQTipChip(id: "lc", label: "LC", icon: nil, isOn: cut.enabled, color: EQPalette.red) {
                    actions.toggleCut()
                }
            ]
            for (index, label) in ["6", "12", "18", "24"].enumerated() {
                result.append(
                    EQTipChip(
                        id: "slope-\(index)",
                        label: label,
                        icon: nil,
                        isOn: cut.slope == index,
                        color: model.cutColor
                    ) {
                        actions.setCutSlope(index)
                    }
                )
            }
            return result
        }
    }

    // MARK: - Подписи

    private func formatFrequency(_ frequency: Double) -> String {
        if frequency >= 1000 {
            return String(format: "%.1f kHz", frequency / 1000)
        }
        return String(format: "%.0f Hz", frequency.rounded())
    }

    private func formatGain(_ gain: Double) -> String {
        (gain > 0 ? "+" : "") + String(format: "%.1f dB", gain)
    }
}

// MARK: - События мыши

private struct EQInteractionLayer: NSViewRepresentable {
    var onHover: (CGPoint?) -> Void
    var onPress: (CGPoint, Bool, Int) -> Void
    var onDrag: (CGPoint) -> Void
    var onRelease: (CGPoint) -> Void
    var onScroll: (CGPoint, CGFloat) -> Void
    /// Курсор над точкой полосы и над пустым графиком разный: ручка должна
    /// читаться как то, что можно взять.
    var cursorFor: (CGPoint?) -> NSCursor

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
        view.cursorFor = cursorFor
    }

    final class EventView: NSView {
        var onHover: ((CGPoint?) -> Void)?
        var onPress: ((CGPoint, Bool, Int) -> Void)?
        var onDrag: ((CGPoint) -> Void)?
        var onRelease: ((CGPoint) -> Void)?
        var onScroll: ((CGPoint, CGFloat) -> Void)?
        var cursorFor: ((CGPoint?) -> NSCursor)?

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
            let point = point(for: event)
            cursorFor?(point).set()
            onHover?(point)
        }

        override func mouseEntered(with event: NSEvent) {
            let point = point(for: event)
            cursorFor?(point).set()
            onHover?(point)
        }

        override func mouseExited(with event: NSEvent) {
            NSCursor.arrow.set()
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
            NSCursor.closedHand.set()
            onDrag?(point(for: event))
        }

        override func mouseUp(with event: NSEvent) {
            let point = point(for: event)
            onRelease?(point)
            cursorFor?(point).set()
        }

        override func scrollWheel(with event: NSEvent) {
            onScroll?(point(for: event), event.scrollingDeltaY)
        }
    }
}

// MARK: - Геометрия графика

private struct EQGeometry {
    static let padLeft: CGFloat = 26
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

private enum EQGraphNode: Hashable {
    case band(Int)
    case cut
}

private enum EQDragMode {
    case band(Int)
    case q(Int)
    case cut
}

private struct EQTip {
    let node: EQGraphNode
    let left: CGFloat
    let top: CGFloat
}

private struct EQBandLabelLayout {
    let band: EQGraphBand
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

/// Иконка типа кривой: колокол, полка, срез.
struct EQTypeIcon: Shape {
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

/// Общие цвета графика: полосы канального EQ и узел Low Cut.
enum EQPalette {
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
