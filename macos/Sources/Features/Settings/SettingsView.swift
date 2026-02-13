import SwiftUI
import AppKit

// MARK: - Setting Model

struct SettingItem: Identifiable {
    let id: String
    let title: String
    let description: String
    let category: String
    let keywords: [String]  // Additional keywords for searching
}

// Settings data model
let settingsData: [SettingItem] = [
    // General section
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
    
    // Appearance section
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
    
    // Behavior section
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
    
    // Markdown section
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

    private var quickAccessItems: [SettingItem] {
        let ids = ["font-settings", "appearance-settings", "markdown-settings"]
        return settingsData.filter { ids.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Sync status and conflict notice
            VStack(spacing: AdaptiveTheme.spacing8) {
                SyncStatusIndicator(settingsSync: settingsSync)

                ExternalConflictNotice(settingsSync: settingsSync) {
                    settingsSync.loadFromConfigFile()
                }
            }
            .padding(AdaptiveTheme.spacing10)
            .background(theme.surfaceElevatedC.opacity(0.5))

            // Search bar with category filter
            VStack(spacing: AdaptiveTheme.spacing8) {
                SidebarSearchField(
                    text: $searchText,
                    placeholder: "Search settings..."
                )
                .help("Press Cmd+F to focus search")

                // Category filter (shown when searching)
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

            // Conditional content based on search
            if searchText.isEmpty {
                HStack(spacing: 0) {
                    SettingsSidebar(selection: $selectedTab)
                        .frame(width: 160)

                    Rectangle()
                        .fill(theme.borderSubtleC)
                        .frame(width: 1)

                    VStack(spacing: 0) {
                        QuickAccessPanel(items: quickAccessItems) { item in
                            searchCategory = item.category
                            searchText = item.title
                        }

                        selectedSettingsView
                    }
                }
            } else {
                SearchableSettingsView(searchText: searchText, category: searchCategory)
            }
        }
        .frame(width: 560, height: 560)
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

// MARK: - Quick Access

struct QuickAccessPanel: View {
    let items: [SettingItem]
    let onSelect: (SettingItem) -> Void

    @Environment(\.adaptiveTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: AdaptiveTheme.spacing8) {
            HStack {
                Text("Quick Access")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(theme.textMutedC)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(theme.accentC)
            }
            .padding(.horizontal, AdaptiveTheme.spacing10)

            HStack(spacing: AdaptiveTheme.spacing10) {
                ForEach(items.prefix(3)) { item in
                    QuickAccessCard(item: item, onSelect: onSelect)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AdaptiveTheme.spacing10)
        }
        .padding(.vertical, AdaptiveTheme.spacing8)
        .background(theme.surfaceElevatedC.opacity(0.6))
        .overlay(
            Rectangle()
                .fill(theme.borderSubtleC)
                .frame(height: 1),
            alignment: .bottom
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Quick Access to Common Settings")
    }
}

struct QuickAccessCard: View {
    let item: SettingItem
    let onSelect: (SettingItem) -> Void

    @Environment(\.adaptiveTheme) private var theme
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    private var isActive: Bool { isHovered || isFocused }

    var body: some View {
        Button(action: { onSelect(item) }) {
            VStack(alignment: .leading, spacing: AdaptiveTheme.spacing4) {
                HStack {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    if isActive {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(theme.accentC)
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                }
                Text(item.description)
                    .font(.caption)
                    .foregroundColor(theme.textSecondaryC)
                    .lineLimit(2)
            }
            .padding(AdaptiveTheme.spacing8)
            .frame(maxWidth: 180, alignment: .leading)
            .foregroundColor(theme.textPrimaryC)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: AdaptiveTheme.radiusMedium, style: .continuous)
                .fill(isActive ? theme.surfaceHoverC : theme.surfaceElevatedC)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AdaptiveTheme.radiusMedium, style: .continuous)
                .stroke(isActive ? theme.accentC.opacity(0.3) : theme.borderSubtleC, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AdaptiveTheme.radiusMedium, style: .continuous))
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .focused($isFocused)
        .animation(.linear(duration: AdaptiveTheme.animationFast), value: isActive)
        .help("Scroll to \(item.category) settings")
        .accessibilityLabel(item.title)
        .accessibilityHint(item.description)
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

    private var isFontFamilyValid: Bool {
        fontFamily.isEmpty || !fontFamily.contains("/")
    }
    
    private var fontFamilyErrorMessage: String? {
        guard !fontFamily.isEmpty && !isFontFamilyValid else { return nil }
        return "Font family cannot contain path separators"
    }
    
    private var isFontSizeValid: Bool {
        fontSize >= 8 && fontSize <= 32
    }
    
    private var fontSizeErrorMessage: String? {
        guard !isFontSizeValid else { return nil }
        if fontSize < 8 {
            return "Font size must be at least 8"
        } else if fontSize > 32 {
            return "Font size cannot exceed 32"
        }
        return nil
    }
    
    var body: some View {
        Form {
            Section("Font") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        TextField("Font Family", text: $fontFamily)
                        if !fontFamily.isEmpty {
                            Image(systemName: isFontFamilyValid ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .foregroundColor(isFontFamilyValid ? .green : .red)
                                .font(.system(size: 12))
                        }
                    }
                    if let error = fontFamilyErrorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Font Size: \(Int(fontSize))")
                        Slider(value: $fontSize, in: 8...32, step: 1)
                        Image(systemName: isFontSizeValid ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundColor(isFontSizeValid ? .green : .red)
                            .font(.system(size: 12))
                    }
                    if let error = fontSizeErrorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Toggle("Inherit font size for new windows", isOn: $inheritFontSize)
            }

            Section("Working Directory") {
                Picker("Default Directory", selection: $workingDirectoryMode) {
                    Text("Inherit").tag("inherit")
                    Text("Custom").tag("custom")
                }
                .pickerStyle(.segmented)

                if workingDirectoryMode == "custom" {
                    TextField("Path", text: $workingDirectory)
                }

                Toggle("Inherit for new windows", isOn: $inheritWindowWorkingDirectory)
                Toggle("Inherit for new tabs", isOn: $inheritTabWorkingDirectory)
                Toggle("Inherit for new splits", isOn: $inheritSplitWorkingDirectory)
            }

            Section {
                Text("Changes are saved automatically to your Ghostty config file.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

// MARK: - Appearance Settings

struct AppearanceSettingsView: View {
    @AppStorage("appearance.theme") private var theme = ""
    @AppStorage("appearance.windowTheme") private var windowTheme = "auto"
    @AppStorage("appearance.cursorStyle") private var cursorStyle = "block"
    @AppStorage("appearance.cursorBlink") private var cursorBlink = "auto"
    @AppStorage("appearance.backgroundOpacity") private var backgroundOpacity: Double = 1.0
    @AppStorage("appearance.backgroundBlurMode") private var backgroundBlurMode = "off"
    @AppStorage("appearance.backgroundBlurRadius") private var backgroundBlurRadius: Double = 20
    @AppStorage("appearance.unfocusedSplitOpacity") private var unfocusedSplitOpacity: Double = 0.7

    var body: some View {
        Form {
            Section("Theme") {
                TextField("Theme", text: $theme)

                Picker("Window Theme", selection: $windowTheme) {
                    Text("Auto").tag("auto")
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                    Text("Ghostty").tag("ghostty")
                }

                Text("Use light/dark pairs like \"light:Rose Pine Dawn,dark:Rose Pine\".")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Cursor") {
                Picker("Style", selection: $cursorStyle) {
                    Text("Block").tag("block")
                    Text("Underline").tag("underline")
                    Text("Bar").tag("bar")
                    Text("Hollow Block").tag("block_hollow")
                }

                Picker("Blink", selection: $cursorBlink) {
                    Text("Auto").tag("auto")
                    Text("On").tag("true")
                    Text("Off").tag("false")
                }
            }

            Section("Transparency") {
                HStack {
                    Text("Background Opacity: \(backgroundOpacity, specifier: "%.2f")")
                    Slider(value: $backgroundOpacity, in: 0.0...1.0, step: 0.05)
                }

                Picker("Background Blur", selection: $backgroundBlurMode) {
                    Text("Off").tag("off")
                    Text("Standard").tag("standard")
                    Text("Glass (Regular)").tag("macos-glass-regular")
                    Text("Glass (Clear)").tag("macos-glass-clear")
                    Text("Custom").tag("custom")
                }

                if backgroundBlurMode == "custom" {
                    HStack {
                        Text("Blur Radius: \(Int(backgroundBlurRadius))")
                        Slider(value: $backgroundBlurRadius, in: 0...50, step: 1)
                    }
                }

                Text("Changing background opacity or blur may require restarting Ghostty on macOS.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Splits") {
                HStack {
                    Text("Unfocused Split Opacity: \(unfocusedSplitOpacity, specifier: "%.2f")")
                    Slider(value: $unfocusedSplitOpacity, in: 0.15...1.0, step: 0.05)
                }
            }

            Section {
                Text("Changes are saved automatically to your Ghostty config file.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
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

    var body: some View {
        Form {
            Section("Scrollback") {
                HStack {
                    Text("Limit: \(Int(scrollbackLimitMB)) MB")
                    Slider(value: $scrollbackLimitMB, in: 1...500, step: 1)
                }

                Text("Applies per terminal surface and affects new windows/tabs only.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Clipboard") {
                Picker("Copy on Select", selection: $copyOnSelect) {
                    Text("Off").tag("false")
                    Text("On").tag("true")
                    Text("Clipboard + Selection").tag("clipboard")
                }

                Toggle("Paste protection", isOn: $clipboardPasteProtection)
            }

            Section("Mouse") {
                Toggle("Hide while typing", isOn: $mouseHideWhileTyping)
                Toggle("Focus follows mouse", isOn: $focusFollowsMouse)

                Picker("Right Click", selection: $rightClickAction) {
                    Text("Context Menu").tag("context-menu")
                    Text("Paste").tag("paste")
                    Text("Copy").tag("copy")
                    Text("Copy or Paste").tag("copy-or-paste")
                    Text("Ignore").tag("ignore")
                }
            }

            Section {
                Text("Changes are saved automatically to your Ghostty config file.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

// MARK: - Advanced Settings

struct AdvancedSettingsView: View {
    var body: some View {
        Text("Advanced settings coming soon")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
