import SwiftUI
import WebKit

/// A Warp-inspired view that renders markdown content with syntax highlighting.
struct MarkdownPanelView: View {
    @Binding var content: String
    let filePath: String?
    let onClose: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            MarkdownPanelHeader(
                filePath: filePath,
                onClose: onClose,
                onRefresh: onRefresh
            )

            Rectangle()
                .fill(Color(PanelTheme.border))
                .frame(height: 1)

            MarkdownWebView(content: content)
        }
        .frame(minWidth: 300)
        .background(Color(PanelTheme.background))
    }
}

// MARK: - Header with Breadcrumb

struct MarkdownPanelHeader: View {
    let filePath: String?
    let onClose: () -> Void
    let onRefresh: () -> Void

    @State private var refreshHovered = false
    @State private var closeHovered = false
    @State private var revealHovered = false
    @State private var copyPathHovered = false
    @State private var showCopiedFeedback = false

    private var breadcrumbs: [String] {
        guard let path = filePath else { return ["Preview"] }
        let components = path.split(separator: "/").suffix(3)
        return components.map(String.init)
    }

    private func revealInFinder() {
        guard let path = filePath else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: (path as NSString).deletingLastPathComponent)
    }

    private func copyPathToClipboard() {
        guard let path = filePath else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        
        // Visual feedback
        showCopiedFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showCopiedFeedback = false
        }
    }

    var body: some View {
        HStack(spacing: PanelTheme.spacing8) {
            // Breadcrumb path
            HStack(spacing: PanelTheme.spacing4) {
                ForEach(Array(breadcrumbs.enumerated()), id: \.offset) { index, component in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Color(PanelTheme.textMuted))
                    }

                    Text(component)
                        .font(.system(size: 12, weight: index == breadcrumbs.count - 1 ? .medium : .regular))
                        .foregroundColor(Color(index == breadcrumbs.count - 1 ? PanelTheme.textPrimary : PanelTheme.textSecondary))
                        .lineLimit(1)
                }
            }

            Spacer()

            // Actions
            HStack(spacing: PanelTheme.spacing4) {
                // Contextual actions (only show when filePath is available)
                if filePath != nil {
                    Button(action: revealInFinder) {
                        Image(systemName: "folder")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(revealHovered ? PanelTheme.iconHover : PanelTheme.iconDefault))
                            .frame(width: 28, height: 28)
                            .background(revealHovered ? Color(PanelTheme.surfaceHover) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: PanelTheme.radiusSmall))
                    }
                    .buttonStyle(.plain)
                    .help("Reveal in Finder")
                    .onHover { revealHovered = $0 }

                    Button(action: copyPathToClipboard) {
                        Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(showCopiedFeedback ? PanelTheme.success : (copyPathHovered ? PanelTheme.iconHover : PanelTheme.iconDefault)))
                            .frame(width: 28, height: 28)
                            .background(copyPathHovered ? Color(PanelTheme.surfaceHover) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: PanelTheme.radiusSmall))
                    }
                    .buttonStyle(.plain)
                    .help("Copy path")
                    .onHover { copyPathHovered = $0 }
                }

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(refreshHovered ? PanelTheme.iconHover : PanelTheme.iconDefault))
                        .frame(width: 28, height: 28)
                        .background(refreshHovered ? Color(PanelTheme.surfaceHover) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: PanelTheme.radiusSmall))
                }
                .buttonStyle(.plain)
                .help("Refresh")
                .onHover { refreshHovered = $0 }

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(closeHovered ? PanelTheme.iconHover : PanelTheme.iconDefault))
                        .frame(width: 28, height: 28)
                        .background(closeHovered ? Color(PanelTheme.surfaceHover) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: PanelTheme.radiusSmall))
                }
                .buttonStyle(.plain)
                .help("Close")
                .onHover { closeHovered = $0 }
            }
        }
        .padding(.horizontal, PanelTheme.spacing12)
        .padding(.vertical, PanelTheme.spacing8)
        .background(Color(PanelTheme.surfaceElevated))
    }
}

// MARK: - WebView

struct MarkdownWebView: NSViewRepresentable {
    let content: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = generateHTML(from: content)
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func generateHTML(from markdown: String) -> String {
        let escapedMarkdown = markdown
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
            <script src="https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11.9.0/build/highlight.min.js"></script>
            <link rel="stylesheet" href="https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11.9.0/build/styles/github-dark.min.css">
            <style>
                \(warpInspiredCSS)
            </style>
        </head>
        <body>
            <article id="content"></article>
            <script>
                marked.setOptions({
                    highlight: function(code, lang) {
                        if (lang && hljs.getLanguage(lang)) {
                            try {
                                return hljs.highlight(code, { language: lang }).value;
                            } catch (e) {}
                        }
                        return hljs.highlightAuto(code).value;
                    },
                    breaks: true,
                    gfm: true
                });

                const markdown = `\(escapedMarkdown)`;
                document.getElementById('content').innerHTML = marked.parse(markdown);
            </script>
        </body>
        </html>
        """
    }

    private var warpInspiredCSS: String {
        """
        :root {
            color-scheme: dark;
            --bg-primary: #0D1117;
            --bg-elevated: #161B22;
            --bg-code: #1C2128;
            --border: #30363D;
            --border-subtle: #21262D;
            --text-primary: #E6EDF3;
            --text-secondary: #8B949E;
            --text-muted: #6E7681;
            --accent: #58A6FF;
            --accent-muted: #388BFD66;
        }

        * {
            box-sizing: border-box;
        }

        html {
            scroll-behavior: smooth;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Helvetica, Arial, sans-serif;
            font-size: 15px;
            line-height: 1.7;
            color: var(--text-primary);
            background-color: var(--bg-primary);
            padding: 32px 28px;
            margin: 0;
            -webkit-font-smoothing: antialiased;
            -moz-osx-font-smoothing: grayscale;
        }

        article {
            max-width: 800px;
            margin: 0 auto;
        }

        /* Headings */
        h1, h2, h3, h4, h5, h6 {
            color: var(--text-primary);
            font-weight: 600;
            line-height: 1.3;
            margin-top: 28px;
            margin-bottom: 16px;
            letter-spacing: -0.01em;
        }

        h1 {
            font-size: 2em;
            font-weight: 700;
            padding-bottom: 12px;
            border-bottom: 1px solid var(--border);
            margin-top: 0;
        }

        h2 {
            font-size: 1.5em;
            padding-bottom: 8px;
            border-bottom: 1px solid var(--border-subtle);
        }

        h3 { font-size: 1.25em; }
        h4 { font-size: 1.1em; }
        h5 { font-size: 1em; color: var(--text-secondary); }
        h6 { font-size: 0.9em; color: var(--text-muted); }

        /* Paragraphs */
        p {
            margin: 0 0 16px;
        }

        /* Links */
        a {
            color: var(--accent);
            text-decoration: none;
            transition: opacity 0.15s ease;
        }

        a:hover {
            text-decoration: underline;
            text-underline-offset: 3px;
        }

        /* Code */
        code {
            font-family: "SF Mono", Monaco, Menlo, Consolas, "Liberation Mono", monospace;
            font-size: 0.875em;
            background-color: var(--bg-code);
            padding: 0.15em 0.4em;
            border-radius: 6px;
            border: 1px solid var(--border-subtle);
        }

        pre {
            background-color: var(--bg-elevated);
            border: 1px solid var(--border);
            border-radius: 8px;
            padding: 16px 20px;
            overflow-x: auto;
            margin: 20px 0;
            position: relative;
        }

        pre code {
            background-color: transparent;
            padding: 0;
            border: none;
            font-size: 0.85em;
            line-height: 1.5;
        }

        /* Blockquotes */
        blockquote {
            margin: 20px 0;
            padding: 4px 20px;
            color: var(--text-secondary);
            border-left: 3px solid var(--accent-muted);
            background-color: rgba(88, 166, 255, 0.04);
            border-radius: 0 6px 6px 0;
        }

        blockquote p:last-child {
            margin-bottom: 0;
        }

        /* Lists */
        ul, ol {
            margin: 0 0 16px;
            padding-left: 1.75em;
        }

        li {
            margin: 6px 0;
        }

        li > p {
            margin: 8px 0;
        }

        ul ul, ol ol, ul ol, ol ul {
            margin-bottom: 0;
        }

        /* Horizontal rule */
        hr {
            height: 1px;
            background: linear-gradient(90deg, transparent, var(--border), transparent);
            border: none;
            margin: 32px 0;
        }

        /* Tables */
        table {
            border-collapse: collapse;
            width: 100%;
            margin: 20px 0;
            font-size: 0.95em;
        }

        th, td {
            border: 1px solid var(--border);
            padding: 10px 14px;
            text-align: left;
        }

        th {
            background-color: var(--bg-elevated);
            font-weight: 600;
            color: var(--text-primary);
        }

        tr:nth-child(even) {
            background-color: rgba(22, 27, 34, 0.4);
        }

        /* Images */
        img {
            max-width: 100%;
            height: auto;
            border-radius: 8px;
            margin: 16px 0;
            border: 1px solid var(--border-subtle);
        }

        /* Task lists */
        .task-list-item {
            list-style: none;
            margin-left: -1.5em;
        }

        .task-list-item input[type="checkbox"] {
            margin-right: 8px;
            accent-color: var(--accent);
        }

        /* Keyboard */
        kbd {
            display: inline-block;
            padding: 3px 6px;
            font-family: "SF Mono", monospace;
            font-size: 0.85em;
            color: var(--text-primary);
            background-color: var(--bg-elevated);
            border: 1px solid var(--border);
            border-radius: 4px;
            box-shadow: inset 0 -1px 0 var(--border);
        }

        /* Selection */
        ::selection {
            background-color: var(--accent-muted);
        }

        /* Scrollbar */
        ::-webkit-scrollbar {
            width: 10px;
            height: 10px;
        }

        ::-webkit-scrollbar-track {
            background: transparent;
        }

        ::-webkit-scrollbar-thumb {
            background: var(--border);
            border-radius: 5px;
            border: 2px solid var(--bg-primary);
        }

        ::-webkit-scrollbar-thumb:hover {
            background: var(--text-muted);
        }
        """
    }
}

#Preview {
    MarkdownPanelView(
        content: .constant("""
        # Project Documentation

        This is a **markdown** preview with Warp-inspired styling.

        ## Features

        - Clean typography
        - Syntax highlighting
        - Dark theme

        ```swift
        func greet(name: String) -> String {
            return "Hello, \\(name)!"
        }
        ```

        > Pro tip: Use keyboard shortcuts for efficiency.

        | Feature | Status |
        |---------|--------|
        | Themes  | Done   |
        | Search  | WIP    |
        """),
        filePath: "/Users/demo/project/README.md",
        onClose: {},
        onRefresh: {}
    )
    .frame(width: 500, height: 700)
}
