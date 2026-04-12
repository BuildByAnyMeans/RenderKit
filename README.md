# RenderKit

A native macOS desktop app for previewing front-end files locally — HTML, CSS, JS, Markdown, JSON, JSX/TSX, and images — without leaving your Mac.

Built with **Swift + SwiftUI + WKWebView**. No Electron, no browser tabs.

## Features

- **Native Mac app** — opens like any other application, runs entirely locally
- **File tree sidebar** — browse project folders with color-coded file icons
- **Live preview** — HTML files render with full CSS/JS/asset support
- **Live reload** — saves auto-refresh the preview via FSEvents file watching
- **Markdown rendering** — `.md` files display as styled HTML (GitHub-like)
- **Syntax highlighting** — CSS, JS, TS, and other source files with code view
- **JSON pretty-print** — formatted and highlighted JSON display
- **Image preview** — PNG, JPG, GIF, WebP, SVG with transparency checkerboard
- **React/JSX support** — two modes:
  - **Dev Server mode**: detects React/Vite/Next.js projects and runs their dev server
  - **Sandbox mode**: previews standalone `.jsx/.tsx` components in a minimal Vite sandbox
- **Terminal panel** — see dev server output directly in the app
- **Project detection** — auto-detects Vite, CRA, Next.js, Remix, Angular, Vue, SvelteKit
- **Keyboard shortcuts** — ⌘O open, ⌘R refresh, ⌘L live reload, ⌘T terminal
- **Persisted state** — remembers your last folder, live reload preference

## Requirements

- **macOS 13 (Ventura)** or later
- **Xcode 15+** or Swift 5.9+ toolchain (for building)
- **Node.js + npm** _(optional)_ — only needed for JSX/TSX preview and dev server features

## Quick Start

### Option 1: Build & Run with Swift (simplest)

```bash
# Clone or navigate to the project
cd RenderKit

# Build and run (one command)
./setup.sh

# Or manually:
swift build -c release && swift run -c release
```

The app window will appear. Click **Open Folder** (or ⌘O) to select a project.

### Option 2: Open in Xcode

```bash
# Option A: Open the Swift package directly in Xcode
open Package.swift

# Option B: Generate an Xcode project (requires XcodeGen)
brew install xcodegen
xcodegen generate
open RenderKit.xcodeproj
```

In Xcode, select the **RenderKit** scheme and click **Run** (⌘R).

### Option 3: Build a standalone .app

```bash
swift build -c release
# The binary is at .build/release/RenderKit
# You can run it directly:
.build/release/RenderKit
```

## Usage Guide

### Basic File Preview

1. Click **Open Folder** or press **⌘O**
2. Select any folder containing front-end files
3. Click a file in the sidebar to preview it
4. Toggle **Live Reload** (⌘L) to auto-refresh when you save changes

### HTML Files

HTML files render in a full WKWebView with:
- Local CSS and JavaScript loaded correctly
- Images and other assets resolved relative to the project root
- A custom URL scheme (`rk://`) that handles all resource loading

### React / JSX / TSX

**If the folder is a React project** (has `package.json` with React dependencies):
1. Click the **Run Dev Server** button in the toolbar (or the JSX preview panel)
2. The app runs `npm run dev` (or the detected dev command)
3. The preview automatically points to the dev server URL
4. Open the **Terminal** panel (⌘T) to see server output

**If the file is a standalone component** (not part of a project):
1. Click the `.jsx/.tsx` file in the sidebar
2. Click **Preview in Sandbox**
3. The app creates a minimal Vite+React sandbox and renders your component
4. Changes to the file are picked up by Vite's HMR

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘O | Open Folder |
| ⌘R | Refresh Preview |
| ⌘L | Toggle Live Reload |
| ⌘T | Toggle Terminal |
| ⇧⌘C | Copy File Path |
| ⇧⌘D | Start Dev Server |

## Architecture

```
Sources/RenderKit/
├── RenderKitApp.swift              # @main entry, window config, menu commands
├── AppState.swift                  # Central ObservableObject (single source of truth)
├── ContentView.swift               # NavigationSplitView: sidebar + detail
├── Models/
│   ├── FileNode.swift              # Recursive file tree model
│   └── ProjectInfo.swift           # Detected project metadata
├── Views/
│   ├── FileTreeView.swift          # Sidebar file browser with DisclosureGroups
│   ├── PreviewPanelView.swift      # Routes file type → correct preview
│   ├── WebPreviewView.swift        # NSViewRepresentable wrapping WKWebView
│   ├── GettingStartedView.swift    # Welcome screen with instructions
│   └── TerminalOutputView.swift    # Dev server log viewer
├── Services/
│   ├── FileWatcherService.swift    # FSEvents directory watcher
│   ├── LocalFileSchemeHandler.swift# Custom WKURLSchemeHandler for local files
│   ├── MarkdownRenderer.swift      # Markdown → HTML converter
│   ├── ProjectDetector.swift       # Framework/project type detection
│   ├── DevServerManager.swift      # npm/dev server process management
│   └── SandboxManager.swift        # Standalone JSX/TSX preview sandbox
└── Helpers/
    ├── FileTypeHelper.swift        # MIME types, preview mode classification
    └── PreferencesManager.swift    # UserDefaults persistence
```

### Key Design Decisions

- **WKURLSchemeHandler** (`rk://`): Instead of running a local HTTP server, we register a custom URL scheme with WebKit. The handler reads files from disk and serves them to the web view. This handles relative paths, avoids CORS issues, and requires no external dependencies.

- **FSEventStream**: macOS kernel-level file system events API for watching directory trees. More efficient than polling and handles recursive subdirectories automatically.

- **Process group termination**: When stopping a dev server, we send `SIGTERM` to the entire process group (negative PID), not just the npm parent process. This ensures child processes (vite, webpack, etc.) are also killed.

- **ObservableObject + @Published**: Classic SwiftUI state management pattern. AppState is the single source of truth, injected via @StateObject at the app level.

## Troubleshooting

### "Node.js not found"
Install Node.js from [nodejs.org](https://nodejs.org) or via Homebrew:
```bash
brew install node
```

### Dev server won't start
1. Open Terminal and try running the command manually (e.g., `npm run dev`)
2. Make sure `node` and `npm` are in your PATH
3. If using nvm/volta/fnm, make sure the correct version is active
4. Check the Terminal panel (⌘T) in RenderKit for error output

### Port already in use
```bash
# Find what's using port 3000 (or whatever port):
lsof -i :3000
# Kill it:
kill -9 <PID>
```

### HTML preview is blank
- Ensure all referenced CSS/JS files exist at the expected relative paths
- Check for JavaScript errors (right-click in preview → Inspect Element → Console)
- The app serves files from the project root — paths like `/assets/style.css` resolve relative to the opened folder

### Sandbox preview fails
- Requires Node.js and npm (check with `node --version` and `npm --version`)
- First run downloads React and Vite (~30 seconds depending on internet speed)
- Sandbox uses port 5199 — make sure it's free
- Clear the sandbox cache: Server menu → Clean Sandbox Cache
- Sandbox directory: `~/.renderkit-sandbox/`

### App window doesn't appear (swift run)
This can happen if macOS doesn't recognize the process as a GUI app:
```bash
# Try building and running the release binary directly:
swift build -c release
.build/release/RenderKit
```

### Build fails
```bash
# Clean and rebuild:
swift package clean
swift build -c release
```

Make sure you have Xcode 15+ or the Swift 5.9+ toolchain installed.

## Limitations & Future Improvements

### Current Limitations
- **No SCSS/LESS/Sass compilation** — only plain CSS is supported natively
- **No TypeScript compilation for preview** — TS files show syntax-highlighted source; use the dev server for actual TS execution
- **Markdown parser is basic** — handles common Markdown but may miss edge cases (tables with alignment, footnotes, etc.). A full CommonMark parser would be better.
- **No embedded syntax highlighting library** — source code views use a basic monospaced font without token-level coloring. Embedding Prism.js or highlight.js would improve this.
- **Sandbox requires internet on first use** — npm install needs to download React and Vite
- **No multi-window support** — only one project can be open at a time
- **No built-in terminal** — the terminal panel is output-only (no interactive input)

### Planned Improvements
- [ ] Embed Prism.js or highlight.js for proper syntax coloring
- [ ] Add a full CommonMark parser (or embed cmark)
- [ ] Multi-tab / multi-window support for comparing files
- [ ] Drag-and-drop folder opening
- [ ] Inline CSS/JS error overlay in the preview
- [ ] Search across files (⌘⇧F)
- [ ] Responsive preview mode (mobile/tablet size presets)
- [ ] Export preview as PDF or screenshot
- [ ] App icon and proper .app bundle for distribution
- [ ] App Sandbox + security-scoped bookmarks for Mac App Store
- [ ] Auto-detect and use yarn/pnpm/bun instead of npm
- [ ] Split-pane source + preview for markdown editing

## License

MIT — do whatever you want with it.
