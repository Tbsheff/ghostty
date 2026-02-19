import SwiftUI

// MARK: - Settings Form Container

/// Replaces `.padding()` wrapper on each settings tab.
/// Provides a scrollable themed container with consistent background.
struct SettingsFormContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.adaptiveTheme) private var theme

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: AdaptiveTheme.spacing16) {
                content()
            }
            .padding(AdaptiveTheme.spacing16)
        }
        .background(theme.backgroundC)
    }
}

// MARK: - Themed Section

/// Replaces SwiftUI `Section` with AdaptiveTheme-styled header and divider.
struct ThemedSection<Content: View>: View {
    let header: String
    @ViewBuilder let content: () -> Content
    @Environment(\.adaptiveTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: AdaptiveTheme.spacing8) {
            Text(header.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(theme.textMutedC)
                .tracking(0.5)
                .padding(.horizontal, AdaptiveTheme.spacing12)

            VStack(alignment: .leading, spacing: AdaptiveTheme.spacing8) {
                content()
            }
            .padding(.horizontal, AdaptiveTheme.spacing12)
            .padding(.vertical, AdaptiveTheme.spacing8)

            Rectangle()
                .fill(theme.borderSubtleC)
                .frame(height: 1)
        }
    }
}

// MARK: - Setting Row

/// Consistent label + optional description + trailing control layout.
struct SettingRow<Control: View>: View {
    let label: String
    var description: String? = nil
    @ViewBuilder let control: () -> Control
    @Environment(\.adaptiveTheme) private var theme

    var body: some View {
        HStack(alignment: .center, spacing: AdaptiveTheme.spacing10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(theme.textPrimaryC)
                if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(theme.textSecondaryC)
                }
            }
            Spacer()
            control()
        }
        .padding(.vertical, AdaptiveTheme.spacing4)
    }
}

// MARK: - Themed Toggle

/// Replaces SwiftUI `Toggle` with themed row layout and accent tint.
struct ThemedToggle: View {
    let label: String
    var description: String? = nil
    @Binding var isOn: Bool
    @Environment(\.adaptiveTheme) private var theme

    var body: some View {
        SettingRow(label: label, description: description) {
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .tint(theme.accentC)
                .labelsHidden()
        }
    }
}

// MARK: - Themed Slider

/// Replaces bare `Slider` with label, value badge, and theme tint.
struct ThemedSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var format: String = "%.0f"
    var suffix: String = ""
    var description: String? = nil
    @Environment(\.adaptiveTheme) private var theme

    private var displayValue: String {
        String(format: format, value) + suffix
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AdaptiveTheme.spacing6) {
            HStack {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(theme.textPrimaryC)
                if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(theme.textSecondaryC)
                }
                Spacer()
                Text(displayValue)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(theme.textPrimaryC)
                    .padding(.horizontal, AdaptiveTheme.spacing6)
                    .padding(.vertical, AdaptiveTheme.spacing4)
                    .background(
                        RoundedRectangle(cornerRadius: AdaptiveTheme.radiusSmall, style: .continuous)
                            .fill(theme.surfaceElevatedC)
                    )
            }
            Slider(value: $value, in: range, step: step)
                .tint(theme.accentC)
        }
        .padding(.vertical, AdaptiveTheme.spacing4)
    }
}

// MARK: - Themed Text Field

/// Replaces bare `TextField` with themed background, border, and focus ring.
struct ThemedTextField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var description: String? = nil
    var errorMessage: String? = nil
    var isValid: Bool = true
    @Environment(\.adaptiveTheme) private var theme
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AdaptiveTheme.spacing6) {
            SettingRow(label: label, description: description) {
                HStack(spacing: AdaptiveTheme.spacing6) {
                    TextField(placeholder, text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($isFocused)
                        .padding(AdaptiveTheme.spacing8)
                        .background(
                            RoundedRectangle(cornerRadius: AdaptiveTheme.radiusSmall, style: .continuous)
                                .fill(theme.backgroundC)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AdaptiveTheme.radiusSmall, style: .continuous)
                                .stroke(
                                    isFocused ? theme.accentC : theme.borderSubtleC,
                                    lineWidth: 1
                                )
                        )
                        .animation(.linear(duration: AdaptiveTheme.animationFast), value: isFocused)

                    if !text.isEmpty {
                        Image(systemName: isValid ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundColor(isValid ? theme.successC : theme.dangerC)
                            .font(.system(size: 12))
                    }
                }
                .frame(maxWidth: 200)
            }

            if let errorMessage {
                HStack(spacing: AdaptiveTheme.spacing4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    Text(errorMessage)
                        .font(.caption)
                }
                .foregroundColor(theme.dangerC)
                .padding(.leading, AdaptiveTheme.spacing12)
            }
        }
    }
}

// MARK: - Themed Picker

/// Replaces `Picker` in Form with themed row layout.
struct ThemedPicker<SelectionValue: Hashable>: View {
    let label: String
    @Binding var selection: SelectionValue
    var description: String? = nil
    var style: PickerDisplayStyle = .menu
    let content: () -> AnyView
    @Environment(\.adaptiveTheme) private var theme

    enum PickerDisplayStyle {
        case menu
        case segmented
    }

    var body: some View {
        switch style {
        case .menu:
            SettingRow(label: label, description: description) {
                Picker("", selection: $selection) {
                    content()
                }
                .labelsHidden()
                .frame(maxWidth: 180)
            }
        case .segmented:
            VStack(alignment: .leading, spacing: AdaptiveTheme.spacing6) {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(theme.textPrimaryC)
                if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(theme.textSecondaryC)
                }
                Picker("", selection: $selection) {
                    content()
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.vertical, AdaptiveTheme.spacing4)
        }
    }
}

/// Convenience initializer for string-tagged pickers (most common case).
extension ThemedPicker where SelectionValue == String {
    init(
        label: String,
        selection: Binding<String>,
        description: String? = nil,
        style: PickerDisplayStyle = .menu,
        options: [(String, String)]
    ) {
        self.label = label
        self._selection = selection
        self.description = description
        self.style = style
        self.content = {
            AnyView(ForEach(options, id: \.1) { option in
                Text(option.0).tag(option.1)
            })
        }
    }
}

// MARK: - Auto Save Footer

/// Replaces repeated "Changes are saved automatically..." section.
struct AutoSaveFooter: View {
    @Environment(\.adaptiveTheme) private var theme

    var body: some View {
        Text("Changes are saved automatically to your Ghostty config file.")
            .font(.caption)
            .foregroundColor(theme.textMutedC)
            .padding(.top, AdaptiveTheme.spacing8)
    }
}

// MARK: - Sync Status Bar

/// Bottom status bar showing sync state. Hidden when idle.
struct SyncStatusBar: View {
    @ObservedObject var settingsSync: SettingsSync
    @Environment(\.adaptiveTheme) private var theme

    private var isVisible: Bool {
        switch settingsSync.syncStatus {
        case .idle: return false
        case .syncing, .success, .error: return true
        }
    }

    var body: some View {
        if isVisible {
            HStack(spacing: AdaptiveTheme.spacing8) {
                statusContent
                Spacer()
                if let lastSync = settingsSync.lastSyncTime {
                    Text("Last sync: \(lastSync.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundColor(theme.textMutedC)
                }
            }
            .padding(.horizontal, AdaptiveTheme.spacing12)
            .padding(.vertical, AdaptiveTheme.spacing8)
            .background(theme.surfaceElevatedC)
            .overlay(
                Rectangle()
                    .fill(theme.borderSubtleC)
                    .frame(height: 1),
                alignment: .top
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        switch settingsSync.syncStatus {
        case .idle:
            EmptyView()
        case .syncing:
            ProgressView()
                .scaleEffect(0.7, anchor: .center)
            Text("Syncing...")
                .font(.caption)
                .foregroundColor(theme.textSecondaryC)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(theme.successC)
                .font(.system(size: 11))
            Text("Saved")
                .font(.caption)
                .foregroundColor(theme.successC)
        case .error(let message):
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(theme.dangerC)
                .font(.system(size: 11))
            Text(message)
                .font(.caption)
                .foregroundColor(theme.dangerC)
        }
    }
}
