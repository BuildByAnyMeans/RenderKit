// ───────────────────────────────────────────────────────────────────────────────
// FileTreeView.swift — Recursive file tree sidebar
// ───────────────────────────────────────────────────────────────────────────────
// Displays the project's file structure as a collapsible tree using SwiftUI's
// List with DisclosureGroup for directories. Each file shows an SF Symbol icon
// color-coded by file type.
//
// Architecture: This view is intentionally "dumb" — it only reads FileNode
// data and sends selection events to AppState. All business logic lives in
// AppState.
// ───────────────────────────────────────────────────────────────────────────────

import SwiftUI

struct FileTreeView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // ── Project Header ──
            if let root = appState.rootFolder {
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.accentColor)
                    Text(root.lastPathComponent)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()
            }

            // ── File Tree ──
            if appState.fileTree.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("No files to show")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(selection: $appState.selectedFile) {
                    ForEach(appState.fileTree) { node in
                        FileTreeNodeView(node: node, appState: appState)
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }
}

// MARK: - Recursive Node View

/// Renders a single file or directory node. Directories use DisclosureGroup
/// to show/hide children recursively.
struct FileTreeNodeView: View {
    @ObservedObject var node: FileNode
    @ObservedObject var appState: AppState

    var body: some View {
        if node.isDirectory {
            // ── Directory ──
            DisclosureGroup(isExpanded: $node.isExpanded) {
                if let children = node.children {
                    ForEach(children) { child in
                        FileTreeNodeView(node: child, appState: appState)
                    }
                }
            } label: {
                Label {
                    Text(node.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } icon: {
                    Image(systemName: node.iconName)
                        .foregroundColor(colorForNode(node))
                }
            }
        } else {
            // ── File ──
            Label {
                Text(node.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: node.iconName)
                    .foregroundColor(colorForNode(node))
            }
            .tag(node) // Enables selection binding
            .contextMenu {
                fileContextMenu(for: node)
            }
        }
    }

    /// Map the node's color name to a SwiftUI Color.
    private func colorForNode(_ node: FileNode) -> Color {
        switch node.iconColorName {
        case "orange":      return .orange
        case "blue":        return .blue
        case "yellow":      return .yellow
        case "cyan":        return .cyan
        case "green":       return .green
        case "purple":      return .purple
        case "pink":        return .pink
        case "gray":        return .gray
        case "accentColor": return .accentColor
        default:            return .secondary
        }
    }

    /// Right-click context menu for files.
    @ViewBuilder
    private func fileContextMenu(for node: FileNode) -> some View {
        Button("Copy File Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(node.url.path, forType: .string)
        }

        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([node.url])
        }

        Button("Open in Default App") {
            NSWorkspace.shared.open(node.url)
        }

        if node.fileExtension == "html" {
            Divider()
            Button("Open in Browser") {
                NSWorkspace.shared.open(node.url)
            }
        }
    }
}
