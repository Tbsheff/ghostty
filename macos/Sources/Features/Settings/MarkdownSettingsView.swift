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

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Panel Theme", selection: $theme) {
                    Text("Terminal (Auto)").tag("terminal")
                    Text("GitHub Dark").tag("github-dark")
                    Text("GitHub Light").tag("github-light")
                    Text("Minimal").tag("minimal")
                    Text("Obsidian").tag("obsidian")
                }

                Picker("Code Syntax Theme", selection: $codeTheme) {
                    Text("Auto").tag("auto")
                    Text("Monokai").tag("monokai")
                    Text("Dracula").tag("dracula")
                    Text("Nord").tag("nord")
                    Text("GitHub").tag("github")
                    Text("One Dark").tag("one-dark")
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
        .onAppear {
            // Initialize settings sync - loads config file values and sets up observers
            _ = SettingsSync.shared
        }
    }
}

struct MarkdownSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        MarkdownSettingsView()
    }
}
