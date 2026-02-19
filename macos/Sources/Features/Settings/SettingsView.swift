import SwiftUI
import AppKit

// MARK: - Setting Model

struct SettingItem: Identifiable {
    let id: String
    let title: String
    let description: String
    let category: String
    let keywords: [String]
}

let settingsData: [SettingItem] = [
    SettingItem(
        id: "font-settings",
        title: "Font Settings",
        description: "Configure font family and size for terminals",
        category: "general",
        keywords: ["font", "font family", "font size", "typeface"]
    ),
    SettingItem(
        id: "working-directory",
        title: "Working Directory",
        description: "Set default directory for new terminals",
        category: "general",
        keywords: ["working directory", "path", "directory", "cwd"]
    ),
    SettingItem(
        id: "appearance-settings",
        title: "Appearance Settings",
        description: "Adjust theme, cursor style, and transparency",
        category: "appearance",
        keywords: ["theme", "cursor", "opacity", "blur", "transparency", "background"]
    ),
    SettingItem(
        id: "cursor-settings",
        title: "Cursor Settings",
        description: "Configure cursor appearance and behavior",
        category: "appearance",
        keywords: ["cursor", "blink", "style", "block", "underline", "bar"]
    ),
    SettingItem(
        id: "behavior-settings",
        title: "Behavior Settings",
        description: "Configure scrollback, clipboard, and mouse behavior",
        category: "behavior",
        keywords: ["scroll", "copy", "clipboard", "mouse", "paste", "selection"]
    ),
    SettingItem(
        id: "mouse-settings",
        title: "Mouse Settings",
        description: "Control mouse interaction and focus behavior",
        category: "behavior",
        keywords: ["mouse", "focus", "right click", "selection"]
    ),
    SettingItem(
        id: "markdown-settings",
        title: "Markdown Settings",
        description: "Configure markdown rendering and syntax highlighting",
        category: "markdown",
        keywords: ["markdown", "preview", "code theme", "typography", "rendering", "syntax"]
    ),
]

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case appearance
    case behavior
    case markdown
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .behavior: return "Behavior"
        case .markdown: return "Markdown"
        case .advanced: return "Advanced"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gear"
        case .appearance: return "paintbrush"
        case .behavior: return "slider.horizontal.3"
        case .markdown: return "doc.richtext"
        case .advanced: return "gearshape.2"
        }
    }
}

struct SettingsView: View {
    @State private var searchText: String = ""
    @State private var searchCategory: String = "all"
    @State private var selectedTab: SettingsTab? = .general
    @ObservedObject private var settingsSync = SettingsSync.shared
    @Environment(\.adaptiveTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            // Conflict notice (only when external changes detected)
            ExternalConflictNotice(settingsSync: settingsSync) {
                settingsSync.loadFromConfigFile()
            }
            .padding(.horizontal, AdaptiveTheme.spacing10)
            .padding(.top, AdaptiveTheme.spacing8)

            // Search bar with category filter
            VStack(spacing: AdaptiveTheme.spacing8) {
                SidebarSearchField(
                    text: $searchText,
                    placeholder: "Search settings..."
                )
                .help("Press Cmd+F to focus search")

                if !searchText.isEmpty {
                    Picker("Category", selection: $searchCategory) {
                        Text("All").tag("all")
                        Text("General").tag("general")
                        Text("Appearance").tag("appearance")
                        Text("Behavior").tag("behavior")
                        Text("Markdown").tag("markdown")
                    }
                    .pickerStyle(.segmented)
                    .font(.system(size: 11))
                }
            }
            .padding(AdaptiveTheme.spacing10)
            .background(theme.surfaceElevatedC)
            .overlay(
                Rectangle()
                    .fill(theme.borderSubtleC)
                    .frame(height: 1),
                alignment: .bottom
            )

            // Content area
            if searchText.isEmpty {
                HStack(spacing: 0) {
                    SettingsSidebar(selection: $selectedTab)
                        .frame(width: 160)

                    Rectangle()
                        .fill(theme.borderSubtleC)
                        .frame(width: 1)

                    selectedSettingsView
                }
            } else {
                SearchableSettingsView(searchText: searchText, category: searchCategory)
            }

            // Bottom sync status bar
            SyncStatusBar(settingsSync: settingsSync)
                .animation(.spring(response: AdaptiveTheme.springResponse, dampingFraction: AdaptiveTheme.springDamping), value: settingsSync.syncStatus.isActive)
        }
        .frame(minWidth: 520, minHeight: 440)
        .adaptiveThemeFromSystem()
        .onAppear {
            _ = SettingsSync.shared
        }
        .keyboardShortcut("f", modifiers: .command)
    }

    @ViewBuilder
    private var selectedSettingsView: some View {
        switch selectedTab ?? .general {
        case .general:
            GeneralSettingsView()
        case .appearance:
            AppearanceSettingsView()
        case .behavior:
            BehaviorSettingsView()
        case .markdown:
            MarkdownSettingsView()
        case .advanced:
            AdvancedSettingsView()
        }
    }
}

// MARK: - SyncStatus Helpers

extension SettingsSync.SyncStatus {
    var isActive: Bool {
        switch self {
        case .idle: return false
        case .syncing, .success, .error: return true
        }
    }
}

// MARK: - Searchable Settings

struct SearchableSettingsView: View {
    let searchText: String
    let category: String

    @Environment(\.adaptiveTheme) private var theme

    private var filteredSettings: [SettingItem] {
        settingsData.filter { setting in
            if category != "all" && setting.category != category {
                return false
            }

            let titleMatch = setting.title.localizedCaseInsensitiveContains(searchText)
            let descriptionMatch = setting.description.localizedCaseInsensitiveContains(searchText)
            let keywordMatch = setting.keywords.contains { keyword in
                keyword.localizedCaseInsensitiveContains(searchText)
            }

            return titleMatch || descriptionMatch || keywordMatch
        }
    }

    private func categoryColor(for settingCategory: String) -> Color {
        switch settingCategory {
        case "general":
            return theme.accentC.opacity(0.2)
        case "appearance":
            return Color.purple.opacity(0.2)
        case "behavior":
            return Color.orange.opacity(0.2)
        case "markdown":
            return Color.green.opacity(0.2)
        default:
            return theme.surfaceHoverC
        }
    }

    var body: some View {
        ScrollView {
            if filteredSettings.isEmpty {
                SidebarEmptyState(
                    icon: "magnifyingglass",
                    message: "No settings found",
                    detail: "Try adjusting your search"
                )
                .padding(40)
            } else {
                VStack(alignment: .leading, spacing: AdaptiveTheme.spacing12) {
                    ForEach(filteredSettings) { setting in
                        VStack(alignment: .leading, spacing: AdaptiveTheme.spacing8) {
                            HStack {
                                Text(setting.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(theme.textPrimaryC)
                                Spacer()
                                Text(setting.category.uppercased())
                                    .font(.system(size: 10, weight: .medium))
                                    .tracking(0.5)
                                    .padding(.horizontal, AdaptiveTheme.spacing8)
                                    .padding(.vertical, AdaptiveTheme.spacing4)
                                    .background(categoryColor(for: setting.category))
                                    .clipShape(Capsule())
                            }
                            Text(setting.description)
                                .font(.caption)
                                .foregroundColor(theme.textSecondaryC)
                        }
                        .padding(AdaptiveTheme.spacing10)
                        .background(
                            RoundedRectangle(cornerRadius: AdaptiveTheme.radiusMedium, style: .continuous)
                                .fill(theme.surfaceElevatedC)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AdaptiveTheme.radiusMedium, style: .continuous)
                                .stroke(theme.borderSubtleC, lineWidth: 1)
                        )
                    }
                }
                .padding(AdaptiveTheme.spacing16)
            }
        }
    }
}

// MARK: - Sidebar Navigation

struct SettingsSidebar: View {
    @Binding var selection: SettingsTab?
    @Environment(\.adaptiveTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(spacing: AdaptiveTheme.spacing4) {
                ForEach(SettingsTab.allCases) { tab in
                    SidebarIconRow(
                        icon: tab.systemImage,
                        title: tab.title,
                        isSelected: selection == tab,
                        iconColor: selection == tab ? theme.accentC : nil,
                        onTap: { selection = tab }
                    )
                }
            }
            .padding(.vertical, AdaptiveTheme.spacing8)
            .padding(.horizontal, AdaptiveTheme.spacing6)
        }
        .background(theme.backgroundC)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @AppStorage("general.fontFamily") private var fontFamily = ""
    @AppStorage("general.fontSize") private var fontSize: Double = 13
    @AppStorage("general.workingDirectoryMode") private var workingDirectoryMode = "inherit"
    @AppStorage("general.workingDirectory") private var workingDirectory = ""
    @AppStorage("general.inheritWindowWorkingDirectory") private var inheritWindowWorkingDirectory = true
    @AppStorage("general.inheritTabWorkingDirectory") private var inheritTabWorkingDirectory = true
    @AppStorage("general.inheritSplitWorkingDirectory") private var inheritSplitWorkingDirectory = true
    @AppStorage("general.inheritFontSize") private var inheritFontSize = true

    @Environment(\.adaptiveTheme) private var theme

    private var isFontFamilyValid: Bool {
        fontFamily.isEmpty || !fontFamily.contains("/")
    }

    private var fontFamilyErrorMessage: String? {
        guard !fontFamily.isEmpty && !isFontFamilyValid else { return nil }
        return "Font family cannot contain path separators"
    }

    var body: some View {
        SettingsFormContainer {
            ThemedSection(header: "Font") {
                ThemedTextField(
                    label: "Font Family",
                    text: $fontFamily,
                    placeholder: "e.g. JetBrains Mono",
                    errorMessage: fontFamilyErrorMessage,
                    isValid: isFontFamilyValid
                )

                ThemedSlider(
                    label: "Font Size",
                    value: $fontSize,
                    range: 8...32,
                    step: 1,
                    format: "%.0f",
                    suffix: "pt"
                )

                ThemedToggle(
                    label: "Inherit font size",
                    description: "Apply to new windows",
                    isOn: $inheritFontSize
                )
            }

            ThemedSection(header: "Working Directory") {
                ThemedPicker(
                    label: "Default Directory",
                    selection: $workingDirectoryMode,
                    style: .segmented,
                    options: [("Inherit", "inherit"), ("Custom", "custom")]
                )

                if workingDirectoryMode == "custom" {
                    ThemedTextField(
                        label: "Path",
                        text: $workingDirectory,
                        placeholder: "/Users/..."
                    )
                }

                ThemedToggle(label: "Inherit for new windows", isOn: $inheritWindowWorkingDirectory)
                ThemedToggle(label: "Inherit for new tabs", isOn: $inheritTabWorkingDirectory)
                ThemedToggle(label: "Inherit for new splits", isOn: $inheritSplitWorkingDirectory)
            }

            AutoSaveFooter()
        }
    }
}

// MARK: - Appearance Settings

struct AppearanceSettingsView: View {
    @AppStorage("appearance.theme") private var themeName = ""
    @AppStorage("appearance.windowTheme") private var windowTheme = "auto"
    @AppStorage("appearance.cursorStyle") private var cursorStyle = "block"
    @AppStorage("appearance.cursorBlink") private var cursorBlink = "auto"
    @AppStorage("appearance.backgroundOpacity") private var backgroundOpacity: Double = 1.0
    @AppStorage("appearance.backgroundBlurMode") private var backgroundBlurMode = "off"
    @AppStorage("appearance.backgroundBlurRadius") private var backgroundBlurRadius: Double = 20
    @AppStorage("appearance.unfocusedSplitOpacity") private var unfocusedSplitOpacity: Double = 0.7

    @Environment(\.adaptiveTheme) private var theme

    var body: some View {
        SettingsFormContainer {
            ThemedSection(header: "Theme") {
                ThemedTextField(
                    label: "Theme",
                    text: $themeName,
                    placeholder: "e.g. Rose Pine"
                )

                ThemedPicker(
                    label: "Window Theme",
                    selection: $windowTheme,
                    options: [
                        ("Auto", "auto"),
                        ("System", "system"),
                        ("Light", "light"),
                        ("Dark", "dark"),
                        ("Ghostty", "ghostty"),
                    ]
                )

                Text("Use light/dark pairs like \"light:Rose Pine Dawn,dark:Rose Pine\".")
                    .font(.caption)
                    .foregroundColor(theme.textSecondaryC)
                    .padding(.vertical, AdaptiveTheme.spacing4)
            }

            ThemedSection(header: "Cursor") {
                ThemedPicker(
                    label: "Style",
                    selection: $cursorStyle,
                    options: [
                        ("Block", "block"),
                        ("Underline", "underline"),
                        ("Bar", "bar"),
                        ("Hollow Block", "block_hollow"),
                    ]
                )

                ThemedPicker(
                    label: "Blink",
                    selection: $cursorBlink,
                    options: [
                        ("Auto", "auto"),
                        ("On", "true"),
                        ("Off", "false"),
                    ]
                )
            }

            ThemedSection(header: "Transparency") {
                ThemedSlider(
                    label: "Background Opacity",
                    value: $backgroundOpacity,
                    range: 0.0...1.0,
                    step: 0.05,
                    format: "%.2f"
                )

                ThemedPicker(
                    label: "Background Blur",
                    selection: $backgroundBlurMode,
                    options: [
                        ("Off", "off"),
                        ("Standard", "standard"),
                        ("Glass (Regular)", "macos-glass-regular"),
                        ("Glass (Clear)", "macos-glass-clear"),
                        ("Custom", "custom"),
                    ]
                )

                if backgroundBlurMode == "custom" {
                    ThemedSlider(
                        label: "Blur Radius",
                        value: $backgroundBlurRadius,
                        range: 0...50,
                        step: 1,
                        format: "%.0f"
                    )
                }

                Text("Changing background opacity or blur may require restarting Ghostty on macOS.")
                    .font(.caption)
                    .foregroundColor(theme.textSecondaryC)
                    .padding(.vertical, AdaptiveTheme.spacing4)
            }

            ThemedSection(header: "Splits") {
                ThemedSlider(
                    label: "Unfocused Split Opacity",
                    value: $unfocusedSplitOpacity,
                    range: 0.15...1.0,
                    step: 0.05,
                    format: "%.2f"
                )
            }

            AutoSaveFooter()
        }
    }
}

// MARK: - Behavior Settings

struct BehaviorSettingsView: View {
    @AppStorage("behavior.scrollbackLimitMB") private var scrollbackLimitMB: Double = 10
    @AppStorage("behavior.copyOnSelect") private var copyOnSelect = "true"
    @AppStorage("behavior.clipboardPasteProtection") private var clipboardPasteProtection = true
    @AppStorage("behavior.mouseHideWhileTyping") private var mouseHideWhileTyping = false
    @AppStorage("behavior.focusFollowsMouse") private var focusFollowsMouse = false
    @AppStorage("behavior.rightClickAction") private var rightClickAction = "context-menu"

    @Environment(\.adaptiveTheme) private var theme

    var body: some View {
        SettingsFormContainer {
            ThemedSection(header: "Scrollback") {
                ThemedSlider(
                    label: "Limit",
                    value: $scrollbackLimitMB,
                    range: 1...500,
                    step: 1,
                    format: "%.0f",
                    suffix: " MB"
                )

                Text("Applies per terminal surface and affects new windows/tabs only.")
                    .font(.caption)
                    .foregroundColor(theme.textSecondaryC)
                    .padding(.vertical, AdaptiveTheme.spacing4)
            }

            ThemedSection(header: "Clipboard") {
                ThemedPicker(
                    label: "Copy on Select",
                    selection: $copyOnSelect,
                    options: [
                        ("Off", "false"),
                        ("On", "true"),
                        ("Clipboard + Selection", "clipboard"),
                    ]
                )

                ThemedToggle(label: "Paste protection", isOn: $clipboardPasteProtection)
            }

            ThemedSection(header: "Mouse") {
                ThemedToggle(label: "Hide while typing", isOn: $mouseHideWhileTyping)
                ThemedToggle(label: "Focus follows mouse", isOn: $focusFollowsMouse)

                ThemedPicker(
                    label: "Right Click",
                    selection: $rightClickAction,
                    options: [
                        ("Context Menu", "context-menu"),
                        ("Paste", "paste"),
                        ("Copy", "copy"),
                        ("Copy or Paste", "copy-or-paste"),
                        ("Ignore", "ignore"),
                    ]
                )
            }

            AutoSaveFooter()
        }
    }
}

// MARK: - Advanced Settings

struct AdvancedSettingsView: View {
    @Environment(\.adaptiveTheme) private var theme

    var body: some View {
        SettingsFormContainer {
            Text("Advanced settings coming soon")
                .font(.system(size: 13))
                .foregroundColor(theme.textMutedC)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

// MARK: - Preview

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
