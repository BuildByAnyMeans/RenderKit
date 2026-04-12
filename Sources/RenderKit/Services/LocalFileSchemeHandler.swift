// ───────────────────────────────────────────────────────────────────────────────
// LocalFileSchemeHandler.swift — Custom WKURLSchemeHandler for local files
// ───────────────────────────────────────────────────────────────────────────────
// Registers the custom URL scheme "rk" with WKWebView. When the web view
// loads "rk:///Users/me/project/index.html", this handler:
//   1. Strips the scheme to get the file path
//   2. Reads the file from disk
//   3. Returns the data with the correct MIME type
//
// Why not just use loadFileURL()? This scheme handler approach:
//   - Handles relative paths seamlessly (CSS, JS, images)
//   - Allows JavaScript fetch() to local files (no CORS issues)
//   - Gives us full control over headers and caching
//   - Works consistently across all file types
// ───────────────────────────────────────────────────────────────────────────────

import Foundation
import WebKit

/// The custom URL scheme we register. All local file previews are served
/// through URLs like: rk:///absolute/path/to/file.html
let kRenderKitScheme = "rk"

final class LocalFileSchemeHandler: NSObject, WKURLSchemeHandler {

    // MARK: - WKURLSchemeHandler

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            fail(urlSchemeTask, message: "No URL in request")
            return
        }

        // The URL looks like: rk:///Users/me/project/style.css
        // We extract the path component to get the filesystem path.
        let filePath = url.path

        // Security check: path must be absolute
        guard filePath.hasPrefix("/") else {
            fail(urlSchemeTask, message: "Relative paths not allowed: \(filePath)")
            return
        }

        let fileURL = URL(fileURLWithPath: filePath)

        // Read the file from disk
        guard let data = try? Data(contentsOf: fileURL) else {
            // Return a 404-style error page
            let html = """
            <html><body style="font-family:system-ui;padding:40px;color:#666">
            <h2>File Not Found</h2>
            <p>Could not read: <code>\(filePath)</code></p>
            </body></html>
            """
            let htmlData = html.data(using: .utf8) ?? Data()
            respond(urlSchemeTask, data: htmlData, mimeType: "text/html", filePath: filePath)
            return
        }

        // Determine MIME type from extension
        let ext = fileURL.pathExtension.lowercased()
        let mimeType = FileTypeHelper.mimeType(for: ext)

        respond(urlSchemeTask, data: data, mimeType: mimeType, filePath: filePath)
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Nothing to cancel — our reads are synchronous.
        // In a production app you might want async reads with cancellation support.
    }

    // MARK: - Helpers

    /// Send a successful response to the scheme task.
    private func respond(
        _ task: WKURLSchemeTask,
        data: Data,
        mimeType: String,
        filePath: String
    ) {
        // Build an HTTPURLResponse so WebKit sees proper headers
        let headers: [String: String] = [
            "Content-Type": mimeType,
            "Content-Length": "\(data.count)",
            "Cache-Control": "no-cache",  // Always serve fresh for live reload
            // Allow CORS for local file access from JavaScript
            "Access-Control-Allow-Origin": "*"
        ]

        if let response = HTTPURLResponse(
            url: task.request.url ?? URL(string: "rk:///")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) {
            task.didReceive(response)
        }

        task.didReceive(data)
        task.didFinish()
    }

    /// Send an error response.
    private func fail(_ task: WKURLSchemeTask, message: String) {
        let error = NSError(
            domain: "com.renderkit.scheme",
            code: 404,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
        task.didFailWithError(error)
    }

    // MARK: - URL Construction

    /// Convert a local file URL to a custom-scheme URL for WKWebView loading.
    /// Example: file:///Users/me/project/index.html → rk:///Users/me/project/index.html
    static func schemeURL(for fileURL: URL) -> URL? {
        var components = URLComponents()
        components.scheme = kRenderKitScheme
        components.host = ""
        components.path = fileURL.path
        return components.url
    }
}
