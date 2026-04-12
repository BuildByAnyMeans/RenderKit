// swift-tools-version: 5.9
// ───────────────────────────────────────────────────────────────────────────────
// RenderKit – A native macOS front-end file previewer
// Built with SwiftUI + WKWebView. Open a folder, click a file, see it rendered.
// ───────────────────────────────────────────────────────────────────────────────

import PackageDescription

let package = Package(
    name: "RenderKit",
    platforms: [
        // macOS 13 (Ventura) for NavigationSplitView and modern SwiftUI APIs
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "RenderKit",
            path: "Sources/RenderKit"
        )
    ]
)
