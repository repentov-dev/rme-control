import SwiftUI

/// Карточка-секция окна настроек: заголовок, необязательное пояснение и содержимое.
/// Занимает всю ширину колонки, поэтому настройки читаются сверху вниз без «узких» блоков.
struct SettingsCard<Content: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    let content: Content

    init(_ title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

/// Переключатель с заголовком и необязательным пояснением.
struct SettingsToggleRow: View {
    let title: LocalizedStringKey
    var description: LocalizedStringKey? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Строка «заголовок — выпадающий список» с пояснением под заголовком.
struct SettingsPickerRow<Selection: Hashable, Content: View>: View {
    let title: LocalizedStringKey
    var description: LocalizedStringKey? = nil
    @Binding var selection: Selection
    private let content: Content

    init(
        _ title: LocalizedStringKey,
        description: LocalizedStringKey? = nil,
        selection: Binding<Selection>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.description = description
        self._selection = selection
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            Picker("", selection: $selection) {
                content
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 160)
        }
    }
}

/// Сворачиваемая карточка канала: название, OSC-адрес и поля редактирования.
/// Кнопка удаления живёт в шапке, поэтому доступна и без раскрытия карточки.
struct ExpandableChannelCard<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isExpanded: Bool
    var onDelete: (() -> Void)? = nil
    var deleteHelp: LocalizedStringKey = "Delete channel"
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        isExpanded: Binding<Bool>,
        onDelete: (() -> Void)? = nil,
        deleteHelp: LocalizedStringKey = "Delete channel",
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self._isExpanded = isExpanded
        self.onDelete = onDelete
        self.deleteHelp = deleteHelp
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: title)
                                .font(.callout)
                                .lineLimit(1)
                            if let subtitle {
                                Text(verbatim: subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if let onDelete {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help(deleteHelp)
                }
            }
            .padding(8)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    content
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.075))
        )
    }
}

/// Поле ввода с подписью слева (имя/адрес канала в настройках).
struct LabeledTextField: View {
    let caption: LocalizedStringKey
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Text(caption)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
        }
    }
}

/// Значение, вычисляемое приложением (например, адрес индикатора уровня канала).
struct LabeledValue: View {
    let caption: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(caption)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value.isEmpty ? "—" : value)
                .font(.callout)
                .monospaced()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: 200, alignment: .trailing)
                .textSelection(.enabled)
        }
    }
}
