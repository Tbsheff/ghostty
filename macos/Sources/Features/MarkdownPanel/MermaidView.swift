import SwiftUI
import WebKit

// MARK: - Mermaid Block View

/// A wrapper view that manages the dynamic height of the MermaidView
struct MermaidBlockView: View {
    let code: String
    let theme: MarkdownTheme

    @State private var height: CGFloat = 200
    @State private var isHovered = false
    @State private var copied = false
    @State private var loadFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with label and copy button
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 10, weight: .medium))
                    Text("MERMAID")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                .foregroundColor(theme.textMuted)

                Spacer()

                Button(action: copyCode) {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10, weight: .medium))
                        if copied {
                            Text("Copied!")
                                .font(.system(size: 10, weight: .medium))
                        }
                    }
                    .foregroundColor(copied ? theme.success : theme.textMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(theme.surfaceElevated.opacity(isHovered ? 1 : 0))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .opacity(isHovered || copied ? 1 : 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            // Mermaid diagram or fallback
            if loadFailed {
                // Fallback: show raw code
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(theme.textPrimary)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            } else {
                MermaidView(code: code, theme: theme, height: $height, loadFailed: $loadFailed)
                    .frame(height: height)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
            }
        }
        .background(theme.codeBackground)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.border, lineWidth: 1)
        )
        .padding(.vertical, 12)
        .onHover { isHovered = $0 }
    }

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        copied = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }
}

// MARK: - Mermaid WebView

/// NSViewRepresentable wrapper for WKWebView that renders Mermaid diagrams
struct MermaidView: NSViewRepresentable {
    let code: String
    let theme: MarkdownTheme
    @Binding var height: CGFloat
    @Binding var loadFailed: Bool

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let contentController = configuration.userContentController
        // Use a weak wrapper to break the retain cycle between
        // WKUserContentController -> Coordinator -> MermaidView
        let weakHandler = WeakScriptMessageHandler(context.coordinator)
        contentController.add(weakHandler, name: "heightHandler")
        contentController.add(weakHandler, name: "errorHandler")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")

        // Make WebView transparent
        if let scrollView = webView.enclosingScrollView {
            scrollView.drawsBackground = false
        }

        loadMermaid(in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Reload if code or theme changes
        if context.coordinator.lastCode != code || context.coordinator.lastTheme != mermaidTheme {
            context.coordinator.lastCode = code
            context.coordinator.lastTheme = mermaidTheme
            loadMermaid(in: webView)
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        // CRITICAL: Remove message handlers to break retain cycle
        let contentController = webView.configuration.userContentController
        contentController.removeScriptMessageHandler(forName: "heightHandler")
        contentController.removeScriptMessageHandler(forName: "errorHandler")
        // Clear navigation delegate to avoid dangling reference
        webView.navigationDelegate = nil
        // Stop any pending loads
        webView.stopLoading()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private var mermaidTheme: String {
        theme.colorScheme == .dark ? "dark" : "default"
    }

    private var backgroundColor: String {
        theme.colorScheme == .dark ? "#1E1E20" : "#F6F8FA"
    }

    private var textColor: String {
        theme.colorScheme == .dark ? "#E5E5E7" : "#1D1D1F"
    }

    private func loadMermaid(in webView: WKWebView) {
        // Escape the mermaid code for safe embedding in HTML
        let escapedCode = code
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
                * {
                    margin: 0;
                    padding: 0;
                    box-sizing: border-box;
                }
                html, body {
                    background: transparent;
                    overflow: hidden;
                }
                #container {
                    display: flex;
                    justify-content: center;
                    align-items: flex-start;
                    min-height: 100px;
                }
                .mermaid {
                    background: transparent;
                }
                .mermaid svg {
                    max-width: 100%;
                    height: auto;
                }
                #error {
                    color: #FF453A;
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                    font-size: 13px;
                    padding: 16px;
                    display: none;
                }
                #loading {
                    color: \(textColor);
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                    font-size: 13px;
                    padding: 16px;
                    opacity: 0.6;
                }
            </style>
        </head>
        <body>
            <div id="loading">Loading diagram...</div>
            <div id="error"></div>
            <div id="container">
                <pre class="mermaid" id="mermaid-diagram">\(escapedCode)</pre>
            </div>
            <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
            <script>
                let loadTimeout = setTimeout(function() {
                    document.getElementById('loading').style.display = 'none';
                    document.getElementById('error').textContent = 'Failed to load Mermaid library (timeout)';
                    document.getElementById('error').style.display = 'block';
                    window.webkit.messageHandlers.errorHandler.postMessage('timeout');
                }, 10000);

                function initMermaid() {
                    clearTimeout(loadTimeout);
                    document.getElementById('loading').style.display = 'none';

                    mermaid.initialize({
                        startOnLoad: false,
                        theme: '\(mermaidTheme)',
                        securityLevel: 'loose',
                        fontFamily: '-apple-system, BlinkMacSystemFont, sans-serif',
                        themeVariables: {
                            background: 'transparent',
                            primaryColor: '\(theme.colorScheme == .dark ? "#0A84FF" : "#007AFF")',
                            primaryTextColor: '\(textColor)',
                            primaryBorderColor: '\(theme.colorScheme == .dark ? "#38383A" : "#D1D1D6")',
                            lineColor: '\(theme.colorScheme == .dark ? "#636366" : "#8E8E93")',
                            secondaryColor: '\(theme.colorScheme == .dark ? "#2C2C2E" : "#F5F5F7")',
                            tertiaryColor: '\(theme.colorScheme == .dark ? "#3A3A3C" : "#E5E5EA")'
                        }
                    });

                    mermaid.run({
                        nodes: [document.getElementById('mermaid-diagram')]
                    }).then(function() {
                        reportHeight();
                    }).catch(function(error) {
                        document.getElementById('error').textContent = 'Diagram error: ' + error.message;
                        document.getElementById('error').style.display = 'block';
                        document.getElementById('container').style.display = 'none';
                        window.webkit.messageHandlers.errorHandler.postMessage(error.message);
                    });
                }

                function reportHeight() {
                    const container = document.getElementById('container');
                    const svg = container.querySelector('svg');
                    if (svg) {
                        const height = Math.max(svg.getBoundingClientRect().height, 100);
                        window.webkit.messageHandlers.heightHandler.postMessage(height);
                    } else {
                        window.webkit.messageHandlers.heightHandler.postMessage(200);
                    }
                }

                // Check if mermaid loaded
                if (typeof mermaid !== 'undefined') {
                    initMermaid();
                } else {
                    // Wait for script to load
                    window.addEventListener('load', function() {
                        if (typeof mermaid !== 'undefined') {
                            initMermaid();
                        } else {
                            clearTimeout(loadTimeout);
                            document.getElementById('loading').style.display = 'none';
                            document.getElementById('error').textContent = 'Failed to load Mermaid library';
                            document.getElementById('error').style.display = 'block';
                            window.webkit.messageHandlers.errorHandler.postMessage('load_failed');
                        }
                    });
                }

                // Handle window resize
                window.addEventListener('resize', reportHeight);
            </script>
        </body>
        </html>
        """

        webView.loadHTMLString(html, baseURL: nil)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        // Note: This is effectively a weak reference to the parent because
        // NSViewRepresentable recreates MermaidView structs on each update.
        // The bindings (height, loadFailed) are the real owners of state.
        var parent: MermaidView
        var lastCode: String = ""
        var lastTheme: String = ""

        init(_ parent: MermaidView) {
            self.parent = parent
            self.lastCode = parent.code
            self.lastTheme = parent.theme.colorScheme == .dark ? "dark" : "default"
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "heightHandler", let height = message.body as? CGFloat {
                DispatchQueue.main.async {
                    self.parent.height = max(height + 20, 100) // Add padding
                }
            } else if message.name == "errorHandler" {
                DispatchQueue.main.async {
                    self.parent.loadFailed = true
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.loadFailed = true
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.loadFailed = true
            }
        }
    }
}

// MARK: - Weak Script Message Handler

/// Wrapper that holds a weak reference to the actual message handler.
/// This breaks the retain cycle: WKUserContentController -> WeakScriptMessageHandler -weak-> Coordinator
/// Without this, WKUserContentController holds a strong reference to the handler, causing leaks.
private class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var delegate: WKScriptMessageHandler?

    init(_ delegate: WKScriptMessageHandler) {
        self.delegate = delegate
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
