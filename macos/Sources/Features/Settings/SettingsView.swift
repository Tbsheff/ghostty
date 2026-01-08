import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appDelegate: AppDelegate

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }

            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }

            MarkdownSettingsView()
                .tabItem { Label("Markdown", systemImage: "doc.richtext") }

            AdvancedSettingsView()
                .tabItem { Label("Advanced", systemImage: "gearshape.2") }
        }
        .frame(width: 500, height: 400)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    var body: some View {
        Text("General settings coming soon")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Appearance Settings

struct AppearanceSettingsView: View {
    var body: some View {
        Text("Appearance settings coming soon")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
