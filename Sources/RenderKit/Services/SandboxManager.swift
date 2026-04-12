// ───────────────────────────────────────────────────────────────────────────────
// SandboxManager.swift — Standalone JSX/TSX component preview sandbox
// ───────────────────────────────────────────────────────────────────────────────
// When a user selects a .jsx/.tsx file that's NOT part of a full React project,
// this manager creates a minimal Vite+React sandbox in a temp directory,
// configures it to import and render the user's component, and runs the Vite
// dev server. The WKWebView then points to the sandbox's dev server URL.
//
// How it works:
//   1. Create a temp directory (~/.renderkit-sandbox/)
//   2. Write a minimal package.json, vite.config.js, index.html, and main.jsx
//   3. main.jsx imports the user's component using a Vite alias
//   4. Run `npm install` (once) then `npx vite`
//   5. Vite's HMR watches the user's file for changes → auto-refresh
//
// Prerequisites: Node.js and npm must be installed.
// ───────────────────────────────────────────────────────────────────────────────

import Foundation

final class SandboxManager: ObservableObject {

    // MARK: - State

    @Published var isReady = false
    @Published var isInstalling = false
    @Published var serverURL: URL?
    @Published var logs: [String] = []
    @Published var error: String?

    // MARK: - Private

    private var sandboxDir: URL?
    private var serverProcess: Process?
    private var installedOnce = false

    /// Base directory for all sandbox operations
    private var baseSandboxDir: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".renderkit-sandbox")
    }

    // MARK: - Public API

    /// Set up the sandbox and start a preview for the given component file.
    /// - Parameter componentURL: Absolute URL to a .jsx or .tsx file
    func startPreview(for componentURL: URL) {
        Task { @MainActor in
            do {
                error = nil
                isReady = false
                logs = []

                // 1. Create sandbox directory
                let dir = try createSandboxDirectory()
                self.sandboxDir = dir

                // 2. Write scaffold files
                try writeScaffold(to: dir, componentURL: componentURL)

                // 3. Install dependencies (only on first run or if node_modules missing)
                let nodeModules = dir.appendingPathComponent("node_modules")
                if !FileManager.default.fileExists(atPath: nodeModules.path) {
                    isInstalling = true
                    appendLog("[Sandbox] Installing dependencies...\n")
                    try await runNpmInstall(in: dir)
                    isInstalling = false
                    appendLog("[Sandbox] Dependencies installed.\n")
                }

                // 4. Start Vite dev server
                appendLog("[Sandbox] Starting Vite dev server...\n")
                startViteServer(in: dir)

            } catch {
                self.error = error.localizedDescription
                appendLog("[Sandbox] Error: \(error.localizedDescription)\n")
            }
        }
    }

    /// Stop the sandbox preview server and clean up processes.
    func stopPreview() {
        if let proc = serverProcess, proc.isRunning {
            proc.terminate()
            let pid = proc.processIdentifier
            kill(-pid, SIGTERM)
        }
        serverProcess = nil
        serverURL = nil
        isReady = false
        appendLog("[Sandbox] Server stopped.\n")
    }

    /// Remove the entire sandbox directory from disk.
    func cleanUp() {
        stopPreview()
        if let dir = sandboxDir {
            try? FileManager.default.removeItem(at: dir)
            appendLog("[Sandbox] Cleaned up sandbox directory.\n")
        }
        sandboxDir = nil
        installedOnce = false
    }

    // MARK: - Scaffold Generation

    /// Create the sandbox directory if it doesn't exist.
    private func createSandboxDirectory() throws -> URL {
        let dir = baseSandboxDir
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Write the minimal Vite+React scaffold files.
    private func writeScaffold(to dir: URL, componentURL: URL) throws {
        let componentDir = componentURL.deletingLastPathComponent().path
        let componentName = componentURL.deletingPathExtension().lastPathComponent
        let componentExt = componentURL.pathExtension

        // ── package.json ──
        let packageJson = """
        {
          "name": "renderkit-sandbox",
          "private": true,
          "type": "module",
          "scripts": {
            "dev": "vite --port 5199 --strictPort"
          },
          "dependencies": {
            "react": "^18.2.0",
            "react-dom": "^18.2.0"
          },
          "devDependencies": {
            "@vitejs/plugin-react": "^4.2.0",
            "vite": "^5.0.0"
          }
        }
        """
        try packageJson.write(to: dir.appendingPathComponent("package.json"),
                              atomically: true, encoding: .utf8)

        // ── vite.config.js ──
        // Uses a resolve alias so we can import the user's component without copying it.
        let viteConfig = """
        import { defineConfig } from 'vite';
        import react from '@vitejs/plugin-react';

        export default defineConfig({
          plugins: [react()],
          resolve: {
            alias: {
              '@component': '\(componentDir)'
            }
          },
          server: {
            port: 5199,
            strictPort: true,
            // Watch the user's component directory for changes
            watch: {
              ignored: ['!**/node_modules/**'],
            }
          }
        });
        """
        try viteConfig.write(to: dir.appendingPathComponent("vite.config.js"),
                             atomically: true, encoding: .utf8)

        // ── index.html ──
        let indexHtml = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1.0" />
          <title>RenderKit Component Preview</title>
          <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            body {
              font-family: -apple-system, BlinkMacSystemFont, sans-serif;
              display: flex;
              justify-content: center;
              padding: 24px;
              min-height: 100vh;
            }
            #root { width: 100%; max-width: 960px; }
            .error-boundary {
              color: #dc3545;
              padding: 16px;
              border: 1px solid #dc3545;
              border-radius: 8px;
              margin: 16px 0;
              font-family: monospace;
              white-space: pre-wrap;
            }
          </style>
        </head>
        <body>
          <div id="root"></div>
          <script type="module" src="/main.jsx"></script>
        </body>
        </html>
        """
        try indexHtml.write(to: dir.appendingPathComponent("index.html"),
                           atomically: true, encoding: .utf8)

        // ── main.jsx ──
        // Imports the user's component via the @component alias and renders it.
        // Wraps in an error boundary so crashes show a nice message instead of a blank page.
        let mainJsx = """
        import React from 'react';
        import { createRoot } from 'react-dom/client';

        // Import the user's component using the Vite alias
        import PreviewComponent from '@component/\(componentName).\(componentExt)';

        // Simple error boundary
        class ErrorBoundary extends React.Component {
          constructor(props) {
            super(props);
            this.state = { error: null };
          }
          static getDerivedStateFromError(error) {
            return { error: error.message };
          }
          render() {
            if (this.state.error) {
              return React.createElement('div', { className: 'error-boundary' },
                'Component Error:\\n\\n' + this.state.error
              );
            }
            return this.props.children;
          }
        }

        const root = createRoot(document.getElementById('root'));
        root.render(
          React.createElement(ErrorBoundary, null,
            React.createElement(PreviewComponent)
          )
        );
        """
        try mainJsx.write(to: dir.appendingPathComponent("main.jsx"),
                          atomically: true, encoding: .utf8)
    }

    // MARK: - Process Management

    /// Run `npm install` synchronously.
    private func runNpmInstall(in directory: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let proc = Process()
            proc.currentDirectoryURL = directory
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            proc.arguments = ["npm", "install"]

            var env = ProcessInfo.processInfo.environment
            let extraPaths = ["/usr/local/bin", "/opt/homebrew/bin"]
            env["PATH"] = (extraPaths + [env["PATH"] ?? ""]).joined(separator: ":")
            proc.environment = env

            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe

            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                DispatchQueue.main.async { self?.appendLog(text) }
            }

            proc.terminationHandler = { process in
                pipe.fileHandleForReading.readabilityHandler = nil
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "SandboxManager",
                        code: Int(process.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: "npm install failed (exit code \(process.terminationStatus))"]
                    ))
                }
            }

            do {
                try proc.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Start the Vite dev server as a background process.
    private func startViteServer(in directory: URL) {
        let proc = Process()
        proc.currentDirectoryURL = directory
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["npx", "vite", "--port", "5199", "--strictPort"]

        var env = ProcessInfo.processInfo.environment
        let extraPaths = ["/usr/local/bin", "/opt/homebrew/bin"]
        env["PATH"] = (extraPaths + [env["PATH"] ?? ""]).joined(separator: ":")
        proc.environment = env

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.appendLog(text)
                // Detect when Vite is ready
                if text.contains("localhost:5199") || text.contains("127.0.0.1:5199") {
                    self?.serverURL = URL(string: "http://localhost:5199")
                    self?.isReady = true
                }
            }
        }

        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.isReady = false
            }
        }

        do {
            try proc.run()
            self.serverProcess = proc
        } catch {
            appendLog("[Sandbox] Failed to start Vite: \(error.localizedDescription)\n")
            self.error = error.localizedDescription
        }
    }

    private func appendLog(_ text: String) {
        logs.append(text)
        if logs.count > 2000 {
            logs.removeFirst(logs.count - 2000)
        }
    }

    deinit {
        stopPreview()
    }
}
