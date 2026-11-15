import AppKit
import SwiftUI

/// Кнопка записи горячей клавиши: нажали — слушаем следующее нажатие и сохраняем
/// его как комбинацию действия. Esc отменяет запись, Delete убирает комбинацию.
struct HotkeyRecorderButton: View {
    let viewModel: SettingsViewModel
    let action: HotkeyAction

    @State private var monitor: Any?

    private var hotkey: Hotkey { viewModel.hotkey(for: action) }
    private var isRecording: Bool { viewModel.recordingAction == action }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            } label: {
                Text(verbatim: isRecording ? String(localized: "Press keys…") : hotkey.displayString)
                    .font(.callout.monospaced())
                    .frame(minWidth: 92)
            }
            .buttonStyle(.bordered)
            .tint(isRecording ? .accentColor : nil)
            .disabled(viewModel.recordingAction != nil && !isRecording)
            .help(isRecording
                  ? "Press the new shortcut, or Esc to cancel."
                  : "Click, then press the shortcut you want to use.")

            if hotkey.isAssigned && !isRecording {
                Button {
                    viewModel.clearHotkey(for: action)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove shortcut")
            }
        }
        .onDisappear { stopRecording() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            // Ушли в другое приложение — запись отменяем, иначе глобальные
            // комбинации остались бы выключенными.
            if isRecording { stopRecording() }
        }
    }

    private func startRecording() {
        guard monitor == nil else { return }
        viewModel.beginHotkeyRecording(for: action)
        // Локальный монитор видит нажатие раньше окна, поэтому комбинация
        // не срабатывает как кнопка интерфейса и не уходит дальше в приложение.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { handle(event) }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        viewModel.endHotkeyRecording()
    }

    private func handle(_ event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc — отменить запись
            stopRecording()
        case 51, 117: // Delete / Forward Delete — убрать комбинацию
            viewModel.clearHotkey(for: action)
            stopRecording()
        default:
            guard let hotkey = Hotkey.capture(from: event) else {
                NSSound.beep()
                return
            }
            viewModel.assignHotkey(hotkey, to: action)
            stopRecording()
        }
    }
}
