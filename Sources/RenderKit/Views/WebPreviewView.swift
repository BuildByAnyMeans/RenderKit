// ───────────────────────────────────────────────────────────────────────────────
// WebPreviewView.swift — WKWebView wrapper for SwiftUI
// ───────────────────────────────────────────────────────────────────────────────
// This is an NSViewRepresentable that bridges WKWebView into SwiftUI.
//
// Key design decisions:
//   - The WKWebView is created ONCE in makeNSView and reused across updates.
//     SwiftUI calls updateNSView frequently; recreating the web view each time
//     would be wasteful and cause flicker.
//   - We register our custom URL scheme handler ("rk") at init time so local
//     file loading goes through LocalFileSchemeHandler.
//   - The Coordinator acts as WKNavigationDelegate to handle errors gracefully.
//   - A "reload trigger" UUID from AppState lets us force a reload without
//     recreating the view.
// ───────────────────────────────────────────────────────────────────────────────

import SwiftUI
import WebKit

struct WebPreviewView: NSViewRepresentable {

    /// What to load. Can be a custom-scheme URL (rk:///) or a dev server URL (http://).
    let url: URL?

    /// Raw HTML string to load directly (used for markdown, code previews).
    let htmlString: String?

    /// Bumped to force a reload (live reload).
    let reloadTrigger: UUID

    // MARK: - NSViewRepresentable

    func makeNSView(context: Context) -> WKWebView {
        // Configure the web view with our custom scheme handler
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(LocalFileSchemeHandler(), forURLScheme: kRenderKitScheme)

        // Allow local file access and developer extras for debugging
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        // Allow pages loaded via custom schemes to fetch HTTPS resources
        // (needed for React/Babel CDN scripts in JSX preview)
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator

        // Transparent background to match SwiftUI theming
        webView.setValue(false, forKey: "drawsBackground")

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Check if we actually need to reload
        let currentTrigger = context.coordinator.lastTrigger
        guard reloadTrigger != currentTrigger else { return }
        context.coordinator.lastTrigger = reloadTrigger

        if let html = htmlString {
            // Load raw HTML string (markdown preview, syntax-highlighted code)
            webView.loadHTMLString(html, baseURL: nil)
        } else if let loadURL = url {
            if loadURL.isFileURL {
                // Local file: use loadFileURL to grant read access to containing directory
                // This allows the page to load external CDN scripts (unlike loadHTMLString)
                let accessDir = loadURL.deletingLastPathComponent()
                webView.loadFileURL(loadURL, allowingReadAccessTo: accessDir)
            } else {
                webView.load(URLRequest(url: loadURL))
            }
        } else {
            // Nothing to show — load a blank page
            webView.loadHTMLString("", baseURL: nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate {
        /// Tracks the last reload trigger to avoid redundant loads.
        var lastTrigger: UUID?

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            // Show a user-friendly error page instead of a blank screen
            let html = """
            <html>
            <body style="font-family:-apple-system,sans-serif;padding:40px;color:#888">
            <h2 style="color:#ff3b30">Preview Error</h2>
            <p>\(error.localizedDescription)</p>
            <p style="font-size:13px;margin-top:24px">
                Tip: If this is an HTML file with external resources, make sure all
                referenced files exist in the project folder.
            </p>
            </body>
            </html>
            """
            webView.loadHTMLString(html, baseURL: nil)
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            print("[WebPreview] Navigation failed: \(error.localizedDescription)")
        }

        /// Allow navigation to all URLs (needed for dev server links, anchor jumps, etc.)
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            // For external links (http/https that aren't our dev server), open in browser
            if let url = navigationAction.request.url,
               navigationAction.navigationType == .linkActivated,
               url.scheme == "http" || url.scheme == "https" {
                // Could open externally: NSWorkspace.shared.open(url)
                // For now, allow in-view navigation
            }
            decisionHandler(.allow)
        }
    }
}
