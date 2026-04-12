// ───────────────────────────────────────────────────────────────────────────────
// PreviewPanelView.swift — Main preview area (right side of split view)
// ───────────────────────────────────────────────────────────────────────────────
// This view decides HOW to preview the currently selected file based on its
// type. It delegates to WebPreviewView for actual rendering.
//
// Preview logic:
//   1. No file selected → show "Select a file" placeholder
//   2. HTML file → load via custom scheme (rk:///) in WKWebView
//   3. Markdown → convert to HTML, display in WKWebView
//   4. CSS/JS/TS → syntax-highlight as HTML, display in WKWebView
//   5. JSON → pretty-print + highlight, display in WKWebView
//   6. Images → render as <img> in WKWebView
//   7. JSX/TSX → show sandbox or dev server controls
//   8. Dev server running → show dev server URL in WKWebView
// ───────────────────────────────────────────────────────────────────────────────

import SwiftUI

struct PreviewPanelView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // ── Main Preview Content ──
            previewContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // ── Terminal Panel (collapsible) ──
            if appState.showTerminal {
                Divider()
                TerminalOutputView(
                    logs: activeLogs,
                    onClear: {
                        appState.devServer.logs = []
                        appState.sandbox.logs = []
                    },
                    onStop: {
                        appState.stopDevServer()
                        appState.stopSandboxPreview()
                    },
                    isRunning: appState.devServer.isRunning || appState.sandbox.isReady
                )
            }
        }
    }

    // MARK: - Preview Content Router

    @ViewBuilder
    private var previewContent: some View {
        // Priority 1: If dev server is running and has a URL, show that
        if let devURL = appState.devServer.serverURL, appState.devServer.isRunning {
            WebPreviewView(
                url: devURL,
                htmlString: nil,
                reloadTrigger: appState.reloadTrigger
            )
        }
        // Priority 2: If sandbox is running and has a URL, show that
        else if let sandboxURL = appState.sandbox.serverURL, appState.sandbox.isReady {
            WebPreviewView(
                url: sandboxURL,
                htmlString: nil,
                reloadTrigger: appState.reloadTrigger
            )
        }
        // Priority 3: Code Pad is active — render pasted code
        else if appState.isCodePadActive && !appState.codePadText.isEmpty {
            codePadPreview
        }
        // Priority 4: Show selected file preview
        else if let file = appState.selectedFile {
            previewForFile(file)
        }
        // Priority 5: Code Pad active but empty — show hint
        else if appState.isCodePadActive {
            codePadEmptyView
        }
        // Priority 6: No file selected
        else {
            noSelectionView
        }
    }

    @ViewBuilder
    private func previewForFile(_ file: FileNode) -> some View {
        let mode = FileTypeHelper.previewMode(for: file.fileExtension)

        switch mode {
        case .webRender:
            // HTML: Load via custom scheme so relative paths work
            if let schemeURL = LocalFileSchemeHandler.schemeURL(for: file.url) {
                WebPreviewView(
                    url: schemeURL,
                    htmlString: nil,
                    reloadTrigger: appState.reloadTrigger
                )
            }

        case .markdownRender:
            // Markdown: Convert to HTML and display
            if let content = try? String(contentsOf: file.url, encoding: .utf8) {
                let baseURL = file.url.deletingLastPathComponent()
                let html = MarkdownRenderer.render(content, baseURL: baseURL)
                WebPreviewView(
                    url: nil,
                    htmlString: html,
                    reloadTrigger: appState.reloadTrigger
                )
            }

        case .syntaxHighlight:
            // Source code: Syntax-highlight and display
            if let content = try? String(contentsOf: file.url, encoding: .utf8) {
                let lang = FileTypeHelper.languageIdentifier(for: file.fileExtension)
                let html = syntaxHighlightHTML(code: content, language: lang, fileName: file.name)
                WebPreviewView(
                    url: nil,
                    htmlString: html,
                    reloadTrigger: appState.reloadTrigger
                )
            }

        case .jsonPretty:
            // JSON: Pretty-print then syntax-highlight
            if let content = try? String(contentsOf: file.url, encoding: .utf8) {
                let pretty = prettyPrintJSON(content) ?? content
                let html = syntaxHighlightHTML(code: pretty, language: "json", fileName: file.name)
                WebPreviewView(
                    url: nil,
                    htmlString: html,
                    reloadTrigger: appState.reloadTrigger
                )
            }

        case .imagePreview:
            // Image: Render as <img> tag via custom scheme
            if let schemeURL = LocalFileSchemeHandler.schemeURL(for: file.url) {
                let html = imagePreviewHTML(imageURL: schemeURL, fileName: file.name)
                WebPreviewView(
                    url: nil,
                    htmlString: html,
                    reloadTrigger: appState.reloadTrigger
                )
            }

        case .reactComponent:
            // JSX/TSX: If a dev server is running, it takes priority (handled above).
            // Otherwise, render inline using Babel + React UMD (same as Code Pad).
            if let content = try? String(contentsOf: file.url, encoding: .utf8) {
                let isTSX = file.fileExtension == "tsx"
                let html = codePadReactHTML(code: content, isTSX: isTSX)
                if let fileURL = writeTempHTML(html, name: "preview-react.html") {
                    WebPreviewView(url: fileURL, htmlString: nil, reloadTrigger: appState.reloadTrigger)
                } else {
                    WebPreviewView(url: nil, htmlString: html, reloadTrigger: appState.reloadTrigger)
                }
            }

        case .unsupported:
            unsupportedFileView(file)
        }
    }

    // MARK: - React Component Preview Options

    @ViewBuilder
    private func reactComponentView(for file: FileNode) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "atom")
                .font(.system(size: 48))
                .foregroundColor(.cyan)

            Text(file.name)
                .font(.title2.bold())

            if let info = appState.projectInfo, info.hasDevServer {
                // This is part of a project — offer dev server
                VStack(spacing: 12) {
                    Text("This file is part of a \(info.kind.description) project.")
                        .foregroundColor(.secondary)

                    if appState.devServer.isRunning {
                        Label("Dev server is running", systemImage: "bolt.fill")
                            .foregroundColor(.green)
                        if appState.devServer.serverURL == nil {
                            ProgressView("Waiting for server URL...")
                        }
                    } else {
                        Button(action: { appState.startDevServer() }) {
                            Label("Run Dev Server", systemImage: "play.fill")
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)

                        if let cmd = info.devCommand {
                            Text("Will run: `\(cmd)`")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } else {
                // Standalone file — offer sandbox
                VStack(spacing: 12) {
                    Text("This JSX/TSX file is not part of a detected project.")
                        .foregroundColor(.secondary)

                    if appState.sandbox.isInstalling {
                        ProgressView("Installing sandbox dependencies...")
                    } else if appState.sandbox.isReady {
                        Label("Sandbox preview running", systemImage: "bolt.fill")
                            .foregroundColor(.green)
                    } else {
                        Button(action: { appState.startSandboxPreview(for: file) }) {
                            Label("Preview in Sandbox", systemImage: "play.fill")
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)

                        Text("Creates a minimal Vite+React sandbox to render this component.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if !DevServerManager.isNodeInstalled() {
                            Label("Node.js required — install from nodejs.org", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }

                    if let error = appState.sandbox.error {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(8)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(6)
                    }
                }
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Placeholder Views

    private var noSelectionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "cursorarrow.click.2")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            Text("Select a file to preview")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("Choose a file from the sidebar, or press ⌘O to open a folder.")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func unsupportedFileView(_ file: FileNode) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.questionmark")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Cannot preview .\(file.fileExtension) files")
                .font(.title3)
                .foregroundColor(.secondary)
            Text(file.url.path)
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
                .lineLimit(2)
                .truncationMode(.middle)

            Button("Open in Default App") {
                NSWorkspace.shared.open(file.url)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - HTML Generators

    /// Generate HTML with syntax highlighting using a simple CSS-based approach.
    /// We use <pre><code> with HTML-escaped content and a monospace font.
    /// For a more complete solution, you'd embed Prism.js or highlight.js.
    private func syntaxHighlightHTML(code: String, language: String, fileName: String) -> String {
        let escaped = code
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        :root { color-scheme: light dark; }
        body {
            font-family: 'SF Mono', Menlo, Monaco, 'Courier New', monospace;
            font-size: 13px;
            line-height: 1.6;
            margin: 0;
            padding: 0;
            background: #fafafa;
            color: #1d1d1f;
        }
        @media (prefers-color-scheme: dark) {
            body { background: #1c1c1e; color: #f5f5f7; }
            .header { background: #2c2c2e; border-color: #38383a; }
            pre { background: #1c1c1e; }
            .line-number { color: #48484a; border-color: #38383a; }
        }
        .header {
            padding: 8px 16px;
            background: #f2f2f7;
            border-bottom: 1px solid #d1d1d6;
            font-family: -apple-system, sans-serif;
            font-size: 12px;
            color: #6e6e73;
        }
        .lang-badge {
            display: inline-block;
            padding: 1px 6px;
            background: rgba(0,113,227,0.1);
            color: #0071e3;
            border-radius: 4px;
            font-size: 11px;
            margin-left: 8px;
        }
        pre {
            margin: 0;
            padding: 12px 16px;
            overflow-x: auto;
            tab-size: 4;
            white-space: pre;
        }
        </style>
        </head>
        <body>
        <div class="header">
            \(fileName)
            <span class="lang-badge">\(language)</span>
        </div>
        <pre><code>\(escaped)</code></pre>
        </body>
        </html>
        """
    }

    /// Pretty-print a JSON string, or return nil if it's not valid JSON.
    private func prettyPrintJSON(_ input: String) -> String? {
        guard let data = input.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8)
        else { return nil }
        return str
    }

    /// Generate HTML that displays an image centered with its filename.
    private func imagePreviewHTML(imageURL: URL, fileName: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        :root { color-scheme: light dark; }
        body {
            font-family: -apple-system, sans-serif;
            display: flex; flex-direction: column;
            align-items: center; justify-content: center;
            min-height: 100vh; margin: 0; padding: 20px;
            background: #fafafa; color: #1d1d1f;
        }
        @media (prefers-color-scheme: dark) {
            body { background: #1c1c1e; color: #f5f5f7; }
        }
        img {
            max-width: 100%; max-height: 80vh;
            border-radius: 8px;
            box-shadow: 0 4px 20px rgba(0,0,0,0.1);
        }
        .filename {
            margin-top: 16px; font-size: 13px; color: #6e6e73;
        }
        /* Checkerboard background for transparent images */
        .checker {
            background-image:
                linear-gradient(45deg, #ccc 25%, transparent 25%),
                linear-gradient(-45deg, #ccc 25%, transparent 25%),
                linear-gradient(45deg, transparent 75%, #ccc 75%),
                linear-gradient(-45deg, transparent 75%, #ccc 75%);
            background-size: 16px 16px;
            background-position: 0 0, 0 8px, 8px -8px, -8px 0;
            border-radius: 8px; padding: 8px;
        }
        </style>
        </head>
        <body>
        <div class="checker">
            <img src="\(imageURL.absoluteString)" alt="\(fileName)">
        </div>
        <div class="filename">\(fileName)</div>
        </body>
        </html>
        """
    }

    // MARK: - Code Pad Preview

    @ViewBuilder
    private var codePadPreview: some View {
        let code = appState.codePadText
        let lang = appState.codePadLanguage

        switch lang {
        case .html:
            WebPreviewView(url: nil, htmlString: code, reloadTrigger: appState.reloadTrigger)

        case .svg:
            let html = "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><style>:root{color-scheme:light dark}body{margin:0;display:flex;align-items:center;justify-content:center;min-height:100vh;background:#fafafa}@media(prefers-color-scheme:dark){body{background:#1c1c1e}}</style></head><body>" + code + "</body></html>"
            WebPreviewView(url: nil, htmlString: html, reloadTrigger: appState.reloadTrigger)

        case .css:
            let html = codePadCSSHTML(css: code)
            WebPreviewView(url: nil, htmlString: html, reloadTrigger: appState.reloadTrigger)

        case .js:
            let html = codePadJSHTML(js: code)
            WebPreviewView(url: nil, htmlString: html, reloadTrigger: appState.reloadTrigger)

        case .jsx, .tsx:
            // JSX/TSX needs CDN scripts (React, Babel) — loadHTMLString blocks
            // external resources, so we write to a temp file and load via file:// URL.
            // allowUniversalAccessFromFileURLs in WebPreviewView allows the fetch.
            let html = codePadReactHTML(code: code, isTSX: lang == .tsx)
            if let fileURL = writeTempHTML(html, name: "codepad-react.html") {
                WebPreviewView(url: fileURL, htmlString: nil, reloadTrigger: appState.reloadTrigger)
            } else {
                WebPreviewView(url: nil, htmlString: html, reloadTrigger: appState.reloadTrigger)
            }

        case .markdown:
            let html = MarkdownRenderer.render(code, baseURL: nil)
            WebPreviewView(url: nil, htmlString: html, reloadTrigger: appState.reloadTrigger)

        case .json:
            let pretty = prettyPrintJSON(code) ?? code
            let html = syntaxHighlightHTML(code: pretty, language: "json", fileName: "Code Pad")
            WebPreviewView(url: nil, htmlString: html, reloadTrigger: appState.reloadTrigger)
        }
    }

    private var codePadEmptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.accentColor.opacity(0.5))
            Text("Paste code to preview")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("Type or paste code in the editor on the left.\nIt will render here automatically.")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Code Pad HTML Generators

    private func codePadCSSHTML(css: String) -> String {
        let escapedCSS = css.replacingOccurrences(of: "</", with: "<\\/")
        return "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><style>:root{color-scheme:light dark}body{font-family:-apple-system,sans-serif;padding:24px;margin:0;background:#fafafa;color:#1d1d1f}@media(prefers-color-scheme:dark){body{background:#1c1c1e;color:#f5f5f7}}</style><style>" + escapedCSS + "</style></head><body><h1>Heading 1</h1><h2>Heading 2</h2><h3>Heading 3</h3><p>This is a paragraph with <strong>bold</strong>, <em>italic</em>, and <a href=\"#\">links</a>.</p><ul><li>List item one</li><li>List item two</li><li>List item three</li></ul><button>Button</button> <input type=\"text\" placeholder=\"Text input\" /><div class=\"container\"><div class=\"box\">Box 1</div><div class=\"box\">Box 2</div><div class=\"box\">Box 3</div></div><table><tr><th>Name</th><th>Value</th></tr><tr><td>Alpha</td><td>100</td></tr><tr><td>Beta</td><td>200</td></tr></table><pre><code>code block { display: block; }</code></pre><blockquote>This is a blockquote.</blockquote></body></html>"
    }

    private func codePadJSHTML(js: String) -> String {
        let escapedJS = js
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "</", with: "<\\/")
        return codePadJSTemplate(escapedJS: escapedJS)
    }

    private func codePadJSTemplate(escapedJS: String) -> String {
        return "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><style>:root{color-scheme:light dark}body{font-family:'SF Mono',Menlo,monospace;font-size:13px;margin:0;padding:0;background:#1c1c1e;color:#f5f5f7}#console{padding:16px;white-space:pre-wrap;word-break:break-word}.log{color:#f5f5f7;margin:2px 0}.warn{color:#ffd60a;margin:2px 0}.error{color:#ff453a;margin:2px 0}.info{color:#64d2ff;margin:2px 0}.header{padding:8px 16px;background:#2c2c2e;border-bottom:1px solid #38383a;font-family:-apple-system,sans-serif;font-size:12px;color:#6e6e73}.result{color:#30d158;margin:4px 0;padding-top:8px;border-top:1px solid #38383a}</style></head><body><div class=\"header\">Console Output</div><div id=\"console\"></div><script>(function(){var o=document.getElementById('console');function a(c,g){var l=document.createElement('div');l.className=c;l.textContent=Array.from(g).map(function(x){if(typeof x==='object')try{return JSON.stringify(x,null,2)}catch(e){}return String(x)}).join(' ');o.appendChild(l)}var _l=console.log,_w=console.warn,_e=console.error,_i=console.info;console.log=function(){a('log',arguments);_l.apply(console,arguments)};console.warn=function(){a('warn',arguments);_w.apply(console,arguments)};console.error=function(){a('error',arguments);_e.apply(console,arguments)};console.info=function(){a('info',arguments);_i.apply(console,arguments)};try{var __r=eval(\"" + escapedJS + "\");if(__r!==undefined){var r=document.createElement('div');r.className='result';r.textContent='\\u2192 '+(typeof __r==='object'?JSON.stringify(__r,null,2):String(__r));o.appendChild(r)}}catch(e){a('error',['Error: '+e.message])}})()</script></body></html>"
    }

    private func codePadReactHTML(code: String, isTSX: Bool) -> String {
        let safeCode = code.replacingOccurrences(of: "</script", with: "<\\/script")
        let presets = isTSX ? "env, react, typescript" : "env, react"

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        * { box-sizing: border-box; }
        #root { min-height: 100vh; }
        #error { color: #ff453a; font-family: 'SF Mono', monospace; font-size: 13px;
                 padding: 16px; white-space: pre-wrap; background: rgba(255,69,58,0.1);
                 margin: 16px; border-radius: 8px; display: none; }
        .loading { text-align: center; padding: 40px; color: #6e6e73;
                   font-family: -apple-system, sans-serif; }
        </style>
        </head>
        <body style="margin:0; padding:0;">
        <div id="root"><div class="loading">Loading React...</div></div>
        <div id="error"></div>

        <script src="https://unpkg.com/react@18/umd/react.development.js"></script>
        <script src="https://unpkg.com/react-dom@18/umd/react-dom.development.js"></script>
        <script src="https://unpkg.com/@babel/standalone/babel.min.js"></script>

        <script>
        // --- Module shim ---
        // Babel transpiles `import X from "react"` into `require("react")`.
        // Since there is no bundler here, we shim require() to return the UMD globals.
        var __modules = {
            'react': React,
            'react-dom': ReactDOM,
            'react-dom/client': ReactDOM,
            'react/jsx-runtime': { jsx: React.createElement, jsxs: React.createElement, Fragment: React.Fragment }
        };
        function require(name) {
            if (__modules[name]) return __modules[name];
            throw new Error('Module not found: ' + name);
        }
        var exports = {};
        var module = { exports: exports };
        Object.defineProperty(exports, '__esModule', { value: true });

        window.onerror = function(msg, src, line, col, err) {
            var rootEl = document.getElementById('root');
            if (rootEl) rootEl.textContent = '';
            var d = document.getElementById('error');
            if (d) { d.style.display = 'block'; d.textContent = (err && err.message) || msg; }
            return true;
        };
        </script>

        <script type="text/babel" data-presets="\(presets)">
        \(safeCode)
        </script>

        <script>
        // Mount the component after Babel finishes processing.
        function __tryMount() {
            var C = (module.exports && module.exports.default) || exports.default || null;
            if (!C) {
                var keys = Object.keys(exports).filter(function(k) { return k !== '__esModule' && k !== 'default'; });
                for (var i = 0; i < keys.length; i++) {
                    if (typeof exports[keys[i]] === 'function') { C = exports[keys[i]]; break; }
                }
            }
            if (C && typeof C === 'function') {
                try {
                    ReactDOM.createRoot(document.getElementById('root')).render(React.createElement(C));
                } catch(e) {
                    var d = document.getElementById('error');
                    d.style.display = 'block'; d.textContent = e.message;
                }
            } else {
                var rootEl = document.getElementById('root');
                if (rootEl && rootEl.querySelector('.loading')) {
                    rootEl.textContent = 'No component found. Use export default on your component.';
                    rootEl.style.cssText = 'color:#999;padding:16px;font-family:-apple-system,sans-serif;';
                }
            }
        }
        var __n = 0;
        function __poll() {
            __n++;
            if (Object.keys(exports).length > 1 || __n > 50) { __tryMount(); }
            else { setTimeout(__poll, 100); }
        }
        setTimeout(__poll, 200);
        </script>
        </body>
        </html>
        """
    }

    // MARK: - Temp File Helper

    /// Write HTML to a temp file so we can load it via rk:// scheme
    /// (which allows external CDN scripts to load, unlike loadHTMLString).
    private func writeTempHTML(_ html: String, name: String) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("renderkit-codepad", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent(name)
        do {
            try html.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("[CodePad] Failed to write temp file: \(error)")
            return nil
        }
    }

    // MARK: - Active Logs

    /// Returns whichever log source is currently active.
    private var activeLogs: [String] {
        if !appState.sandbox.logs.isEmpty {
            return appState.sandbox.logs
        }
        return appState.devServer.logs
    }
}
