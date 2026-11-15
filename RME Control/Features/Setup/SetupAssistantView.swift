import SwiftUI

/// Мастер первого запуска: приветствие, поиск каналов в TotalMix и финальная
/// проверка разрешений. Появляется только на свежей установке, когда каналов нет.
struct SetupAssistantView: View {
    let viewModel: SetupAssistantViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(minWidth: 560, minHeight: 600)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.refreshAccessibility()
        }
    }

    // MARK: - Заголовок

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "hifispeaker.2.fill")
                .font(.system(size: 22))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Set Up RME Control")
                    .font(.headline)
                Text(verbatim: "\(viewModel.step.number) / \(viewModel.totalSteps)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(verbatim: stepTitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(14)
    }

    private var stepTitle: String {
        switch viewModel.step {
        case .welcome: return String(localized: "Welcome")
        case .channels: return String(localized: "Channels")
        case .finish: return String(localized: "Ready")
        }
    }

    // MARK: - Шаги

    @ViewBuilder
    private var content: some View {
        switch viewModel.step {
        case .welcome:
            welcome
        case .channels:
            channels
        case .finish:
            finish
        }
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 12)
            Image(systemName: "hifispeaker.2.fill")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
            Text("Welcome to RME Control")
                .font(.title2.bold())
            Text("RME Control lives in the menu bar and controls your RME interface through TotalMix FX. This short assistant finds your channels and checks the permissions.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            VStack(alignment: .leading, spacing: 10) {
                featureRow("arrow.down.circle", "Find inputs and outputs automatically in TotalMix.")
                featureRow("keyboard", "Choose the shortcuts and what the hardware keys do.")
                featureRow("menubar.rectangle", "Keep RME Control in the menu bar and start it with your Mac.")
            }
            .padding(.top, 4)
            Spacer(minLength: 12)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    private func featureRow(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(verbatim: text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var channels: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Choose your channels")
                    .font(.headline)
                Text("TotalMix reported these inputs and outputs. Select the ones you want to control. You can change them later in Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            ChannelDiscoveryView(
                viewModel: viewModel.discovery,
                showsHeader: false,
                showsFooter: false
            )
        }
    }

    private var finish: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("You're all set")
                        .font(.title3.bold())
                    Text("RME Control is ready to use.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                SettingsCard("Channels", subtitle: "These channels will be available in the menu bar panel.") {
                    countRow("arrow.down.circle", "Inputs", count: viewModel.inputCount)
                    Divider()
                    countRow("speaker.wave.2", "Outputs", count: viewModel.outputCount)
                    if viewModel.inputCount == 0 && viewModel.outputCount == 0 {
                        Divider()
                        Text("No channels added yet. You can scan them later in Settings → Channels.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                SettingsCard("Accessibility", subtitle: "RME Control needs this permission to intercept the hardware keys.") {
                    HStack(spacing: 8) {
                        Image(systemName: viewModel.accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(viewModel.accessibilityGranted ? .green : .orange)
                        Text(viewModel.accessibilityGranted
                             ? LocalizedStringKey("Permission granted")
                             : LocalizedStringKey("Permission not granted"))
                            .font(.callout)
                        Spacer(minLength: 8)
                        if !viewModel.accessibilityGranted {
                            Button("Open System Settings") {
                                viewModel.openAccessibilitySettings()
                            }
                        }
                    }
                }

                SettingsCard("Startup", subtitle: "RME Control lives in the menu bar, so it can start quietly with your Mac.") {
                    SettingsToggleRow(
                        title: "Launch at login",
                        description: "Start RME Control automatically when you log in.",
                        isOn: Binding(
                            get: { viewModel.launchAtLogin },
                            set: { viewModel.setLaunchAtLogin($0) }
                        )
                    )
                }

                HStack {
                    Button("Open Settings") {
                        viewModel.openSettings()
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(16)
        }
    }

    private func countRow(_ symbol: String, _ title: LocalizedStringKey, count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(title)
                .font(.callout)
            Spacer(minLength: 8)
            Text(verbatim: "\(count)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Нижняя панель

    private var footer: some View {
        HStack(spacing: 10) {
            if viewModel.step != .welcome {
                Button("Back") {
                    viewModel.back()
                }
            }

            if viewModel.step == .channels {
                Text(String(format: String(localized: "Selected: %lld"), viewModel.discovery.selectedCount))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            switch viewModel.step {
            case .welcome:
                Button("Continue") {
                    viewModel.advance()
                }
                .keyboardShortcut(.defaultAction)

            case .channels:
                Button("Skip") {
                    viewModel.skipChannels()
                }
                Button("Continue") {
                    viewModel.advance()
                }
                .keyboardShortcut(.defaultAction)

            case .finish:
                Button("Finish") {
                    viewModel.finish()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
    }
}
