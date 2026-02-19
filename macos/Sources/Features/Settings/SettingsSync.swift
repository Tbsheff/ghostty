import Foundation
import Combine
import SwiftUI
import GhosttyKit

/// Syncs settings between UserDefaults (@AppStorage) and Ghostty config file
class SettingsSync: ObservableObject {
    static let shared = SettingsSync()

    @Published var syncStatus: SyncStatus = .idle
    @Published var hasExternalChanges: Bool = false
    @Published var lastSyncTime: Date?

    private var cancellables = Set<AnyCancellable>()
    private let configPath: URL
    private let defaultFontSize: Double = 13
    private let defaultBackgroundOpacity: Double = 1.0
    private let defaultUnfocusedSplitOpacity: Double = 0.7
    private let defaultBackgroundBlurRadius: Double = 20
    private let defaultScrollbackLimitBytes: Double = 10_000_000
    private let defaultScrollbackLimitMB: Double = 10
    private let defaultCopyOnSelect = "true"
    private let defaultRightClickAction = "context-menu"
    
    enum SyncStatus {
        case idle
        case syncing
        case success
        case error(String)
    }

    init() {
        // Find config file path
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/ghostty")
        configPath = configDir.appendingPathComponent("config")

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        // Load initial values from config file to UserDefaults
        loadFromConfigFile()

        // Watch for UserDefaults changes and write to config
        setupObservers()
    }

    func loadFromConfigFile() {
        guard let content = try? String(contentsOf: configPath, encoding: .utf8) else { return }

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), trimmed.contains("=") else { continue }

            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let rawValue = String(parts[1]).trimmingCharacters(in: .whitespaces)
            let value = normalizedStringValue(rawValue)

            // Map config keys to UserDefaults keys (using dot notation to match @AppStorage keys)
            switch key {
            case "font-family":
                UserDefaults.standard.set(value, forKey: "general.fontFamily")
            case "font-size":
                if let num = Double(value) {
                    UserDefaults.standard.set(num, forKey: "general.fontSize")
                }
            case "working-directory":
                if value == "inherit" || value.isEmpty {
                    UserDefaults.standard.set("inherit", forKey: "general.workingDirectoryMode")
                    UserDefaults.standard.set("", forKey: "general.workingDirectory")
                } else {
                    UserDefaults.standard.set("custom", forKey: "general.workingDirectoryMode")
                    UserDefaults.standard.set(value, forKey: "general.workingDirectory")
                }
            case "window-inherit-working-directory":
                if let boolValue = parseBool(value) {
                    UserDefaults.standard.set(boolValue, forKey: "general.inheritWindowWorkingDirectory")
                }
            case "tab-inherit-working-directory":
                if let boolValue = parseBool(value) {
                    UserDefaults.standard.set(boolValue, forKey: "general.inheritTabWorkingDirectory")
                }
            case "split-inherit-working-directory":
                if let boolValue = parseBool(value) {
                    UserDefaults.standard.set(boolValue, forKey: "general.inheritSplitWorkingDirectory")
                }
            case "window-inherit-font-size":
                if let boolValue = parseBool(value) {
                    UserDefaults.standard.set(boolValue, forKey: "general.inheritFontSize")
                }
            case "theme":
                UserDefaults.standard.set(value, forKey: "appearance.theme")
            case "window-theme":
                UserDefaults.standard.set(value, forKey: "appearance.windowTheme")
            case "cursor-style":
                UserDefaults.standard.set(value, forKey: "appearance.cursorStyle")
            case "cursor-style-blink":
                if let boolValue = parseBool(value) {
                    UserDefaults.standard.set(boolValue ? "true" : "false", forKey: "appearance.cursorBlink")
                } else {
                    UserDefaults.standard.set("auto", forKey: "appearance.cursorBlink")
                }
            case "background-opacity":
                if let num = Double(value) {
                    UserDefaults.standard.set(num, forKey: "appearance.backgroundOpacity")
                }
            case "background-blur":
                switch value.lowercased() {
                case "true":
                    UserDefaults.standard.set("standard", forKey: "appearance.backgroundBlurMode")
                case "false":
                    UserDefaults.standard.set("off", forKey: "appearance.backgroundBlurMode")
                case "macos-glass-regular":
                    UserDefaults.standard.set("macos-glass-regular", forKey: "appearance.backgroundBlurMode")
                case "macos-glass-clear":
                    UserDefaults.standard.set("macos-glass-clear", forKey: "appearance.backgroundBlurMode")
                default:
                    if let num = Double(value) {
                        UserDefaults.standard.set("custom", forKey: "appearance.backgroundBlurMode")
                        UserDefaults.standard.set(num, forKey: "appearance.backgroundBlurRadius")
                    }
                }
            case "unfocused-split-opacity":
                if let num = Double(value) {
                    UserDefaults.standard.set(num, forKey: "appearance.unfocusedSplitOpacity")
                }
            case "scrollback-limit":
                if let num = Double(value) {
                    let mb = max(1, num / 1_000_000)
                    UserDefaults.standard.set(mb, forKey: "behavior.scrollbackLimitMB")
                }
            case "copy-on-select":
                UserDefaults.standard.set(value, forKey: "behavior.copyOnSelect")
            case "clipboard-paste-protection":
                if let boolValue = parseBool(value) {
                    UserDefaults.standard.set(boolValue, forKey: "behavior.clipboardPasteProtection")
                }
            case "mouse-hide-while-typing":
                if let boolValue = parseBool(value) {
                    UserDefaults.standard.set(boolValue, forKey: "behavior.mouseHideWhileTyping")
                }
            case "focus-follows-mouse":
                if let boolValue = parseBool(value) {
                    UserDefaults.standard.set(boolValue, forKey: "behavior.focusFollowsMouse")
                }
            case "right-click-action":
                UserDefaults.standard.set(value, forKey: "behavior.rightClickAction")
            case "markdown-theme":
                UserDefaults.standard.set(value, forKey: "markdown.theme")
            case "markdown-font-size":
                if let num = Double(value) {
                    UserDefaults.standard.set(num, forKey: "markdown.fontSize")
                }
            case "markdown-code-font-size":
                if let num = Double(value) {
                    UserDefaults.standard.set(num, forKey: "markdown.codeFontSize")
                }
            case "markdown-line-height":
                if let num = Double(value) {
                    UserDefaults.standard.set(num, forKey: "markdown.lineHeight")
                }
            case "markdown-code-theme":
                UserDefaults.standard.set(value, forKey: "markdown.codeTheme")
            default:
                break
            }
        }
    }

    private func setupObservers() {
        // Watch for changes to settings in UserDefaults
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.writeToConfigFile()
            }
            .store(in: &cancellables)
    }

    func writeToConfigFile() {
        syncStatus = .syncing
        
        // Read existing config
        var lines = (try? String(contentsOf: configPath, encoding: .utf8))?
            .components(separatedBy: .newlines) ?? []

        let fontFamily = trimmedString(stringValue(forKey: "general.fontFamily", default: ""))
        setConfigString(&lines, key: "font-family", value: fontFamily.isEmpty ? nil : fontFamily)

        let fontSize = doubleValue(forKey: "general.fontSize", default: defaultFontSize)
        setConfigNumber(&lines, key: "font-size", value: fontSize, defaultValue: defaultFontSize) { value in
            String(Int(value.rounded()))
        }

        let workingDirectoryMode = stringValue(forKey: "general.workingDirectoryMode", default: "inherit")
        let workingDirectory = trimmedString(stringValue(forKey: "general.workingDirectory", default: ""))
        if workingDirectoryMode == "custom", !workingDirectory.isEmpty {
            setConfigString(&lines, key: "working-directory", value: workingDirectory)
        } else {
            removeConfigLines(&lines, key: "working-directory")
        }

        let inheritWindowWorkingDirectory = boolValue(forKey: "general.inheritWindowWorkingDirectory", default: true)
        setConfigBool(&lines, key: "window-inherit-working-directory", value: inheritWindowWorkingDirectory, defaultValue: true)

        let inheritTabWorkingDirectory = boolValue(forKey: "general.inheritTabWorkingDirectory", default: true)
        setConfigBool(&lines, key: "tab-inherit-working-directory", value: inheritTabWorkingDirectory, defaultValue: true)

        let inheritSplitWorkingDirectory = boolValue(forKey: "general.inheritSplitWorkingDirectory", default: true)
        setConfigBool(&lines, key: "split-inherit-working-directory", value: inheritSplitWorkingDirectory, defaultValue: true)

        let inheritFontSize = boolValue(forKey: "general.inheritFontSize", default: true)
        setConfigBool(&lines, key: "window-inherit-font-size", value: inheritFontSize, defaultValue: true)

        let theme = trimmedString(stringValue(forKey: "appearance.theme", default: ""))
        setConfigString(&lines, key: "theme", value: theme.isEmpty ? nil : theme)

        let windowTheme = stringValue(forKey: "appearance.windowTheme", default: "auto")
        setConfigString(&lines, key: "window-theme", value: windowTheme == "auto" ? nil : windowTheme)

        let cursorStyle = stringValue(forKey: "appearance.cursorStyle", default: "block")
        setConfigString(&lines, key: "cursor-style", value: cursorStyle == "block" ? nil : cursorStyle)

        let cursorBlink = stringValue(forKey: "appearance.cursorBlink", default: "auto")
        switch cursorBlink {
        case "true":
            setConfigString(&lines, key: "cursor-style-blink", value: "true")
        case "false":
            setConfigString(&lines, key: "cursor-style-blink", value: "false")
        default:
            removeConfigLines(&lines, key: "cursor-style-blink")
        }

        let backgroundOpacity = doubleValue(forKey: "appearance.backgroundOpacity", default: defaultBackgroundOpacity)
        setConfigNumber(&lines, key: "background-opacity", value: backgroundOpacity, defaultValue: defaultBackgroundOpacity) { value in
            String(format: "%.2f", value)
        }

        let blurMode = stringValue(forKey: "appearance.backgroundBlurMode", default: "off")
        let blurRadius = doubleValue(forKey: "appearance.backgroundBlurRadius", default: defaultBackgroundBlurRadius)
        switch blurMode {
        case "standard":
            setConfigString(&lines, key: "background-blur", value: "true")
        case "macos-glass-regular":
            setConfigString(&lines, key: "background-blur", value: "macos-glass-regular")
        case "macos-glass-clear":
            setConfigString(&lines, key: "background-blur", value: "macos-glass-clear")
        case "custom":
            if blurRadius > 0 {
                setConfigString(&lines, key: "background-blur", value: String(Int(blurRadius.rounded())))
            } else {
                removeConfigLines(&lines, key: "background-blur")
            }
        default:
            removeConfigLines(&lines, key: "background-blur")
        }

        let unfocusedSplitOpacity = doubleValue(
            forKey: "appearance.unfocusedSplitOpacity",
            default: defaultUnfocusedSplitOpacity
        )
        setConfigNumber(
            &lines,
            key: "unfocused-split-opacity",
            value: unfocusedSplitOpacity,
            defaultValue: defaultUnfocusedSplitOpacity
        ) { value in
            String(format: "%.2f", value)
        }

        let scrollbackLimitMB = max(
            1,
            doubleValue(forKey: "behavior.scrollbackLimitMB", default: defaultScrollbackLimitMB)
        )
        let scrollbackLimitBytes = scrollbackLimitMB * 1_000_000
        setConfigNumber(
            &lines,
            key: "scrollback-limit",
            value: scrollbackLimitBytes,
            defaultValue: defaultScrollbackLimitBytes
        ) { value in
            String(Int(value.rounded()))
        }

        let copyOnSelect = stringValue(forKey: "behavior.copyOnSelect", default: defaultCopyOnSelect)
        setConfigString(
            &lines,
            key: "copy-on-select",
            value: copyOnSelect == defaultCopyOnSelect ? nil : copyOnSelect
        )

        let clipboardPasteProtection = boolValue(forKey: "behavior.clipboardPasteProtection", default: true)
        setConfigBool(
            &lines,
            key: "clipboard-paste-protection",
            value: clipboardPasteProtection,
            defaultValue: true
        )

        let mouseHideWhileTyping = boolValue(forKey: "behavior.mouseHideWhileTyping", default: false)
        setConfigBool(
            &lines,
            key: "mouse-hide-while-typing",
            value: mouseHideWhileTyping,
            defaultValue: false
        )

        let focusFollowsMouse = boolValue(forKey: "behavior.focusFollowsMouse", default: false)
        setConfigBool(
            &lines,
            key: "focus-follows-mouse",
            value: focusFollowsMouse,
            defaultValue: false
        )

        let rightClickAction = stringValue(
            forKey: "behavior.rightClickAction",
            default: defaultRightClickAction
        )
        setConfigString(
            &lines,
            key: "right-click-action",
            value: rightClickAction == defaultRightClickAction ? nil : rightClickAction
        )

        let markdownTheme = trimmedString(stringValue(forKey: "markdown.theme", default: "terminal"))
        setConfigString(&lines, key: "markdown-theme", value: markdownTheme.isEmpty ? nil : markdownTheme)

        let markdownFontSize = doubleValue(forKey: "markdown.fontSize", default: 15)
        setConfigNumber(&lines, key: "markdown-font-size", value: markdownFontSize, defaultValue: 15) { value in
            String(Int(value.rounded()))
        }

        let markdownCodeFontSize = doubleValue(forKey: "markdown.codeFontSize", default: 13)
        setConfigNumber(&lines, key: "markdown-code-font-size", value: markdownCodeFontSize, defaultValue: 13) { value in
            String(Int(value.rounded()))
        }

        let markdownLineHeight = doubleValue(forKey: "markdown.lineHeight", default: 1.4)
        setConfigNumber(&lines, key: "markdown-line-height", value: markdownLineHeight, defaultValue: 1.4) { value in
            String(format: "%.1f", value)
        }

        let markdownCodeTheme = trimmedString(stringValue(forKey: "markdown.codeTheme", default: "auto"))
        setConfigString(&lines, key: "markdown-code-theme", value: markdownCodeTheme.isEmpty ? nil : markdownCodeTheme)

        removeConfigLines(&lines, key: "markdown-enabled")

        // Write back
        let content = lines.joined(separator: "\n")
        do {
            try content.write(to: configPath, atomically: true, encoding: .utf8)
            DispatchQueue.main.async {
                self.lastSyncTime = Date()
                self.syncStatus = .success
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self.syncStatus = .idle
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.syncStatus = .error("Failed to save config")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.syncStatus = .idle
                }
            }
        }

        // Notify Ghostty to reload config
        NotificationCenter.default.post(name: .ghosttyConfigDidChange, object: nil)
    }

    private func stringValue(forKey key: String, default defaultValue: String) -> String {
        if let value = UserDefaults.standard.string(forKey: key) {
            return value
        }
        return defaultValue
    }

    private func doubleValue(forKey key: String, default defaultValue: Double) -> Double {
        if UserDefaults.standard.object(forKey: key) != nil {
            return UserDefaults.standard.double(forKey: key)
        }
        return defaultValue
    }

    private func boolValue(forKey key: String, default defaultValue: Bool) -> Bool {
        if UserDefaults.standard.object(forKey: key) != nil {
            return UserDefaults.standard.bool(forKey: key)
        }
        return defaultValue
    }

    private func parseBool(_ value: String) -> Bool? {
        switch value.lowercased() {
        case "true":
            return true
        case "false":
            return false
        default:
            return nil
        }
    }

    private func normalizedStringValue(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 else {
            return trimmed
        }

        let inner = String(trimmed.dropFirst().dropLast())
        var result = ""
        var isEscaping = false
        for char in inner {
            if isEscaping {
                result.append(char)
                isEscaping = false
                continue
            }
            if char == "\\" {
                isEscaping = true
                continue
            }
            result.append(char)
        }

        return result
    }

    private func trimmedString(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func needsQuoting(_ value: String) -> Bool {
        value.contains { char in
            char.isWhitespace || char == "#" || char == "\"" || char == "\\"
        }
    }

    private func quotedValue(_ value: String) -> String {
        var escaped = ""
        for char in value {
            if char == "\"" || char == "\\" {
                escaped.append("\\")
            }
            escaped.append(char)
        }
        return "\"\(escaped)\""
    }

    private func formatStringValue(_ value: String) -> String {
        let trimmed = trimmedString(value)
        if trimmed.isEmpty { return trimmed }
        return needsQuoting(trimmed) ? quotedValue(trimmed) : trimmed
    }

    private func setConfigString(_ lines: inout [String], key: String, value: String?) {
        guard let value, !value.isEmpty else {
            removeConfigLines(&lines, key: key)
            return
        }
        replaceConfigLine(&lines, key: key, value: formatStringValue(value))
    }

    private func setConfigBool(
        _ lines: inout [String],
        key: String,
        value: Bool,
        defaultValue: Bool
    ) {
        if value == defaultValue {
            removeConfigLines(&lines, key: key)
        } else {
            replaceConfigLine(&lines, key: key, value: value ? "true" : "false")
        }
    }

    private func setConfigNumber(
        _ lines: inout [String],
        key: String,
        value: Double,
        defaultValue: Double,
        formatter: (Double) -> String
    ) {
        if abs(value - defaultValue) < 0.0001 {
            removeConfigLines(&lines, key: key)
        } else {
            replaceConfigLine(&lines, key: key, value: formatter(value))
        }
    }

    private func replaceConfigLine(_ lines: inout [String], key: String, value: String) {
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        let pattern = "^\\s*\(escapedKey)\\s*="
        var found = false
        var updated: [String] = []

        for line in lines {
            if line.range(of: pattern, options: .regularExpression) != nil {
                if !found {
                    updated.append("\(key) = \(value)")
                    found = true
                }
                continue
            }
            updated.append(line)
        }

        if !found {
            updated.append("\(key) = \(value)")
        }

        lines = updated
    }

    private func removeConfigLines(_ lines: inout [String], key: String) {
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        let pattern = "^\\s*\(escapedKey)\\s*="
        lines.removeAll { line in
            line.range(of: pattern, options: .regularExpression) != nil
        }
    }
}

// MARK: - External Conflict Notice

struct ExternalConflictNotice: View {
    @ObservedObject var settingsSync: SettingsSync
    let onReload: () -> Void

    @Environment(\.adaptiveTheme) private var theme

    var body: some View {
        if settingsSync.hasExternalChanges {
            HStack(spacing: AdaptiveTheme.spacing8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(theme.warningC)
                    .font(.system(size: 14))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Configuration Changed Externally")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(theme.textPrimaryC)
                    Text("Your config file was modified outside of this app.")
                        .font(.caption)
                        .foregroundColor(theme.textSecondaryC)
                }

                Spacer()

                Button(action: onReload) {
                    Text("Reload")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(theme.accentC)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: AdaptiveTheme.radiusSmall, style: .continuous)
                                .stroke(theme.accentC, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(AdaptiveTheme.spacing10)
            .background(
                RoundedRectangle(cornerRadius: AdaptiveTheme.radiusMedium, style: .continuous)
                    .fill(theme.surfaceElevatedC)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AdaptiveTheme.radiusMedium, style: .continuous)
                    .stroke(theme.warningC.opacity(0.3), lineWidth: 1)
            )
        }
    }
}
