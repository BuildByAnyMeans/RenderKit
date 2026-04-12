// ───────────────────────────────────────────────────────────────────────────────
// AppState.swift — Central observable state for the entire app
// ───────────────────────────────────────────────────────────────────────────────
// This is the single source of truth. Every view observes this object.
// It orchestrates the services (file watcher, dev server, project detector)
// and provides the data that drives the UI.
//
// Architecture: AppState owns the service instances and coordinates between
// them. Views bind to @Published properties. Actions flow through methods
// on this class.
// ───────────────────────────────────────────────────────────────────────────────

import SwiftUI
import Combine

final class AppState: ObservableObject {

    // MARK: - Published UI State

    /// The root folder of the currently opened project
    @Published var rootFolder: URL?

    /// The file tree built from the root folder
    @Published var fileTree: [FileNode] = []

    /// The currently selected file in the sidebar
    @Published var selectedFile: FileNode?

    /// Whether live-reload is active
    @Published var isLiveReloadEnabled: Bool = true

    /// Detected project metadata (framework, dev command, etc.)
    @Published var projectInfo: ProjectInfo?

    /// Whether the terminal/log panel is visible
    @Published var showTerminal: Bool = false

    /// Status bar message (bottom of the window)
    @Published var statusMessage: String = "No folder open"

    /// Toggle to force WKWebView to reload
    @Published var reloadTrigger: UUID = UUID()

    // MARK: - Code Pad State

    /// Whether the Code Pad is active (replaces file tree sidebar with editor)
    @Published var isCodePadActive: Bool = false

    /// The raw code text the user has pasted/typed into the Code Pad
    @Published var codePadText: String = ""

    /// The language selected in the Code Pad picker
    @Published var codePadLanguage: CodePadLanguage = .html

    // MARK: - Services (owned)

    let fileWatcher = FileWatcherService()
    let devServer = DevServerManager()
    let sandbox = SandboxManager()
    let projectDetector = ProjectDetector()
    let preferences = PreferencesManager()

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init() {
        // Restore preferences
        isLiveReloadEnabled = preferences.isLiveReloadEnabled
        showTerminal = preferences.showTerminal

        // Persist preference changes
        $isLiveReloadEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                self?.preferences.isLiveReloadEnabled = enabled
                if enabled, let root = self?.rootFolder {
                    self?.fileWatcher.watch(directory: root)
                } else {
                    self?.fileWatcher.stop()
                }
            }
            .store(in: &cancellables)

        $showTerminal
            .dropFirst()
            .sink { [weak self] show in
                self?.preferences.showTerminal = show
            }
            .store(in: &cancellables)

        // Wire up file watcher → reload trigger
        fileWatcher.onChange = { [weak self] in
            guard let self = self, self.isLiveReloadEnabled else { return }
            // Refresh the file tree in case files were added/removed
            if let root = self.rootFolder {
                self.fileTree = FileNode.buildTree(at: root)
            }
            // Trigger a WKWebView reload
            self.reloadTrigger = UUID()
            self.statusMessage = "Reloaded at \(Self.timeString)"
        }

        // Try to restore last opened folder
        if let lastFolder = preferences.lastOpenedFolder {
            openFolder(lastFolder)
        }
    }

    // MARK: - Actions

    /// Open a folder and set up the project.
    func openFolder(_ url: URL) {
        rootFolder = url
        preferences.lastOpenedFolder = url

        // Build file tree
        fileTree = FileNode.buildTree(at: url)

        // Detect project type
        projectInfo = projectDetector.detect(at: url)
        statusMessage = projectInfo?.summary ?? "Folder opened"

        // Start file watching if live-reload is enabled
        if isLiveReloadEnabled {
            fileWatcher.watch(directory: url)
        }

        // Reset selection
        selectedFile = nil

        // Stop any running servers from previous project
        devServer.stop()
        sandbox.stopPreview()

        print("[AppState] Opened folder: \(url.path)")
        print("[AppState] Project: \(projectInfo?.kind.description ?? "unknown")")
    }

    /// Show the native open panel — accepts BOTH files and folders.
    func showOpenFolderPanel() {
        let panel = NSOpenPanel()
        panel.title = "Open File or Folder"
        panel.message = "Select a project folder or an individual file"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        // Allow all file types we support previewing
        panel.allowedContentTypes = [] // Empty = all types allowed

        if panel.runModal() == .OK, let url = panel.url {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

            if isDir.boolValue {
                openFolder(url)
            } else {
                openFile(url)
            }
        }
    }

    /// Open a single file for preview.
    /// Sets the file's parent directory as the root folder so relative
    /// paths (CSS, images, etc.) still resolve correctly in HTML files.
    func openFile(_ url: URL) {
        let parentDir = url.deletingLastPathComponent()

        // Set parent as root so sidebar shows sibling files
        rootFolder = parentDir
        preferences.lastOpenedFolder = parentDir

        // Build file tree from parent directory
        fileTree = FileNode.buildTree(at: parentDir)

        // Detect project type from parent
        projectInfo = projectDetector.detect(at: parentDir)

        // Start file watching if enabled
        if isLiveReloadEnabled {
            fileWatcher.watch(directory: parentDir)
        }

        // Stop any running servers
        devServer.stop()
        sandbox.stopPreview()

        // Find and select the opened file in the tree
        selectedFile = findNode(for: url, in: fileTree)
        statusMessage = "Opened: \(url.lastPathComponent)"

        print("[AppState] Opened file: \(url.path)")
    }

    /// Recursively search the file tree for a node matching the given URL.
    private func findNode(for url: URL, in nodes: [FileNode]) -> FileNode? {
        for node in nodes {
            if node.url.standardizedFileURL == url.standardizedFileURL {
                return node
            }
            if let children = node.children,
               let found = findNode(for: url, in: children) {
                return found
            }
        }
        return nil
    }

    /// Start the dev server for the current project.
    func startDevServer() {
        guard let info = projectInfo,
              let executable = info.devExecutable,
              let args = info.devArgs else {
            statusMessage = "No dev server command available for this project."
            return
        }

        showTerminal = true
        devServer.start(in: info.rootURL, executable: executable, args: args)
        statusMessage = "Starting \(info.kind) dev server..."
    }

    /// Stop the dev server.
    func stopDevServer() {
        devServer.stop()
        statusMessage = "Dev server stopped."
    }

    /// Start the sandbox preview for a standalone JSX/TSX component.
    func startSandboxPreview(for file: FileNode) {
        guard file.fileExtension == "jsx" || file.fileExtension == "tsx" else { return }
        showTerminal = true
        sandbox.startPreview(for: file.url)
        statusMessage = "Starting sandbox preview for \(file.name)..."
    }

    /// Stop the sandbox preview.
    func stopSandboxPreview() {
        sandbox.stopPreview()
        statusMessage = "Sandbox preview stopped."
    }

    /// Refresh the preview (manual reload).
    func refreshPreview() {
        reloadTrigger = UUID()
        statusMessage = "Refreshed at \(Self.timeString)"
    }

    /// Copy the selected file's path to the clipboard.
    func copyFilePath() {
        guard let file = selectedFile else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(file.url.path, forType: .string)
        statusMessage = "Copied: \(file.url.path)"
    }

    /// Open the selected file in the default external browser.
    func openInExternalBrowser() {
        if let url = devServer.serverURL {
            // If dev server is running, open its URL
            NSWorkspace.shared.open(url)
        } else if let file = selectedFile, file.fileExtension == "html" {
            // Open HTML file directly
            NSWorkspace.shared.open(file.url)
        }
    }

    /// Open the root folder in Finder.
    func revealInFinder() {
        if let file = selectedFile {
            NSWorkspace.shared.activateFileViewerSelecting([file.url])
        } else if let root = rootFolder {
            NSWorkspace.shared.open(root)
        }
    }

    // MARK: - Code Pad Actions

    /// Activate the Code Pad (switches sidebar from file tree to editor).
    func openCodePad() {
        isCodePadActive = true
        selectedFile = nil  // Deselect any file so preview shows Code Pad output
        statusMessage = "Code Pad — paste code and preview instantly"
    }

    /// Deactivate the Code Pad and return to the file tree.
    func closeCodePad() {
        isCodePadActive = false
        statusMessage = rootFolder != nil ? "Back to file browser" : "No folder open"
    }

    /// Render the current Code Pad contents (bumps reloadTrigger).
    func renderCodePad() {
        reloadTrigger = UUID()
        statusMessage = "Rendered \(codePadLanguage.displayName) at \(Self.timeString)"
    }

    /// Save the Code Pad contents to a file using NSSavePanel.
    func saveCodePadToFile() {
        let panel = NSSavePanel()
        panel.title = "Save Code"
        panel.nameFieldStringValue = "untitled.\(codePadLanguage.fileExtension)"
        panel.allowedContentTypes = [.plainText]

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try codePadText.write(to: url, atomically: true, encoding: .utf8)
                statusMessage = "Saved to \(url.lastPathComponent)"
            } catch {
                statusMessage = "Save failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Helpers

    /// Current time as a short string for status messages.
    private static var timeString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm:ss a"
        return fmt.string(from: Date())
    }
}

// MARK: - Code Pad Language

/// Languages the Code Pad can render/preview.
enum CodePadLanguage: String, CaseIterable, Identifiable {
    case html = "html"
    case jsx  = "jsx"
    case tsx  = "tsx"
    case css  = "css"
    case js   = "js"
    case markdown = "md"
    case json = "json"
    case svg  = "svg"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .html:     return "HTML"
        case .jsx:      return "JSX (React)"
        case .tsx:      return "TSX (React+TS)"
        case .css:      return "CSS"
        case .js:       return "JavaScript"
        case .markdown: return "Markdown"
        case .json:     return "JSON"
        case .svg:      return "SVG"
        }
    }

    var fileExtension: String { rawValue }

    /// Placeholder text shown in the editor when empty.
    var placeholder: String {
        switch self {
        case .html:
            return "Paste HTML here...\n\nExample:\n<h1>Hello World</h1>\n<p>This will render in the preview.</p>"
        case .jsx, .tsx:
            return "Paste a React component here...\n\nExample:\nfunction App() {\n  return <h1>Hello from React!</h1>;\n}"
        case .css:
            return "Paste CSS here...\n\nIt will be applied to a sample HTML page."
        case .js:
            return "Paste JavaScript here...\n\nConsole output will appear in the preview."
        case .markdown:
            return "Paste Markdown here...\n\n# Heading\n\nSome **bold** and *italic* text."
        case .json:
            return "Paste JSON here...\n\n{\n  \"hello\": \"world\"\n}"
        case .svg:
            return "Paste SVG markup here...\n\n<svg width=\"200\" height=\"200\">\n  <circle cx=\"100\" cy=\"100\" r=\"80\" fill=\"blue\" />\n</svg>"
        }
    }
}
