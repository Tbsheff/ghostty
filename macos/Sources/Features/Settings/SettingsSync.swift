import Foundation
import Combine
import GhosttyKit

/// Syncs settings between UserDefaults (@AppStorage) and Ghostty config file
class SettingsSync: ObservableObject {
    static let shared = SettingsSync()

    private var cancellables = Set<AnyCancellable>()
    private let configPath: URL

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

    private func loadFromConfigFile() {
        guard let content = try? String(contentsOf: configPath, encoding: .utf8) else { return }

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), trimmed.contains("=") else { continue }

            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let value = String(parts[1]).trimmingCharacters(in: .whitespaces)

            // Map config keys to UserDefaults keys (using dot notation to match @AppStorage keys)
            switch key {
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
            case "markdown-enabled":
                UserDefaults.standard.set(value == "true", forKey: "markdown.enabled")
            default:
                break
            }
        }
    }

    private func setupObservers() {
        // Watch for changes to markdown settings in UserDefaults
        // Using NotificationCenter to observe UserDefaults changes
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.writeToConfigFile()
            }
            .store(in: &cancellables)
    }

    func writeToConfigFile() {
        // Read existing config
        var lines = (try? String(contentsOf: configPath, encoding: .utf8))?
            .components(separatedBy: .newlines) ?? []

        // Update or add markdown settings (using dot notation keys to match @AppStorage)
        let settings: [(String, String)] = [
            ("markdown-enabled", UserDefaults.standard.bool(forKey: "markdown.enabled") ? "true" : "false"),
            ("markdown-theme", UserDefaults.standard.string(forKey: "markdown.theme") ?? "terminal"),
            ("markdown-font-size", String(Int(UserDefaults.standard.double(forKey: "markdown.fontSize")))),
            ("markdown-code-font-size", String(Int(UserDefaults.standard.double(forKey: "markdown.codeFontSize")))),
            ("markdown-line-height", String(format: "%.1f", UserDefaults.standard.double(forKey: "markdown.lineHeight"))),
            ("markdown-code-theme", UserDefaults.standard.string(forKey: "markdown.codeTheme") ?? "auto"),
        ]

        for (key, value) in settings {
            // Skip writing if value is default/empty
            if value == "0" || value == "0.0" { continue }
            updateConfigLine(&lines, key: key, value: value)
        }

        // Write back
        let content = lines.joined(separator: "\n")
        try? content.write(to: configPath, atomically: true, encoding: .utf8)

        // Notify Ghostty to reload config
        NotificationCenter.default.post(name: .ghosttyConfigDidChange, object: nil)
    }

    private func updateConfigLine(_ lines: inout [String], key: String, value: String) {
        let pattern = "^\(key)\\s*="
        if let index = lines.firstIndex(where: { $0.range(of: pattern, options: .regularExpression) != nil }) {
            lines[index] = "\(key) = \(value)"
        } else {
            // Add new line (find a good spot or append)
            lines.append("\(key) = \(value)")
        }
    }
}
