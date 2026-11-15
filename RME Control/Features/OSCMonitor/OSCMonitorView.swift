import SwiftUI

/// Окно OSC-монитора: живой журнал всех входящих и исходящих OSC-сообщений.
/// Запись можно выключить переключателем, журнал — очистить кнопкой.
struct OSCMonitorView: View {
    @Bindable var monitor: OSCMonitor

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Toggle("Enabled", isOn: $monitor.isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Spacer()
                Text(verbatim: "\(monitor.activities.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("Clear") {
                    monitor.clear()
                }
                .disabled(monitor.activities.isEmpty)
            }
            .padding(10)

            Divider()

            content
        }
        .frame(minWidth: 480, minHeight: 260)
    }

    @ViewBuilder
    private var content: some View {
        if monitor.activities.isEmpty {
            Text(monitor.isEnabled ? "Waiting for OSC messages…" : "Monitoring is off")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(monitor.activities.reversed()) { activity in
                        OSCMonitorRow(activity: activity)
                        Divider()
                    }
                }
            }
        }
    }
}

private struct OSCMonitorRow: View {
    let activity: OSCActivity

    private var isIncoming: Bool { activity.direction == .incoming }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(activity.date, format: .dateTime.hour().minute().second())
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Image(systemName: isIncoming ? "arrow.down.left" : "arrow.up.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(isIncoming ? Color.blue : Color.green)
                .frame(width: 14)
            Text(activity.address)
                .font(.caption.monospaced())
                .textSelection(.enabled)
            Spacer(minLength: 8)
            Text(activity.value)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
