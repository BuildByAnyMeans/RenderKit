// ───────────────────────────────────────────────────────────────────────────────
// DevServerManager.swift — Manages external dev server processes
// ───────────────────────────────────────────────────────────────────────────────
// Starts and stops dev server processes (npm run dev, npx vite, etc.) as child
// processes. Captures stdout/stderr for the terminal view and auto-detects
// the server URL from the output (e.g. "Local: http://localhost:5173").
//
// Key design decisions:
//   - Uses /usr/bin/env to resolve npm/node in the user's PATH
//   - Inherits the user's shell environment (PATH, NVM, etc.)
//   - Reads output via Pipe with readabilityHandler for real-time streaming
//   - Terminates the process tree (not just the parent) on stop
// ───────────────────────────────────────────────────────────────────────────────

import Foundation

final class DevServerManager: ObservableObject {

    // MARK: - Published State

    @Published var isRunning = false
    @Published var logs: [String] = []
    @Published var serverURL: URL?

    // MARK: - Private

    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?

    // MARK: - Start Server

    /// Start a dev server in the given directory.
    ///
    /// - Parameters:
    ///   - directory: The project root (working directory for the process)
    ///   - executable: The command to run (e.g. "npm")
    ///   - args: Arguments (e.g. ["run", "dev"])
    func start(in directory: URL, executable: String, args: [String]) {
        stop() // Kill any existing server first
        logs = []
        serverURL = nil

        let proc = Process()
        proc.currentDirectoryURL = directory

        // Use /usr/bin/env to find the executable in the user's PATH.
        // This is important because npm/node might be installed via nvm,
        // Homebrew, or other version managers.
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [executable] + args

        // Inherit the user's environment so PATH includes nvm, brew, etc.
        // We also add common paths that might be missing.
        var env = ProcessInfo.processInfo.environment
        let extraPaths = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "\(NSHomeDirectory())/.nvm/versions/node/*/bin",  // nvm
            "\(NSHomeDirectory())/.volta/bin",                 // volta
            "\(NSHomeDirectory())/.bun/bin",                   // bun
        ]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")
        proc.environment = env

        // Capture stdout and stderr
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        // Stream stdout in real time
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.appendLog(text)
                self?.detectServerURL(in: text)
            }
        }

        // Stream stderr in real time (many dev servers log to stderr)
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.appendLog(text)
                self?.detectServerURL(in: text)
            }
        }

        // Handle process termination
        proc.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.appendLog("\n[RenderKit] Server exited with code \(process.terminationStatus)")
            }
        }

        // Launch the process
        do {
            try proc.run()
            self.process = proc
            self.outputPipe = outPipe
            self.errorPipe = errPipe
            self.isRunning = true
            appendLog("[RenderKit] Starting: \(executable) \(args.joined(separator: " "))\n")
            appendLog("[RenderKit] Working directory: \(directory.path)\n\n")
        } catch {
            appendLog("[RenderKit] Failed to start server: \(error.localizedDescription)\n")
            appendLog("[RenderKit] Make sure Node.js and npm are installed.\n")
            appendLog("[RenderKit] Tip: Run 'which npm' in Terminal to verify.\n")
        }
    }

    // MARK: - Stop Server

    /// Stop the running dev server and clean up.
    func stop() {
        guard let proc = process, proc.isRunning else {
            process = nil
            isRunning = false
            return
        }

        // Remove pipe handlers first to avoid callbacks after termination
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil

        // Send SIGTERM (graceful shutdown) then SIGKILL after a delay
        proc.terminate()

        // Also kill the process group to terminate child processes (like the
        // actual Vite/webpack process spawned by npm)
        let pid = proc.processIdentifier
        kill(-pid, SIGTERM) // Negative PID = entire process group

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            if proc.isRunning {
                proc.interrupt() // SIGINT as fallback
                kill(-pid, SIGKILL) // Force kill the group
            }
            self?.process = nil
        }

        isRunning = false
        serverURL = nil
        appendLog("\n[RenderKit] Server stopped.\n")
    }

    // MARK: - Helpers

    /// Append text to the log buffer (keeps last 5000 lines to prevent memory issues).
    private func appendLog(_ text: String) {
        logs.append(text)
        if logs.count > 5000 {
            logs.removeFirst(logs.count - 5000)
        }
    }

    /// Try to extract a localhost URL from server output.
    /// Dev servers typically print something like:
    ///   "Local:   http://localhost:5173/"
    ///   "ready started server on 0.0.0.0:3000, url: http://localhost:3000"
    private func detectServerURL(in output: String) {
        guard serverURL == nil else { return } // Only detect once

        // Match http://localhost:PORT or http://127.0.0.1:PORT
        let pattern = #"https?://(?:localhost|127\.0\.0\.1):\d+"#
        guard let range = output.range(of: pattern, options: .regularExpression) else { return }

        let urlString = String(output[range])
        if let url = URL(string: urlString) {
            serverURL = url
            appendLog("\n[RenderKit] Detected server URL: \(urlString)\n")
        }
    }

    /// Check if Node.js is available on this system.
    static func isNodeInstalled() -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["node", "--version"]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Check if npm is available on this system.
    static func isNpmInstalled() -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["npm", "--version"]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }

    deinit {
        stop()
    }
}
