// ───────────────────────────────────────────────────────────────────────────────
// MarkdownRenderer.swift — Markdown → HTML conversion
// ───────────────────────────────────────────────────────────────────────────────
// Converts .md files to styled HTML for display in WKWebView.
// Uses a simple regex-based parser for common Markdown constructs.
//
// We avoid external dependencies (like cmark) to keep the project self-contained.
// The parser handles: headings, bold, italic, code blocks, inline code,
// links, images, lists, blockquotes, and horizontal rules.
// For production use, you'd want a full CommonMark parser.
// ───────────────────────────────────────────────────────────────────────────────

import Foundation

enum MarkdownRenderer {

    /// Convert a Markdown string to a full HTML document with inline styles.
    static func render(_ markdown: String, baseURL: URL? = nil) -> String {
        let body = markdownToHTML(markdown)
        return wrapInHTMLDocument(body: body, baseURL: baseURL)
    }

    // MARK: - Markdown → HTML Body

    private static func markdownToHTML(_ input: String) -> String {
        let lines = input.components(separatedBy: "\n")
        var html = ""
        var inCodeBlock = false
        var codeBlockLang = ""
        var codeBlockContent = ""
        var inList = false
        var listType = "" // "ul" or "ol"

        for line in lines {
            // ── Fenced code blocks ──
            if line.hasPrefix("```") {
                if inCodeBlock {
                    // End code block
                    let escaped = escapeHTML(codeBlockContent)
                    html += "<pre><code class=\"language-\(codeBlockLang)\">\(escaped)</code></pre>\n"
                    inCodeBlock = false
                    codeBlockContent = ""
                    codeBlockLang = ""
                } else {
                    // Start code block
                    closeList(&html, &inList, &listType)
                    inCodeBlock = true
                    codeBlockLang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }
                continue
            }

            if inCodeBlock {
                codeBlockContent += line + "\n"
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // ── Empty line ──
            if trimmed.isEmpty {
                closeList(&html, &inList, &listType)
                html += "\n"
                continue
            }

            // ── Horizontal rule ──
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                closeList(&html, &inList, &listType)
                html += "<hr>\n"
                continue
            }

            // ── Headings ──
            if let heading = parseHeading(trimmed) {
                closeList(&html, &inList, &listType)
                html += heading
                continue
            }

            // ── Blockquote ──
            if trimmed.hasPrefix("> ") {
                closeList(&html, &inList, &listType)
                let content = applyInlineFormatting(String(trimmed.dropFirst(2)))
                html += "<blockquote><p>\(content)</p></blockquote>\n"
                continue
            }

            // ── Unordered list ──
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                if !inList || listType != "ul" {
                    closeList(&html, &inList, &listType)
                    html += "<ul>\n"
                    inList = true
                    listType = "ul"
                }
                let content = applyInlineFormatting(String(trimmed.dropFirst(2)))
                html += "  <li>\(content)</li>\n"
                continue
            }

            // ── Ordered list ──
            if let range = trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                if !inList || listType != "ol" {
                    closeList(&html, &inList, &listType)
                    html += "<ol>\n"
                    inList = true
                    listType = "ol"
                }
                let content = applyInlineFormatting(String(trimmed[range.upperBound...]))
                html += "  <li>\(content)</li>\n"
                continue
            }

            // ── Paragraph ──
            closeList(&html, &inList, &listType)
            html += "<p>\(applyInlineFormatting(trimmed))</p>\n"
        }

        // Close any open blocks
        closeList(&html, &inList, &listType)
        if inCodeBlock {
            let escaped = escapeHTML(codeBlockContent)
            html += "<pre><code>\(escaped)</code></pre>\n"
        }

        return html
    }

    // MARK: - Inline Formatting

    /// Apply bold, italic, code, links, and images within a line of text.
    private static func applyInlineFormatting(_ text: String) -> String {
        var result = escapeHTML(text)

        // Images: ![alt](url)
        result = result.replacingOccurrences(
            of: #"!\[([^\]]*)\]\(([^)]+)\)"#,
            with: "<img src=\"$2\" alt=\"$1\" style=\"max-width:100%\">",
            options: .regularExpression
        )

        // Links: [text](url)
        result = result.replacingOccurrences(
            of: #"\[([^\]]+)\]\(([^)]+)\)"#,
            with: "<a href=\"$2\">$1</a>",
            options: .regularExpression
        )

        // Bold: **text** or __text__
        result = result.replacingOccurrences(
            of: #"\*\*(.+?)\*\*"#,
            with: "<strong>$1</strong>",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"__(.+?)__"#,
            with: "<strong>$1</strong>",
            options: .regularExpression
        )

        // Italic: *text* or _text_
        result = result.replacingOccurrences(
            of: #"\*(.+?)\*"#,
            with: "<em>$1</em>",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?<!\w)_(.+?)_(?!\w)"#,
            with: "<em>$1</em>",
            options: .regularExpression
        )

        // Inline code: `code`
        // Note: We use NSRegularExpression here because Swift's
        // replacingOccurrences(of:with:options:.regularExpression) interprets
        // "$1" inside string interpolation as a closure argument, not a
        // regex backreference.
        if let regex = try? NSRegularExpression(pattern: "`([^`]+)`") {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result, range: range,
                withTemplate: "<code class=\"inline\">$1</code>"
            )
        }

        return result
    }

    // MARK: - Heading Parser

    private static func parseHeading(_ line: String) -> String? {
        let levels: [(prefix: String, tag: String)] = [
            ("######", "h6"), ("#####", "h5"), ("####", "h4"),
            ("###", "h3"), ("##", "h2"), ("#", "h1")
        ]
        for (prefix, tag) in levels {
            if line.hasPrefix(prefix + " ") {
                let content = applyInlineFormatting(
                    String(line.dropFirst(prefix.count + 1))
                )
                return "<\(tag)>\(content)</\(tag)>\n"
            }
        }
        return nil
    }

    // MARK: - List Helpers

    private static func closeList(_ html: inout String, _ inList: inout Bool, _ listType: inout String) {
        if inList {
            html += "</\(listType)>\n"
            inList = false
            listType = ""
        }
    }

    // MARK: - HTML Escaping

    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: - HTML Document Wrapper

    /// Wrap an HTML body in a complete document with GitHub-like styling.
    private static func wrapInHTMLDocument(body: String, baseURL: URL?) -> String {
        let baseTag = baseURL.map { "<base href=\"\($0.absoluteString)\">" } ?? ""
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        \(baseTag)
        <style>
        \(markdownCSS)
        </style>
        </head>
        <body class="markdown-body">
        \(body)
        </body>
        </html>
        """
    }

    // MARK: - Markdown CSS (GitHub-inspired)

    private static let markdownCSS = """
    :root {
        color-scheme: light dark;
    }
    body.markdown-body {
        font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', sans-serif;
        font-size: 15px;
        line-height: 1.7;
        color: #1d1d1f;
        max-width: 820px;
        margin: 0 auto;
        padding: 32px 24px;
    }
    @media (prefers-color-scheme: dark) {
        body.markdown-body { color: #f5f5f7; background: #1c1c1e; }
        code.inline { background: #2c2c2e; }
        pre { background: #2c2c2e !important; }
        blockquote { border-color: #48484a; color: #98989d; }
        hr { background: #38383a; }
        a { color: #64d2ff; }
        th { background: #2c2c2e; }
        td, th { border-color: #38383a; }
    }
    h1, h2, h3, h4, h5, h6 {
        margin-top: 28px; margin-bottom: 12px; font-weight: 600;
    }
    h1 { font-size: 2em; border-bottom: 1px solid #d1d1d6; padding-bottom: 8px; }
    h2 { font-size: 1.5em; border-bottom: 1px solid #d1d1d6; padding-bottom: 6px; }
    h3 { font-size: 1.25em; }
    p { margin: 8px 0 16px; }
    a { color: #0071e3; text-decoration: none; }
    a:hover { text-decoration: underline; }
    code.inline {
        background: #f2f2f7; padding: 2px 6px; border-radius: 4px;
        font-family: 'SF Mono', Menlo, monospace; font-size: 0.9em;
    }
    pre {
        background: #f2f2f7; padding: 16px; border-radius: 8px;
        overflow-x: auto; font-size: 0.88em;
    }
    pre code {
        font-family: 'SF Mono', Menlo, monospace;
        background: none; padding: 0;
    }
    blockquote {
        border-left: 4px solid #d1d1d6; margin: 16px 0; padding: 4px 16px;
        color: #6e6e73;
    }
    ul, ol { padding-left: 28px; }
    li { margin: 4px 0; }
    img { max-width: 100%; border-radius: 8px; margin: 8px 0; }
    hr { border: none; height: 1px; background: #d1d1d6; margin: 24px 0; }
    table {
        border-collapse: collapse; width: 100%; margin: 16px 0;
    }
    th, td {
        border: 1px solid #d1d1d6; padding: 8px 12px; text-align: left;
    }
    th { background: #f2f2f7; font-weight: 600; }
    """
}
