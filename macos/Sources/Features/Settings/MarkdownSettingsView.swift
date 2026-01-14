import SwiftUI
import GhosttyKit

struct MarkdownSettingsView: View {
    // Use @AppStorage for persistence (writes to UserDefaults)
    // These will need to sync with the config file
    @AppStorage("markdown.theme") private var theme = "terminal"
    @AppStorage("markdown.fontSize") private var fontSize: Double = 15
    @AppStorage("markdown.codeFontSize") private var codeFontSize: Double = 13
    @AppStorage("markdown.lineHeight") private var lineHeight: Double = 1.4
    @AppStorage("markdown.codeTheme") private var codeTheme = "auto"
    @State private var showPreview: Bool = true
    
    // Dynamic preview colors based on theme
    private var themeBackground: Color {
        switch theme {
        case "ghostty":
            return Color(red: 0.12, green: 0.12, blue: 0.15)
        case "github":
            return Color(red: 0.96, green: 0.96, blue: 0.98)
        case "minimal":
            return Color.white
        default: // terminal
            return Color(red: 0.15, green: 0.15, blue: 0.15)
        }
    }
    
    private var themeForeground: Color {
        switch theme {
        case "github":
            return Color(red: 0.1, green: 0.1, blue: 0.1)
        case "minimal":
            return Color(red: 0.2, green: 0.2, blue: 0.2)
        default: // terminal, ghostty
            return Color(red: 0.9, green: 0.9, blue: 0.9)
        }
    }
    
    private var codeThemeColor: Color {
        switch codeTheme {
        case "monokai":
            return Color(red: 0.98, green: 0.4, blue: 0.4)
        case "dracula":
            return Color(red: 1.0, green: 0.57, blue: 0.64)
        case "nord":
            return Color(red: 0.44, green: 0.75, blue: 0.85)
        case "github":
            return Color(red: 0.2, green: 0.5, blue: 1.0)
        case "one-dark":
            return Color(red: 0.98, green: 0.61, blue: 0.64)
        case "terminal":
            return Color(red: 0.0, green: 0.8, blue: 0.0)
        default: // auto
            return Color(red: 0.4, green: 0.8, blue: 1.0)
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            // Settings panel
            VStack(alignment: .leading, spacing: 0) {
                Form {
                    Section("Theme") {
                        Picker("Panel Theme", selection: $theme) {
                            Text("Terminal").tag("terminal")
                            Text("Ghostty").tag("ghostty")
                            Text("GitHub").tag("github")
                            Text("Minimal").tag("minimal")
                        }

                        Picker("Code Syntax Theme", selection: $codeTheme) {
                            Text("Auto").tag("auto")
                            Text("Monokai").tag("monokai")
                            Text("Dracula").tag("dracula")
                            Text("Nord").tag("nord")
                            Text("GitHub").tag("github")
                            Text("One Dark").tag("one-dark")
                            Text("Terminal").tag("terminal")
                        }
                    }

                    Section("Typography") {
                        HStack {
                            Text("Font Size: \(Int(fontSize))")
                            Slider(value: $fontSize, in: 10...24, step: 1)
                        }

                        HStack {
                            Text("Code Font Size: \(Int(codeFontSize))")
                            Slider(value: $codeFontSize, in: 10...24, step: 1)
                        }

                        HStack {
                            Text("Line Height: \(lineHeight, specifier: "%.1f")")
                            Slider(value: $lineHeight, in: 1.0...2.0, step: 0.1)
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
            .frame(maxWidth: .infinity)
            
            // Live preview panel
            if showPreview {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Live Preview")
                            .font(.headline)
                        Spacer()
                        Button(action: { showPreview = false }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 4)
                    
                    // Quick preset buttons
                    HStack(spacing: 6) {
                        ForEach(["terminal", "ghostty", "github", "minimal"], id: \.self) { presetTheme in
                            Button(action: { theme = presetTheme }) {
                                Text(presetTheme.prefix(1).uppercased())
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 24, height: 24)
                                    .background(theme == presetTheme ? Color.blue : Color.gray.opacity(0.5))
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                            .help("Switch to \(presetTheme) theme")
                        }
                        Spacer()
                    }
                    .padding(.bottom, 4)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            // Live preview with actual theme colors
                            VStack(alignment: .leading, spacing: 8) {
                                // Heading
                                Text("# Markdown Heading")
                                    .font(.system(size: CGFloat(fontSize), weight: .bold, design: .default))
                                    .foregroundColor(themeForeground)
                                
                                // Body text with dynamic line height
                                VStack(alignment: .leading, spacing: 0) {
                                    Text("This is a paragraph with ")
                                    + Text("bold").fontWeight(.bold)
                                    + Text(" and ")
                                    + Text("italic").italic()
                                    + Text(" text.")
                                }
                                .font(.system(size: CGFloat(fontSize)))
                                .lineSpacing(lineHeight - 1.0)
                                .foregroundColor(themeForeground)
                                
                                // Code block with syntax theme color
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Code example")
                                        .font(.system(size: CGFloat(codeFontSize), design: .monospaced))
                                        .foregroundColor(codeThemeColor)
                                    
                                    Text("let x = 42")
                                        .font(.system(size: CGFloat(codeFontSize), design: .monospaced))
                                        .foregroundColor(codeThemeColor)
                                        .padding(8)
                                        .background(themeBackground.opacity(0.5))
                                        .cornerRadius(4)
                                }
                            }
                            .padding(12)
                            .background(themeBackground)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                            
                            // Theme info
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Theme: \(theme)")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                    Text("Size: \(Int(fontSize))pt, Line: \(lineHeight, specifier: "%.1f")")
                                        .font(.caption2)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("Code Theme: \(codeTheme)")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                    Text("Code Size: \(Int(codeFontSize))pt")
                                        .font(.caption2)
                                }
                            }
                            .foregroundColor(.secondary)
                            .padding(8)
                            .background(Color(.controlBackgroundColor).opacity(0.5))
                            .cornerRadius(4)
                        }
                        .padding(12)
                    }
                    .background(Color(.controlBackgroundColor).opacity(0.3))
                    .cornerRadius(6)
                }
                .frame(maxWidth: 300)
                .padding(12)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
            }
        }
        .padding()
    }
}

struct MarkdownSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        MarkdownSettingsView()
    }
}
