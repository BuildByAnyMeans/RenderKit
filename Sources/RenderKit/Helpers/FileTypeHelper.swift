// ───────────────────────────────────────────────────────────────────────────────
// FileTypeHelper.swift — File type classification and MIME type lookup
// ───────────────────────────────────────────────────────────────────────────────
// Centralizes all file-type logic: which files can be rendered in WKWebView,
// which need syntax highlighting, which are images, etc.
// Also provides MIME types for the custom URL scheme handler.
// ───────────────────────────────────────────────────────────────────────────────

import Foundation

/// How a file should be previewed in the app.
enum PreviewMode {
    case webRender       // Load directly in WKWebView (HTML files)
    case markdownRender  // Convert MD → HTML then load in WKWebView
    case syntaxHighlight // Show as syntax-highlighted source code
    case imagePreview    // Display image in WKWebView via <img> tag
    case jsonPretty      // Pretty-print JSON with syntax highlighting
    case reactComponent  // JSX/TSX — needs dev server or sandbox
    case unsupported     // Can't preview this file type
}

enum FileTypeHelper {

    // MARK: - Preview Mode

    /// Determine how to preview a file based on its extension.
    static func previewMode(for extension: String) -> PreviewMode {
        switch `extension`.lowercased() {
        case "html", "htm":
            return .webRender
        case "md", "markdown":
            return .markdownRender
        case "svg":
            return .webRender
        case "css", "js", "ts", "swift", "py", "rb", "go", "rs",
             "java", "c", "cpp", "h", "hpp", "sh", "bash", "zsh",
             "yaml", "yml", "toml", "xml", "graphql", "sql",
             "env", "gitignore", "dockerfile":
            return .syntaxHighlight
        case "json":
            return .jsonPretty
        case "jsx", "tsx":
            return .reactComponent
        case "png", "jpg", "jpeg", "gif", "webp", "bmp", "ico", "tiff":
            return .imagePreview
        default:
            return .unsupported
        }
    }

    // MARK: - MIME Types

    /// Map file extension to MIME type (used by the URL scheme handler).
    static func mimeType(for extension: String) -> String {
        switch `extension`.lowercased() {
        // Web fundamentals
        case "html", "htm": return "text/html"
        case "css":         return "text/css"
        case "js", "mjs":   return "application/javascript"
        case "json":        return "application/json"
        case "xml":         return "application/xml"
        case "svg":         return "image/svg+xml"

        // Images
        case "png":         return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif":         return "image/gif"
        case "webp":        return "image/webp"
        case "ico":         return "image/x-icon"
        case "bmp":         return "image/bmp"
        case "tiff":        return "image/tiff"

        // Fonts
        case "woff":        return "font/woff"
        case "woff2":       return "font/woff2"
        case "ttf":         return "font/ttf"
        case "otf":         return "font/otf"
        case "eot":         return "application/vnd.ms-fontobject"

        // Media
        case "mp4":         return "video/mp4"
        case "webm":        return "video/webm"
        case "mp3":         return "audio/mpeg"
        case "wav":         return "audio/wav"

        // Other text
        case "md", "markdown": return "text/markdown"
        case "txt":            return "text/plain"
        case "csv":            return "text/csv"

        // Source code (serve as plain text)
        case "ts", "tsx", "jsx", "swift", "py", "rb", "go", "rs",
             "java", "c", "cpp", "h", "hpp", "sh", "yaml", "yml",
             "toml", "sql":
            return "text/plain"

        default:
            return "application/octet-stream"
        }
    }

    // MARK: - Language Identifier for Syntax Highlighting

    /// Returns a Prism.js / highlight.js language identifier for code blocks.
    static func languageIdentifier(for extension: String) -> String {
        switch `extension`.lowercased() {
        case "js", "mjs":        return "javascript"
        case "jsx":              return "jsx"
        case "ts":               return "typescript"
        case "tsx":              return "tsx"
        case "html", "htm":      return "html"
        case "css":              return "css"
        case "json":             return "json"
        case "md", "markdown":   return "markdown"
        case "swift":            return "swift"
        case "py":               return "python"
        case "rb":               return "ruby"
        case "go":               return "go"
        case "rs":               return "rust"
        case "java":             return "java"
        case "c":                return "c"
        case "cpp", "hpp":       return "cpp"
        case "h":                return "c"
        case "sh", "bash", "zsh":return "bash"
        case "yaml", "yml":      return "yaml"
        case "toml":             return "toml"
        case "xml":              return "xml"
        case "svg":              return "xml"
        case "sql":              return "sql"
        case "graphql":          return "graphql"
        case "dockerfile":       return "docker"
        default:                 return "plaintext"
        }
    }

    // MARK: - Utilities

    /// Check if a file extension represents a text-based file we can read.
    static func isTextFile(extension ext: String) -> Bool {
        previewMode(for: ext) != .unsupported || ext == "txt"
    }

    /// Check if the file is a web asset (loadable inside HTML).
    static func isWebAsset(extension ext: String) -> Bool {
        let webAssets: Set<String> = [
            "html", "htm", "css", "js", "mjs", "json", "svg",
            "png", "jpg", "jpeg", "gif", "webp", "ico",
            "woff", "woff2", "ttf", "otf", "eot",
            "mp4", "webm", "mp3", "wav"
        ]
        return webAssets.contains(ext.lowercased())
    }
}
