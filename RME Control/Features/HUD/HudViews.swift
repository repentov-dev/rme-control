import AppKit
import SwiftUI

/// Мигающий индикатор «DIM» в правом нижнем углу экрана, пока включён Dim.
struct DimIndicatorView: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.45)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let pulse = sin(t * 2 * .pi / 0.9) >= 0 ? 1.0 : 0.0
            Text(verbatim: "DIM")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.red)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(Color.black.opacity(0.55))
                )
                .overlay(
                    Capsule().stroke(Color.red.opacity(0.5), lineWidth: 1)
                )
                .opacity(0.1 + 0.9 * pulse)
        }
    }
}

/// HUD громкости под иконкой меню после нажатия клавиш громкости: один фейдер выхода.
struct VolumeHUDView: View {
    let viewModel: MixerViewModel
    let outputID: UUID

    var body: some View {
        DeviceRow(viewModel: viewModel, outputID: outputID, showMute: false)
            .padding()
            .frame(width: 220)
    }
}

/// HUD выбора выхода для клавиш громкости: список выходов с отметкой текущего.
struct OutputPickerHUDView: View {
    let viewModel: MixerViewModel

    private var width: CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let maxTextWidth = viewModel.outputs
            .map { (viewModel.outputName(for: $0.id) as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        let iconWidth: CGFloat = 16
        let checkWidth: CGFloat = 12
        let spacing: CGFloat = 8
        let spacerMinWidth: CGFloat = 12
        let rowPadding: CGFloat = 16
        let outerPadding: CGFloat = 12
        return ceil(outerPadding + rowPadding + iconWidth + maxTextWidth + spacerMinWidth + checkWidth + spacing * 3)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(viewModel.outputs) { output in
                OutputPickerRow(
                    title: viewModel.outputName(for: output.id),
                    symbol: viewModel.outputSymbolName(for: output.id),
                    isSelected: output.id == viewModel.volumeKeyOutputID
                )
            }
        }
        .padding(6)
        .frame(width: width, alignment: .leading)
    }
}

private struct OutputPickerRow: View {
    let title: String
    let symbol: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .frame(width: 16)
            Text(verbatim: title)
                .font(.callout)
            Spacer(minLength: 12)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        )
    }
}

/// Тексты и иконки HUD статуса.
enum HUDStatusText {
    static func onOff(_ kind: HUDStatusKind, on: Bool) -> String {
        switch kind {
        case .dim: return on ? String(localized: "Dim On") : String(localized: "Dim Off")
        case .mono: return on ? String(localized: "Mono On") : String(localized: "Mono Off")
        case .mute: return on ? String(localized: "Mute On") : String(localized: "Mute Off")
        case .deviceConnected(let device): return String(localized: "\(device) connected")
        case .deviceDisconnected(let device): return String(localized: "\(device) disconnected")
        }
    }

    static func icon(_ kind: HUDStatusKind) -> String {
        switch kind {
        case .dim: return "speaker.wave.1.fill"
        case .mono: return "waveform"
        case .mute: return "speaker.slash.fill"
        case .deviceConnected: return "checkmark.circle.fill"
        case .deviceDisconnected: return "xmark.circle.fill"
        }
    }
}

/// HUD статуса: Dim/Mono/Mute вкл/выкл или подключение/отключение устройства.
struct StatusHUDView: View {
    let viewModel: MixerViewModel
    let kind: HUDStatusKind

    private var isOn: Bool {
        switch kind {
        case .dim: return viewModel.dimOn
        case .mono: return viewModel.monoOn
        case .mute: return viewModel.isVolumeKeyOutputMuted
        case .deviceConnected, .deviceDisconnected: return true
        }
    }

    private var tint: Color {
        switch kind {
        case .dim, .mono, .mute: return isOn ? Color.accentColor : Color.secondary
        case .deviceConnected: return Color.green
        case .deviceDisconnected: return Color.red
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: HUDStatusText.icon(kind))
                .font(.callout)
                .foregroundStyle(tint)
            Text(verbatim: HUDStatusText.onOff(kind, on: isOn))
                .font(.callout)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}

/// Статичный HUD «иконка + текст» (клиппинг, Dim/Mono/Mute с клавиатуры).
/// Показывает значение на момент создания.
struct SingleStatusHUDView: View {
    let icon: String
    let title: String
    let on: Bool
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(on ? tint : Color.secondary)
            Text(verbatim: title)
                .font(.callout)
                .foregroundStyle(on ? .primary : .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
