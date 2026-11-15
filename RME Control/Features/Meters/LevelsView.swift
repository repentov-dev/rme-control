import AppKit
import SwiftUI

struct LevelsView: View {
    private static let rowHeight: CGFloat = 8
    private static let rowGap: CGFloat = 8
    private static let padding: CGFloat = 12
    private static let columnGap: CGFloat = 8
    static let meterWidth: CGFloat = 96

    static func nameWidth(for viewModel: MixerViewModel) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 7.5, weight: .heavy),
            .kern: 0.6
        ]
        let widest = viewModel.levelInputs.reduce(CGFloat(0)) { result, input in
            let text = viewModel.inputLabel(for: input.id) as NSString
            return max(result, ceil(text.size(withAttributes: attributes).width))
        }
        return max(24, min(140, widest + 2))
    }

    static func valueWidth() -> CGFloat {
        let font = NSFont.monospacedSystemFont(ofSize: 7.5, weight: .heavy)
        let text = "00000" as NSString
        let width = text.size(withAttributes: [.font: font, .kern: 0.3]).width
        return ceil(width) + 1
    }

    static func contentSize(for viewModel: MixerViewModel) -> NSSize {
        let rows = CGFloat(max(viewModel.levelInputs.count, 1))
        let rowsHeight = rows * rowHeight + (rows - 1) * rowGap
        let width = padding * 2
            + nameWidth(for: viewModel)
            + columnGap
            + meterWidth
            + columnGap
            + valueWidth()
        let height = padding * 2 + rowsHeight
        return NSSize(width: width, height: height)
    }

    let viewModel: MixerViewModel
    var onClose: @MainActor () -> Void
    var onResize: (@MainActor (NSSize) -> Void)? = nil

    var body: some View {
        let size = Self.contentSize(for: viewModel)
        let nameWidth = Self.nameWidth(for: viewModel)
        let valueWidth = Self.valueWidth()

        VStack(spacing: Self.rowGap) {
            ForEach(viewModel.levelInputs) { input in
                row(
                    input: input,
                    nameWidth: nameWidth,
                    valueWidth: valueWidth
                )
            }
        }
        .padding(Self.padding)
        .frame(width: size.width, height: size.height)
        .panelSurface(cornerRadius: 12)
        .overlay(
            WindowDragHandle(onSecondaryClick: onClose)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
        .onChange(of: size) { _, newSize in
            onResize?(newSize)
        }
    }

    private func row(input: InputConfig, nameWidth: CGFloat, valueWidth: CGFloat) -> some View {
        let level = viewModel.micLevel(input.id)
        let phantom = viewModel.isPhantomOn(input.id)
        let fraction = min(max((level + 60) / 60, 0), 1)

        return HStack(spacing: Self.columnGap) {
            Text(viewModel.inputLabel(for: input.id))
                .font(.system(size: 7.5, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(phantom ? Color(nsColor: .systemRed) : Color.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: nameWidth, alignment: .trailing)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.07))

                GeometryReader { proxy in
                    Capsule()
                        .fill(levelColor(level))
                        .frame(width: proxy.size.width * fraction)
                        .animation(.linear(duration: 0.2), value: fraction)
                }
            }
            .frame(width: Self.meterWidth, height: Self.rowHeight)

            Text(levelText(level))
                .font(.system(size: 7.5, weight: .heavy, design: .monospaced))
                .tracking(0.3)
                .foregroundStyle(level >= 0 ? Color(nsColor: .systemRed) : Color.secondary)
                .lineLimit(1)
                .frame(width: valueWidth, alignment: .leading)
        }
        .frame(height: Self.rowHeight)
    }

    private func levelColor(_ level: Double) -> Color {
        if level > -6 { return Color(nsColor: .systemRed) }
        if level > -18 { return Color(nsColor: .systemYellow) }
        return Color(nsColor: .systemGreen)
    }

    private func levelText(_ level: Double) -> String {
        if level <= -99.9 { return "-\u{221E}" }
        return String(format: "%.1f", level)
    }
}
