import AppKit
import SwiftUI

/// Главный поповер из строки меню: статус подключения, фейдеры выходов,
/// кнопки Speaker B / Dim / Mono и переключатели +48V/Inst входов.
/// Кнопки в шапке открывают панель уровней и окно настроек.
/// Если каналов больше, чем помещается на экран, список прокручивается;
/// при обычном числе каналов прокрутки не видно и размер не меняется.
struct VolumeControlView: View {
    let viewModel: MixerViewModel
    /// Максимальная высота всего поповера, включая отступы. Считается
    /// от видимой области экрана при открытии.
    var maxContentHeight: CGFloat = 640
    /// Прокрутка включается только когда контент не помещается; решение
    /// принимает `HudPresenter` по реальной измеренной высоте.
    var scrollable: Bool = false
    var onToggleMeters: (() -> Void)? = nil
    var onOpenSettings: (() -> Void)? = nil
    var onOpenCompressor: ((CompressorTarget) -> Void)? = nil
    var onOpenEQ: ((EQTarget) -> Void)? = nil
    var onOpenRoomEQ: ((RoomEQTarget) -> Void)? = nil

    var body: some View {
        if scrollable {
            ScrollView(.vertical) {
                content
                    // Отключаем «резиновый» отскок у самого NSScrollView:
                    // прокрутка остаётся, но контент не сдвигается и не
                    // возвращается, если тянуть за край списка.
                    .background(ScrollElasticityDisabler())
            }
            // Индикатор прокрутки не показываем: список ходит колесом/трекпадом,
            // а полоска справа только отвлекает.
            .scrollIndicators(.hidden)
            .padding()
            .frame(width: 280)
            .frame(height: maxContentHeight)
        } else {
            content
                .padding()
                .frame(width: 280)
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(verbatim: "RME Control")
                    .font(.headline)
                Spacer()
                Button {
                    onToggleMeters?()
                } label: {
                    Text("Levels")
                        .font(.callout)
                }
                .buttonStyle(.borderless)
                Button {
                    onOpenSettings?()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
            }

            if !viewModel.isConnected {
                Label(viewModel.deviceOffline ? "Device offline" : "TotalMix not found", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            Divider()

            if viewModel.inputs.isEmpty && viewModel.outputs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No channels configured yet.")
                        .font(.callout)
                    Button {
                        onOpenSettings?()
                    } label: {
                        Label("Scan channels in Settings", systemImage: "arrow.down.circle")
                            .font(.callout)
                    }
                    .buttonStyle(.borderless)
                }
                .foregroundStyle(.secondary)
            }

            ForEach(viewModel.outputs.filter(\.showInMain)) { output in
                DeviceRow(
                    viewModel: viewModel,
                    outputID: output.id,
                    showMute: viewModel.showMuteButtons,
                    onOpenEQ: viewModel.showOutputEQ ? onOpenEQ.map { open in
                        { open(EQTarget(bus: .output, id: output.id)) }
                    } : nil,
                    onOpenCompressor: viewModel.showOutputCompressor ? onOpenCompressor.map { open in
                        { open(CompressorTarget(bus: .output, id: output.id)) }
                    } : nil,
                    onOpenRoomEQ: viewModel.showOutputRoomEQ ? onOpenRoomEQ.map { open in
                        {
                            guard let target = viewModel.roomEQTarget(for: output.id) else { return }
                            open(target)
                        }
                    } : nil
                )
            }

            ForEach(viewModel.visibleSends) { send in
                SendRow(viewModel: viewModel, sendID: send.id)
            }

            if viewModel.showSpeakerB {
                Divider()
                MomentaryOscButton(label: "Speaker B", isOn: viewModel.speakerBOn, isEnabled: viewModel.isConnected) {
                    viewModel.toggleSpeakerB()
                }
            }

            if viewModel.showDim || viewModel.showMono {
                HStack(spacing: 6) {
                    if viewModel.showDim {
                        MomentaryOscButton(label: "Dim", isOn: viewModel.dimOn, isEnabled: viewModel.isConnected) {
                            viewModel.toggleDim()
                        }
                    }
                    if viewModel.showMono {
                        MomentaryOscButton(label: "Mono", isOn: viewModel.monoOn, isEnabled: viewModel.isConnected) {
                            viewModel.toggleMono()
                        }
                    }
                }
            }

            let popoverRows = viewModel.popoverInputRows
            if !popoverRows.isEmpty {
                Divider()
                ForEach(popoverRows, id: \.self) { row in
                    HStack(alignment: .top, spacing: 6) {
                        ForEach(row, id: \.self) { id in
                            InputControlColumn(
                                viewModel: viewModel,
                                inputID: id,
                                onOpenEQ: { inputID in
                                    onOpenEQ?(EQTarget(bus: .input, id: inputID))
                                },
                                onOpenCompressor: { inputID in
                                    onOpenCompressor?(CompressorTarget(bus: .input, id: inputID))
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}


/// Находит enclosing `NSScrollView` и выключает у него эластичный отскок.
/// SwiftUI не даёт сказать это напрямую, а `.scrollBounceBehavior` не убирает
/// отскок на краях уже прокручиваемого списка. Настройка повторяется при
/// попадании в иерархию и на layout: SwiftUI может пересоздать ScrollView,
/// когда меняется содержимое поповера.
private struct ScrollElasticityDisabler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ScrollElasticityDisablerView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class ScrollElasticityDisablerView: NSView {
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        disableElasticity()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        disableElasticity()
    }

    override func layout() {
        super.layout()
        disableElasticity()
    }

    private func disableElasticity() {
        var candidate = superview
        while let current = candidate {
            if let scrollView = current as? NSScrollView {
                scrollView.verticalScrollElasticity = .none
                scrollView.horizontalScrollElasticity = .none
                scrollView.hasVerticalScroller = false
                scrollView.hasHorizontalScroller = false
                return
            }
            candidate = current.superview
        }
    }
}
