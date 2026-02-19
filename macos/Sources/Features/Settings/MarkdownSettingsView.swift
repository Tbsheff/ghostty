import SwiftUI
import GhosttyKit

struct MarkdownSettingsView: View {
    @AppStorage("markdown.theme") private var theme = "terminal"
    @AppStorage("markdown.fontSize") private var fontSize: Double = 15
    @AppStorage("markdown.codeFontSize") private var codeFontSize: Double = 13
    @AppStorage("markdown.lineHeight") private var lineHeight: Double = 1.4
    @AppStorage("markdown.codeTheme") private var codeTheme = "auto"
    @State private var showPreview: Bool = true

    @Environment(\.adaptiveTheme) private var adaptiveTheme

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
        HStack(spacing: 0) {
            // Settings panel — themed controls
            SettingsFormContainer {
                ThemedSection(header: "Theme") {
                    ThemedPicker(
                        label: "Panel Theme",
                        selection: $theme,
                        options: [
                            ("Terminal", "terminal"),
                            ("Ghostty", "ghostty"),
                            ("GitHub", "github"),
                            ("Minimal", "minimal"),
                        ]
                    )

                    ThemedPicker(
                        label: "Code Syntax Theme",
                        selection: $codeTheme,
                        options: [
                            ("Auto", "auto"),
                            ("Monokai", "monokai"),
                            ("Dracula", "dracula"),
                            ("Nord", "nord"),
                            ("GitHub", "github"),
                            ("One Dark", "one-dark"),
                            ("Terminal", "terminal"),
                        ]
                    )
                }

                ThemedSection(header: "Typography") {
                    ThemedSlider(
                        label: "Font Size",
                        value: $fontSize,
                        range: 10...24,
                        step: 1,
                        format: "%.0f",
                        suffix: "pt"
                    )

                    ThemedSlider(
                        label: "Code Font Size",
                        value: $codeFontSize,
                        range: 10...24,
                        step: 1,
                        format: "%.0f",
                        suffix: "pt"
                    )

                    ThemedSlider(
                        label: "Line Height",
                        value: $lineHeight,
                        range: 1.0...2.0,
                        step: 0.1,
                        format: "%.1f"
                    )
                }

                AutoSaveFooter()
            }
            .frame(maxWidth: .infinity)

            // Live preview panel (kept as-is — already custom styled)
            if showPreview {
                Rectangle()
                    .fill(adaptiveTheme.borderSubtleC)
                    .frame(width: 1)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Live Preview")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(adaptiveTheme.textPrimaryC)
                        Spacer()
                        Button(action: { showPreview = false }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12))
                                .foregroundColor(adaptiveTheme.textMutedC)
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
                                    .background(
                                        RoundedRectangle(cornerRadius: AdaptiveTheme.radiusSmall, style: .continuous)
                                            .fill(theme == presetTheme ? adaptiveTheme.accentC : adaptiveTheme.surfaceHoverC)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help("Switch to \(presetTheme) theme")
                        }
                        Spacer()
                    }
                    .padding(.bottom, 4)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("# Markdown Heading")
                                    .font(.system(size: CGFloat(fontSize), weight: .bold, design: .default))
                                    .foregroundColor(themeForeground)

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
                            .clipShape(RoundedRectangle(cornerRadius: AdaptiveTheme.radiusMedium, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: AdaptiveTheme.radiusMedium, style: .continuous)
                                    .stroke(adaptiveTheme.borderSubtleC, lineWidth: 1)
                            )

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
                            .foregroundColor(adaptiveTheme.textSecondaryC)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: AdaptiveTheme.radiusSmall, style: .continuous)
                                    .fill(adaptiveTheme.surfaceElevatedC)
                            )
                        }
                        .padding(12)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: AdaptiveTheme.radiusMedium, style: .continuous)
                            .fill(adaptiveTheme.backgroundC.opacity(0.3))
                    )
                }
                .frame(maxWidth: 300)
                .padding(12)
                .background(adaptiveTheme.surfaceElevatedC)
            }
        }
    }
}

struct MarkdownSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        MarkdownSettingsView()
    }
}
