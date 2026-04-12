// ───────────────────────────────────────────────────────────────────────────────
// ProjectDetector.swift — Detect project type from folder contents
// ───────────────────────────────────────────────────────────────────────────────
// Examines a folder for package.json, config files, and other markers to
// determine what kind of front-end project it is. This drives which UI
// controls we show (dev server button, sandbox option, etc.).
//
// Detection strategy:
//   1. Look for package.json → parse it for framework-specific dependencies
//   2. Look for config files (vite.config.*, next.config.*, angular.json, etc.)
//   3. Fall back to "static HTML" if no package.json found
// ───────────────────────────────────────────────────────────────────────────────

import Foundation

final class ProjectDetector {

    /// Analyze a directory and return project metadata.
    func detect(at rootURL: URL) -> ProjectInfo {
        let fm = FileManager.default

        // ── Check for package.json ──
        let packageJsonURL = rootURL.appendingPathComponent("package.json")
        guard fm.fileExists(atPath: packageJsonURL.path),
              let data = try? Data(contentsOf: packageJsonURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            // No package.json → static HTML project
            return ProjectInfo(
                kind: .staticHTML,
                rootURL: rootURL,
                devCommand: nil,
                devExecutable: nil,
                devArgs: nil
            )
        }

        // Merge all dependency maps for framework detection
        let deps = mergeDependencies(json)

        // Read scripts section
        let scripts = json["scripts"] as? [String: String] ?? [:]

        // ── Detect framework by dependencies and config files ──

        // Next.js
        if deps.contains("next") || fm.fileExists(atPath: rootURL.appendingPathComponent("next.config.js").path)
            || fm.fileExists(atPath: rootURL.appendingPathComponent("next.config.mjs").path)
            || fm.fileExists(atPath: rootURL.appendingPathComponent("next.config.ts").path) {
            let cmd = scripts["dev"] != nil ? "npm run dev" : "npx next dev"
            return ProjectInfo(
                kind: .nextjs, rootURL: rootURL,
                devCommand: cmd, devExecutable: "npm",
                devArgs: scripts["dev"] != nil ? ["run", "dev"] : ["exec", "next", "dev"]
            )
        }

        // Vite (check before CRA since Vite projects may also have react)
        if deps.contains("vite") || configExists(in: rootURL, prefix: "vite.config") {
            let cmd = scripts["dev"] != nil ? "npm run dev" : "npx vite"
            return ProjectInfo(
                kind: .vite, rootURL: rootURL,
                devCommand: cmd, devExecutable: "npm",
                devArgs: scripts["dev"] != nil ? ["run", "dev"] : ["exec", "vite"]
            )
        }

        // Create React App (react-scripts)
        if deps.contains("react-scripts") {
            return ProjectInfo(
                kind: .cra, rootURL: rootURL,
                devCommand: "npm start", devExecutable: "npm",
                devArgs: ["start"]
            )
        }

        // Remix
        if deps.contains("@remix-run/react") || deps.contains("@remix-run/dev") {
            let cmd = scripts["dev"] != nil ? "npm run dev" : "npx remix dev"
            return ProjectInfo(
                kind: .remix, rootURL: rootURL,
                devCommand: cmd, devExecutable: "npm",
                devArgs: scripts["dev"] != nil ? ["run", "dev"] : ["exec", "remix", "dev"]
            )
        }

        // Gatsby
        if deps.contains("gatsby") {
            return ProjectInfo(
                kind: .gatsby, rootURL: rootURL,
                devCommand: "npm run develop", devExecutable: "npm",
                devArgs: ["run", "develop"]
            )
        }

        // Angular
        if deps.contains("@angular/core") || fm.fileExists(atPath: rootURL.appendingPathComponent("angular.json").path) {
            return ProjectInfo(
                kind: .angular, rootURL: rootURL,
                devCommand: "npm start", devExecutable: "npm",
                devArgs: ["start"]
            )
        }

        // Vue
        if deps.contains("vue") || configExists(in: rootURL, prefix: "vue.config") {
            let cmd = scripts["dev"] != nil ? "npm run dev" : (scripts["serve"] != nil ? "npm run serve" : "npm start")
            let args = scripts["dev"] != nil ? ["run", "dev"] : (scripts["serve"] != nil ? ["run", "serve"] : ["start"])
            return ProjectInfo(
                kind: .vue, rootURL: rootURL,
                devCommand: cmd, devExecutable: "npm",
                devArgs: args
            )
        }

        // SvelteKit
        if deps.contains("@sveltejs/kit") || deps.contains("svelte") {
            let cmd = scripts["dev"] != nil ? "npm run dev" : "npx svelte-kit dev"
            return ProjectInfo(
                kind: .svelte, rootURL: rootURL,
                devCommand: cmd, devExecutable: "npm",
                devArgs: scripts["dev"] != nil ? ["run", "dev"] : ["exec", "svelte-kit", "dev"]
            )
        }

        // ── Generic Node project ──
        // Has package.json but no recognized framework. Look for a "dev" or "start" script.
        if let _ = scripts["dev"] {
            return ProjectInfo(
                kind: .generic, rootURL: rootURL,
                devCommand: "npm run dev", devExecutable: "npm",
                devArgs: ["run", "dev"]
            )
        }
        if let _ = scripts["start"] {
            return ProjectInfo(
                kind: .generic, rootURL: rootURL,
                devCommand: "npm start", devExecutable: "npm",
                devArgs: ["start"]
            )
        }

        // Node project with no runnable script
        return ProjectInfo(
            kind: .generic, rootURL: rootURL,
            devCommand: nil, devExecutable: nil, devArgs: nil
        )
    }

    // MARK: - Helpers

    /// Merge dependencies, devDependencies, and peerDependencies into one set of package names.
    private func mergeDependencies(_ json: [String: Any]) -> Set<String> {
        var all = Set<String>()
        for key in ["dependencies", "devDependencies", "peerDependencies"] {
            if let deps = json[key] as? [String: Any] {
                all.formUnion(deps.keys)
            }
        }
        return all
    }

    /// Check if a config file exists with any common extension.
    private func configExists(in dir: URL, prefix: String) -> Bool {
        let extensions = ["js", "mjs", "ts", "mts", "cjs"]
        let fm = FileManager.default
        return extensions.contains { ext in
            fm.fileExists(atPath: dir.appendingPathComponent("\(prefix).\(ext)").path)
        }
    }
}
