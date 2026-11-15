import SwiftUI

/// Окно настроек с боковым меню разделов. Каждая страница отвечает за одну
/// понятную область: общие параметры, панель меню, клавиатуру, каналы,
/// подключение, веб-пульт и сведения о приложении.
struct SettingsView: View {
    let viewModel: SettingsViewModel

    @State private var page: SettingsPage? = .general
    @State private var expandedInputs = Set<UUID>()
    @State private var expandedOutputs = Set<UUID>()
    @State private var expandedSends = Set<UUID>()

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $page) {
                ForEach(SettingsPage.allCases) { item in
                    Label {
                        Text(item.title)
                    } icon: {
                        Image(systemName: item.symbol)
                    }
                    .tag(item)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .underPageBackgroundColor))
            .frame(width: 160)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(currentPage.title)
                            .font(.title2.bold())
                        Text(currentPage.subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    detail
                }
                .frame(maxWidth: 620, alignment: .leading)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 550, minHeight: 540)
        .onDisappear { viewModel.endHotkeyRecording() }
    }

    private var currentPage: SettingsPage { page ?? .general }

    @ViewBuilder
    private var detail: some View {
        switch currentPage {
        case .general:
            GeneralSettingsSection(viewModel: viewModel)
        case .menuBar:
            MenuBarSettingsSection(viewModel: viewModel)
        case .keyboard:
            HotkeysSettingsSection(viewModel: viewModel)
        case .channels:
            ChannelsSettingsSection(
                viewModel: viewModel,
                expandedOutputs: $expandedOutputs,
                expandedInputs: $expandedInputs,
                expandedSends: $expandedSends
            )
        case .connection:
            ConnectionSettingsSection(viewModel: viewModel)
        case .remote:
            RemoteSettingsSection(viewModel: viewModel)
        case .about:
            AboutSettingsSection(viewModel: viewModel)
        }
    }
}

/// Разделы окна настроек в порядке бокового меню.
enum SettingsPage: String, CaseIterable, Identifiable {
    case general
    case menuBar
    case keyboard
    case channels
    case connection
    case remote
    case about

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .general: return "General"
        case .menuBar: return "Menu Bar Panel"
        case .keyboard: return "Hotkeys"
        case .channels: return "Routing"
        case .connection: return "Connection"
        case .remote: return "Web Remote"
        case .about: return "About"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .general:
            return "Language and startup behaviour."
        case .menuBar:
            return "What appears when you click the RME Control icon in the menu bar."
        case .keyboard:
            return "Global keyboard shortcuts and the behaviour of the hardware keys."
        case .channels:
            return "Inputs, outputs and sends, their OSC addresses and routing."
        case .connection:
            return "How RME Control talks to TotalMix FX."
        case .remote:
            return "Control the mixer from a phone or another device on the same network."
        case .about:
            return "Version and developer."
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .menuBar: return "menubar.rectangle"
        case .keyboard: return "keyboard"
        case .channels: return "slider.horizontal.3"
        case .connection: return "network"
        case .remote: return "wifi"
        case .about: return "info.circle"
        }
    }
}
