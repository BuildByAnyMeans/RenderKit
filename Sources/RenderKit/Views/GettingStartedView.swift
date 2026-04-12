// ───────────────────────────────────────────────────────────────────────────────
// GettingStartedView.swift — Welcome screen with instructions
// ───────────────────────────────────────────────────────────────────────────────
// Shown when no folder is open. Provides:
//   - Quick-start instructions
//   - Keyboard shortcuts
//   - Troubleshooting tips
//   - System requirements status (Node.js, npm)
// ───────────────────────────────────────────────────────────────────────────────

import SwiftUI

struct GettingStartedView: View {
    @ObservedObject var appState: AppState

    @State private var nodeInstalled: Bool? = nil
    @State private var npmInstalled: Bool? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer().frame(height: 60)

                // ── App Icon & Title ──
                VStack(spacing: 12) {
                    Image(systemName: "eye.trianglebadge.exclamationmark")
                        .font(.system(size: 56))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Text("RenderKit")
                        .font(.system(size: 36, weight: .bold, design: .rounded))

                    Text("Preview front-end files natively on your Mac")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }

                Spacer().frame(height: 40)

                // ── Quick Start ──
                sectionCard(title: "Quick Start", icon: "bolt.fill") {
                    instructionRow(step: "1", text: "Click **Open Folder** or press **⌘O** to select a project")
                    instructionRow(step: "2", text: "Click any file in the sidebar to preview it")
                    instructionRow(step: "3", text: "Enable **Live Reload** to auto-refresh on save")
                    instructionRow(step: "4", text: "For React projects, click **Run Dev Server**")
                }

                // ── Supported Files ──
                sectionCard(title: "Supported Files", icon: "doc.text.fill") {
                    fileTypeRow(ext: ".html", desc: "Full web page rendering with CSS/JS/assets")
                    fileTypeRow(ext: ".css / .js / .ts", desc: "Syntax-highlighted source view")
                    fileTypeRow(ext: ".md", desc: "Rendered Markdown preview")
                    fileTypeRow(ext: ".json", desc: "Pretty-printed JSON view")
                    fileTypeRow(ext: ".jsx / .tsx", desc: "React component preview (via dev server or sandbox)")
                    fileTypeRow(ext: "Images", desc: "PNG, JPG, GIF, WebP, SVG display")
                }

                // ── System Status ──
                sectionCard(title: "System Status", icon: "gear") {
                    systemStatusRow(label: "Node.js", installed: nodeInstalled)
                    systemStatusRow(label: "npm", installed: npmInstalled)
                    if nodeInstalled == false || npmInstalled == false {
                        Text("Node.js is needed for React/JSX preview and dev servers.\nInstall from [nodejs.org](https://nodejs.org) or via Homebrew: `brew install node`")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                }

                // ── Troubleshooting ──
                sectionCard(title: "Troubleshooting", icon: "wrench.fill") {
                    troubleshootRow(
                        problem: "Dev server won't start",
                        solution: "Make sure `node` and `npm` are in your PATH. Try running `npm run dev` in Terminal first."
                    )
                    troubleshootRow(
                        problem: "HTML preview is blank",
                        solution: "Check that all CSS/JS files referenced exist. Open the Console (⌘⌥C) to see errors."
                    )
                    troubleshootRow(
                        problem: "Port already in use",
                        solution: "Another process is using the port. Run `lsof -i :3000` to find it, or change the port in your project config."
                    )
                    troubleshootRow(
                        problem: "Live reload not working",
                        solution: "Make sure the toggle is ON in the toolbar. Files in node_modules and .git are ignored."
                    )
                    troubleshootRow(
                        problem: "JSX sandbox fails to install",
                        solution: "Check your internet connection. The sandbox needs to download React and Vite on first use (~30s)."
                    )
                }

                // ── Keyboard Shortcuts ──
                sectionCard(title: "Keyboard Shortcuts", icon: "keyboard") {
                    shortcutRow(key: "⌘O", action: "Open Folder")
                    shortcutRow(key: "⌘R", action: "Refresh Preview")
                    shortcutRow(key: "⌘L", action: "Toggle Live Reload")
                    shortcutRow(key: "⌘T", action: "Toggle Terminal")
                    shortcutRow(key: "⇧⌘C", action: "Copy File Path")
                }

                Spacer().frame(height: 40)

                // ── Open Folder Button ──
                Button(action: { appState.showOpenFolderPanel() }) {
                    Label("Open Folder", systemImage: "folder.badge.plus")
                        .font(.title3)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Spacer().frame(height: 60)
            }
            .frame(maxWidth: 640)
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            // Check Node/npm in background
            DispatchQueue.global().async {
                let node = DevServerManager.isNodeInstalled()
                let npm = DevServerManager.isNpmInstalled()
                DispatchQueue.main.async {
                    nodeInstalled = node
                    npmInstalled = npm
                }
            }
        }
    }

    // MARK: - Reusable Components

    @ViewBuilder
    private func sectionCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)
                .padding(.bottom, 4)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .padding(.bottom, 12)
    }

    private func instructionRow(step: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(step)
                .font(.system(.caption, design: .rounded).bold())
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.15))
                .cornerRadius(6)
            Text(LocalizedStringKey(text))
                .font(.body)
        }
        .padding(.vertical, 2)
    }

    private func fileTypeRow(ext: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(ext)
                .font(.system(.caption, design: .monospaced).bold())
                .foregroundColor(.accentColor)
                .frame(minWidth: 90, alignment: .leading)
            Text(desc)
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func systemStatusRow(label: String, installed: Bool?) -> some View {
        HStack(spacing: 8) {
            if let installed = installed {
                Image(systemName: installed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(installed ? .green : .red)
            } else {
                ProgressView()
                    .scaleEffect(0.6)
            }
            Text(label)
                .font(.body)
            Spacer()
            if let installed = installed {
                Text(installed ? "Installed" : "Not found")
                    .font(.caption)
                    .foregroundColor(installed ? .green : .red)
            }
        }
        .padding(.vertical, 2)
    }

    private func troubleshootRow(problem: String, solution: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(problem)
                .font(.body.bold())
            Text(solution)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func shortcutRow(key: String, action: String) -> some View {
        HStack {
            Text(key)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color(nsColor: .separatorColor).opacity(0.3))
                .cornerRadius(4)
            Text(action)
                .font(.body)
            Spacer()
        }
        .padding(.vertical, 2)
    }
}
