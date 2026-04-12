// ───────────────────────────────────────────────────────────────────────────────
// RenderKitApp.swift — App entry point
// ───────────────────────────────────────────────────────────────────────────────
// The @main struct that launches the SwiftUI app. Configures:
//   - The main window with a sensible default size
//   - Menu bar commands (File > Open, keyboard shortcuts)
//   - File drop handling (Dock icon, Finder "Open With")
//   - App lifecycle (cleanup on termination)
//
// Note: setActivationPolicy(.regular) is critical when launching via
// `swift run` — without it, the app window may not come to the foreground
// and won't appear in the Dock.
// ───────────────────────────────────────────────────────────────────────────────

import SwiftUI

@main
struct RenderKitApp: App {

    // Single shared app state — injected into all views
    @StateObject private var appState = AppState()

    // AppDelegate handles files opened via Finder / Dock drop
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // When launched from `swift run`, the process starts as a background
        // "accessory" app. This makes it a proper foreground GUI app with
        // a Dock icon and menu bar.
        NSApplication.shared.setActivationPolicy(.regular)

        // Bring the app to front
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        // ── Main Window ──
        WindowGroup {
            ContentView(appState: appState)
                .frame(minWidth: 700, minHeight: 500)
                .onAppear {
                    // Give the AppDelegate a reference to our state so it can
                    // forward file-open events from Finder / Dock drops
                    appDelegate.appState = appState
                }
                .onDisappear {
                    // Clean up when window closes
                    appState.devServer.stop()
                    appState.sandbox.stopPreview()
                    appState.fileWatcher.stop()
                }
        }
        .defaultSize(width: 1100, height: 750)
        .commands {
            // ── File Menu ──
            CommandGroup(after: .newItem) {
                Button("Open...") {
                    appState.showOpenFolderPanel()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button(appState.isCodePadActive ? "Close Code Pad" : "Code Pad") {
                    if appState.isCodePadActive {
                        appState.closeCodePad()
                    } else {
                        appState.openCodePad()
                    }
                }
                .keyboardShortcut("n", modifiers: .command)

                Divider()

                Button("Refresh Preview") {
                    appState.refreshPreview()
                }
                .keyboardShortcut("r", modifiers: .command)
            }

            // ── View Menu ──
            CommandGroup(after: .toolbar) {
                Toggle("Live Reload", isOn: $appState.isLiveReloadEnabled)
                    .keyboardShortcut("l", modifiers: .command)

                Toggle("Terminal", isOn: $appState.showTerminal)
                    .keyboardShortcut("t", modifiers: .command)

                Divider()

                Button("Copy File Path") {
                    appState.copyFilePath()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(appState.selectedFile == nil)

                Button("Open in Browser") {
                    appState.openInExternalBrowser()
                }
                .disabled(appState.selectedFile == nil && appState.devServer.serverURL == nil)

                Button("Reveal in Finder") {
                    appState.revealInFinder()
                }
                .disabled(appState.rootFolder == nil)
            }

            // ── Server Menu ──
            CommandMenu("Server") {
                if appState.devServer.isRunning {
                    Button("Stop Dev Server") {
                        appState.stopDevServer()
                    }
                } else if appState.projectInfo?.hasDevServer == true {
                    Button("Start Dev Server") {
                        appState.startDevServer()
                    }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                }

                if appState.sandbox.isReady {
                    Button("Stop Sandbox Preview") {
                        appState.stopSandboxPreview()
                    }
                }

                Divider()

                Button("Clean Sandbox Cache") {
                    appState.sandbox.cleanUp()
                }
            }
        }
    }
}

// MARK: - AppDelegate (handles Finder / Dock file-open events)

/// NSApplicationDelegate lets us respond to files being dropped on the Dock
/// icon or opened via Finder's "Open With" → RenderKit.
/// SwiftUI alone can't handle application(_:openFile:) events, so we need
/// this thin AppKit bridge.
class AppDelegate: NSObject, NSApplicationDelegate {

    /// Set by the SwiftUI view once AppState is ready
    var appState: AppState?

    /// Called when a file or folder is dropped onto the Dock icon,
    /// or when Finder sends an "Open With" event.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first, let appState = appState else { return }

        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

        if isDir.boolValue {
            appState.openFolder(url)
        } else {
            appState.openFile(url)
        }
    }
}
