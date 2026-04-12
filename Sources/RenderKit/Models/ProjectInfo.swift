// ───────────────────────────────────────────────────────────────────────────────
// ProjectInfo.swift — Detected project metadata
// ───────────────────────────────────────────────────────────────────────────────
// When a folder is opened, we check for package.json and other config files
// to determine what kind of project it is (React, Vite, Next.js, plain HTML…).
// This model stores the result so the UI can show relevant controls.
// ───────────────────────────────────────────────────────────────────────────────

import Foundation

/// The kind of front-end project detected in the opened folder.
enum ProjectKind: String, CustomStringConvertible {
    case vite       = "Vite"
    case cra        = "Create React App"
    case nextjs     = "Next.js"
    case remix      = "Remix"
    case gatsby     = "Gatsby"
    case angular    = "Angular"
    case vue        = "Vue"
    case svelte     = "SvelteKit"
    case generic    = "Node Project"       // Has package.json but no known framework
    case staticHTML = "Static HTML"        // No package.json, just files

    var description: String { rawValue }
}

struct ProjectInfo {
    /// What kind of project this is
    let kind: ProjectKind

    /// Root directory of the project
    let rootURL: URL

    /// The shell command to start the dev server (e.g. "npm run dev")
    let devCommand: String?

    /// Arguments for the dev command split into (executable, args)
    let devExecutable: String?
    let devArgs: [String]?

    /// Human-readable description for the UI
    var summary: String {
        switch kind {
        case .staticHTML:
            return "Static HTML project — files will preview directly."
        default:
            if let cmd = devCommand {
                return "\(kind) project — use \"\(cmd)\" to start the dev server."
            }
            return "\(kind) project detected."
        }
    }

    /// Whether this project supports a dev server
    var hasDevServer: Bool {
        devCommand != nil
    }
}
