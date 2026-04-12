// ───────────────────────────────────────────────────────────────────────────────
// FileNode.swift — Recursive file-tree data model
// ───────────────────────────────────────────────────────────────────────────────
// Each FileNode represents a file or directory in the user's project.
// Directories lazily load their children on first expansion.
// The model conforms to Identifiable (for SwiftUI Lists) and Hashable
// (so it can be used as a NavigationSplitView selection value).
// ───────────────────────────────────────────────────────────────────────────────

import Foundation

final class FileNode: Identifiable, Hashable, ObservableObject {

    // MARK: - Properties

    let id = UUID()

    /// Display name (e.g. "index.html")
    let name: String

    /// Absolute file URL on disk
    let url: URL

    /// True for directories, false for regular files
    let isDirectory: Bool

    /// File extension lowercased (e.g. "html", "jsx"). Empty for directories.
    let fileExtension: String

    /// Child nodes — nil means "not yet loaded", empty means "loaded but empty"
    @Published var children: [FileNode]?

    /// Whether this directory is expanded in the sidebar
    @Published var isExpanded: Bool = false

    // MARK: - Init

    init(url: URL, isDirectory: Bool) {
        self.url = url
        self.name = url.lastPathComponent
        self.isDirectory = isDirectory
        self.fileExtension = isDirectory ? "" : url.pathExtension.lowercased()
    }

    // MARK: - Hashable (identity-based)

    static func == (lhs: FileNode, rhs: FileNode) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: - Tree Construction

    /// Recursively build a file tree starting at `rootURL`.
    /// Skips hidden files (dot-prefixed) and common noise directories.
    static func buildTree(at rootURL: URL) -> [FileNode] {
        let fm = FileManager.default
        let skipDirs: Set<String> = [
            "node_modules", ".git", ".svn", ".hg",
            "DerivedData", ".build", "__pycache__",
            ".next", ".nuxt", "dist", "build", ".DS_Store"
        ]

        guard let contents = try? fm.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var nodes: [FileNode] = []

        for itemURL in contents {
            let name = itemURL.lastPathComponent
            if skipDirs.contains(name) { continue }

            let isDir = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let node = FileNode(url: itemURL, isDirectory: isDir)

            // Eagerly load one level deep so the sidebar shows expand arrows
            if isDir {
                node.children = buildTree(at: itemURL)
            }

            nodes.append(node)
        }

        // Sort: directories first, then alphabetical
        nodes.sort { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }

        return nodes
    }

    // MARK: - SF Symbol for file type

    /// Returns an appropriate SF Symbol name for the sidebar icon.
    var iconName: String {
        if isDirectory { return "folder.fill" }
        switch fileExtension {
        case "html", "htm":   return "globe"
        case "css":            return "paintbrush.fill"
        case "js":             return "bolt.fill"
        case "jsx":            return "atom"               // React
        case "tsx":            return "atom"
        case "ts":             return "t.square.fill"
        case "json":           return "curlybraces"
        case "md", "markdown": return "doc.richtext"
        case "png", "jpg", "jpeg", "gif", "svg", "webp", "ico":
            return "photo"
        case "swift":          return "swift"
        case "py":             return "chevron.left.forwardslash.chevron.right"
        default:               return "doc.text"
        }
    }

    /// Tint color for the icon (makes the tree more scannable)
    var iconColorName: String {
        if isDirectory { return "accentColor" }
        switch fileExtension {
        case "html", "htm":   return "orange"
        case "css":            return "blue"
        case "js":             return "yellow"
        case "jsx", "tsx":     return "cyan"
        case "ts":             return "blue"
        case "json":           return "green"
        case "md", "markdown": return "purple"
        case "png", "jpg", "jpeg", "gif", "svg", "webp":
            return "pink"
        default:               return "gray"
        }
    }
}
