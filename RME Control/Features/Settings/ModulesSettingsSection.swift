import AppKit
import SwiftUI

/// Настройки → Модули: что скачано, сколько занимает места и что можно обновить.
struct ModulesSettingsSection: View {
    @State private var module = MeasurementModule.shared

    var body: some View {
        SettingsCard("Measurement module",
                     subtitle: "Room EQ measurement: roomeq and sotf-capture. Downloaded once and stored outside the app.") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(tint.opacity(0.12)))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.callout)
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)
                    controls
                }
            }
        }
        .task { await module.checkForUpdates() }
    }

    private var installed: Bool { module.phase == .installed }

    private var icon: String {
        switch module.phase {
        case .installed: return "shippingbox.fill"
        case .downloading: return "arrow.down.circle"
        default: return "shippingbox"
        }
    }

    private var tint: Color {
        switch module.phase {
        case .installed: return .green
        case .failed: return .orange
        default: return .secondary
        }
    }

    private var title: String {
        switch module.phase {
        case .installed:
            return String(format: String(localized: "Measurement module %@"), MeasurementModule.version)
        case .downloading(let progress):
            return String(format: String(localized: "Downloading… %ld%%"), Int(progress * 100))
        case .failed:
            return String(localized: "The measurement module did not install.")
        case .missing:
            return String(localized: "The measurement module is not installed.")
        }
    }

    private var detail: String {
        if let status = checkStatus, module.phase == .installed {
            return status
        }
        switch module.phase {
        case .installed:
            let size = ByteCountFormatter.string(fromByteCount: module.sizeBytes, countStyle: .file)
            if let update = module.updateVersion {
                return String(format: String(localized: "Version %@ is available — %@ now installed."),
                              update, size)
            }
            return String(format: String(localized: "Installed, %@ on disk."), size)
        case .downloading:
            return String(localized: "Downloading from GitHub.")
        case .failed(let message):
            return message
        case .missing:
            return String(localized: "Room EQ asks for it before the first measurement.")
        }
    }

    /// Ответ на ручную проверку обновлений: он важнее обычного описания.
    private var checkStatus: String? {
        guard let result = module.checkResult else { return nil }
        switch result {
        case .upToDate:
            return String(format: String(localized: "Version %@ is the latest."),
                          MeasurementModule.installedVersion)
        case .available:
            guard let version = module.updateVersion else { return nil }
            return String(format: String(localized: "Version %@ is available."), version)
        case .failed:
            return String(localized: "Could not check for updates.")
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch module.phase {
        case .installed:
            if let update = module.updateVersion {
                Button {
                    Task { await module.installUpdate() }
                } label: {
                    Label(String(format: String(localized: "Update to %@"), update),
                          systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            Button {
                Task { await module.checkForUpdates(force: true) }
            } label: {
                if module.isChecking {
                    ProgressView().controlSize(.mini)
                } else {
                    Label("Check for updates", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .controlSize(.small)
            .disabled(module.isChecking)
            .help("Check the module release on GitHub")

            Button("Delete") { module.remove() }
                .controlSize(.small)
        case .downloading:
            ProgressView().controlSize(.small)
        case .failed, .missing:
            HStack(spacing: 6) {
                Button("Download") { Task { await module.download() } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("From file…") { pickArchive() }
                    .controlSize(.small)
            }
        }
    }

    /// Запасной путь, пока релиза нет: поставить модуль из локального архива.
    private func pickArchive() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        FilePanel.present(panel) { url in
            guard let url else { return }
            module.install(fromLocalArchive: url)
        }
    }
}
