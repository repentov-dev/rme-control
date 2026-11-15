import AppKit
import Observation

/// Состояние мастера первого запуска: шаги, выбранные каналы и системные параметры.
@MainActor
@Observable
final class SetupAssistantViewModel {
    enum Step: Int, CaseIterable {
        case welcome
        case channels
        case finish

        var number: Int { rawValue + 1 }
    }

    var step: Step = .welcome
    let discovery: ChannelDiscoveryViewModel

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored var onFinish: (() -> Void)?
    @ObservationIgnored var onOpenSettings: (() -> Void)?

    var accessibilityGranted = AccessibilityPermission.isGranted
    var launchAtLogin = LaunchAtLogin.isEnabled

    init(discovery: ChannelDiscoveryViewModel, settings: AppSettings) {
        self.discovery = discovery
        self.settings = settings
    }

    var totalSteps: Int { Step.allCases.count }

    var inputCount: Int { settings.inputs.count }
    var outputCount: Int { settings.outputs.count }

    // MARK: - Шаги

    func advance() {
        switch step {
        case .welcome:
            step = .channels
        case .channels:
            discovery.addSelected()
            step = .finish
        case .finish:
            finish()
        }
    }

    func back() {
        switch step {
        case .welcome:
            break
        case .channels:
            step = .welcome
        case .finish:
            step = .channels
        }
    }

    /// Пропустить выбор каналов: они останутся пустыми, их можно добавить позже.
    func skipChannels() {
        step = .finish
    }

    /// Отмечает мастер пройденным, не закрывая окно.
    func markSetupCompleted() {
        settings.completeSetup()
    }

    func finish() {
        markSetupCompleted()
        onFinish?()
    }

    // MARK: - Системные параметры

    func refreshAccessibility() {
        accessibilityGranted = AccessibilityPermission.isGranted
    }

    func openAccessibilitySettings() {
        AccessibilityPermission.openSystemSettings()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        LaunchAtLogin.setEnabled(enabled)
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    func openSettings() {
        onOpenSettings?()
    }
}
