// ───────────────────────────────────────────────────────────────────────────────
// ContentView.swift — Main window layout
// ───────────────────────────────────────────────────────────────────────────────
// The root view of the app. Uses NavigationSplitView (macOS 13+) to create:
//   - LEFT:  File tree sidebar (FileTreeView)
//   - RIGHT: Preview panel (PreviewPanelView or GettingStartedView)
//
// Also provides the toolbar with buttons for common actions.
// ───────────────────────────────────────────────────────────────────────────────

import SwiftUI

struct ContentView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            // ── Sidebar ──
            if appState.isCodePadActive {
                CodePadView(appState: appState)
            } else if appState.rootFolder != nil {
                FileTreeView(appState: appState)
            } else {
                // No folder open — show a hint in the sidebar
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("Open a folder to start")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Open Folder") {
                        appState.showOpenFolderPanel()
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        } detail: {
            // ── Preview Area ──
            if appState.rootFolder != nil || appState.isCodePadActive {
                PreviewPanelView(appState: appState)
            } else {
                GettingStartedView(appState: appState)
            }
        }
        .navigationSplitViewColumnWidth(
            min: appState.isCodePadActive ? 200 : 140,
            ideal: appState.isCodePadActive ? 350 : 230,
            max: appState.isCodePadActive ? 700 : 400
        )
        .toolbar {
            toolbarContent
        }
        // ── Status Bar ──
        .safeAreaInset(edge: .bottom, spacing: 0) {
            statusBar
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Open Folder
        ToolbarItem(placement: .navigation) {
            Button(action: { appState.showOpenFolderPanel() }) {
                Label("Open Folder", systemImage: "folder.badge.plus")
            }
            .help("Open a project folder (⌘O)")
        }

        // Code Pad toggle
        ToolbarItem(placement: .navigation) {
            Button(action: {
                if appState.isCodePadActive {
                    appState.closeCodePad()
                } else {
                    appState.openCodePad()
                }
            }) {
                Label(
                    "Code Pad",
                    systemImage: appState.isCodePadActive ? "doc.text.fill" : "doc.text"
                )
            }
            .help("Toggle Code Pad — paste code to preview (⌘N)")
            .tint(appState.isCodePadActive ? .accentColor : nil)
        }

        // Refresh
        ToolbarItem(placement: .primaryAction) {
            Button(action: { appState.refreshPreview() }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Refresh preview (⌘R)")
        }

        // Live Reload Toggle
        ToolbarItem(placement: .primaryAction) {
            Toggle(isOn: $appState.isLiveReloadEnabled) {
                Label(
                    "Live Reload",
                    systemImage: appState.isLiveReloadEnabled ? "bolt.fill" : "bolt.slash"
                )
            }
            .toggleStyle(.button)
            .help("Toggle live reload (⌘L)")
            .tint(appState.isLiveReloadEnabled ? .green : nil)
        }

        // Dev Server (only for projects that support it)
        ToolbarItem(placement: .primaryAction) {
            if let info = appState.projectInfo, info.hasDevServer {
                Button(action: {
                    if appState.devServer.isRunning {
                        appState.stopDevServer()
                    } else {
                        appState.startDevServer()
                    }
                }) {
                    Label(
                        appState.devServer.isRunning ? "Stop Server" : "Run Dev Server",
                        systemImage: appState.devServer.isRunning ? "stop.fill" : "play.fill"
                    )
                }
                .help(appState.devServer.isRunning ? "Stop the dev server" : "Start the dev server")
                .tint(appState.devServer.isRunning ? .red : .blue)
            }
        }

        // Terminal Toggle
        ToolbarItem(placement: .primaryAction) {
            Toggle(isOn: $appState.showTerminal) {
                Label("Terminal", systemImage: "terminal")
            }
            .toggleStyle(.button)
            .help("Toggle terminal output (⌘T)")
        }

        // More Actions
        ToolbarItem(placement: .secondaryAction) {
            Menu {
                Button(action: { appState.copyFilePath() }) {
                    Label("Copy File Path", systemImage: "doc.on.clipboard")
                }
                .disabled(appState.selectedFile == nil)

                Button(action: { appState.openInExternalBrowser() }) {
                    Label("Open in Browser", systemImage: "safari")
                }
                .disabled(appState.selectedFile == nil && appState.devServer.serverURL == nil)

                Button(action: { appState.revealInFinder() }) {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                .disabled(appState.rootFolder == nil)

                Divider()

                if let info = appState.projectInfo {
                    Text("Project: \(info.kind.description)")
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 8) {
            // Live reload indicator
            if appState.isLiveReloadEnabled {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
                Text("Live")
                    .font(.system(size: 10))
                    .foregroundColor(.green)
            }

            // File info or Code Pad indicator
            if appState.isCodePadActive {
                Text("Code Pad — \(appState.codePadLanguage.displayName)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.accentColor)
                    .lineLimit(1)
            } else if let file = appState.selectedFile {
                Text(file.url.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer()

            // Status message
            Text(appState.statusMessage)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) { Divider() }
    }
}
