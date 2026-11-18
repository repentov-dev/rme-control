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
            EQGraphView(model: model(for: eq), actions: actions)
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

    // MARK: - Модель графика

    private func model(for eq: EQState) -> EQGraphModel {
        EQGraphModel(
            bands: (1...3).map { number in
                EQGraphBand(
                    number: number,
                    frequency: eq.bandFrequency(number),
                    gain: eq.bandGain(number),
                    q: eq.bandQ(number),
                    type: number == 2 ? 0 : eq.bandType(number)
                )
            },
            enabled: eq.enabled,
            cut: EQGraphCut(enabled: eq.lowCutEnabled, frequency: eq.lowCutFreq, slope: eq.lowCutSlope),
            typedKinds: [
                1: [.bell, .lowShelf, .highPass, .lowPass],
                3: [.bell, .highShelf, .lowPass, .highPass]
            ],
            bandColor: { EQPalette.band($0) },
            cutColor: EQPalette.cut,
            responseDb: { frequency in responseDb(eq, at: frequency) },
            bandResponseDb: { band, frequency in
                let magnitude = bandMagnitude(eq, band: band, frequency: frequency)
                return 20 * log10(max(magnitude, 1e-6))
            }
        )
    }

    private var actions: EQGraphActions {
        EQGraphActions(
            setPosition: { band, frequency, gain in
                set(bandParameter(band, "Freq")!, value: frequency)
                set(bandParameter(band, "Gain")!, value: gain)
            },
            setQ: { band, q in
                set(bandParameter(band, "Q")!, value: q)
            },
            addQ: { band, delta in
                let current = viewModel.eq(target).bandQ(band)
                set(bandParameter(band, "Q")!, value: current + delta)
            },
            currentQ: { band in
                viewModel.eq(target).bandQ(band)
            },
            setType: { band, index in
                set(bandParameter(band, "Type")!, value: Double(index))
            },
            resetBand: { band in
                set(bandParameter(band, "Gain")!, value: 0)
            },
            setCutFrequency: { frequency in
                set(.lowCutFreq, value: frequency)
            },
            toggleCut: {
                viewModel.setLowCutEnabled(target, !viewModel.eq(target).lowCutEnabled)
            },
            setCutSlope: { index in
                set(.lowCutSlope, value: Double(index))
            }
        )
    }

    private func responseDb(_ eq: EQState, at frequency: Double) -> Double {
        // Кривая остаётся на месте и при bypass — график просто рисует её серой.
        var magnitude = bandMagnitude(eq, band: 1, frequency: frequency)
        magnitude *= EQBiquad.magnitude(
            EQBiquad.coefficients(kind: .peak, frequency: eq.band2Freq, gain: eq.band2Gain, q: eq.band2Q),
            at: frequency
        )
        magnitude *= bandMagnitude(eq, band: 3, frequency: frequency)
        if eq.lowCutEnabled {
            let order = Double([1, 2, 3, 4][min(max(eq.lowCutSlope, 0), 3)])
            magnitude *= 1 / sqrt(1 + pow(eq.lowCutFreq / frequency, 2 * order))
        }
        return 20 * log10(max(magnitude, 1e-6))
    }

    private func bandMagnitude(_ eq: EQState, band: Int, frequency: Double) -> Double {
        let kind: EQBiquad.Kind
        if band == 1 {
            kind = [.peak, .lowShelf, .highPass, .lowPass][min(max(eq.band1Type, 0), 3)]
        } else if band == 3 {
            kind = [.peak, .highShelf, .lowPass, .highPass][min(max(eq.band3Type, 0), 3)]
        } else {
            kind = .peak
        }
        return EQBiquad.magnitude(
            EQBiquad.coefficients(
                kind: kind,
                frequency: eq.bandFrequency(band),
                gain: eq.bandGain(band),
                q: eq.bandQ(band)
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
}

// MARK: - АЧХ канального EQ

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
