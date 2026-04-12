// ───────────────────────────────────────────────────────────────────────────────
// TerminalOutputView.swift — Dev server log/terminal panel
// ───────────────────────────────────────────────────────────────────────────────
// Displays real-time output from the dev server or sandbox process.
// Uses a monospaced font and auto-scrolls to the bottom as new output arrives.
// This sits at the bottom of the preview area as a collapsible panel.
// ───────────────────────────────────────────────────────────────────────────────

import SwiftUI

struct TerminalOutputView: View {
    /// The log lines to display. Binds to DevServerManager.logs or SandboxManager.logs.
    let logs: [String]

    /// Called when the user clicks "Clear"
    var onClear: (() -> Void)?

    /// Called when the user clicks "Stop"
    var onStop: (() -> Void)?

    /// Whether a server is currently running (affects Stop button state)
    var isRunning: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // ── Header Bar ──
            HStack {
                Image(systemName: "terminal.fill")
                    .foregroundColor(.secondary)
                Text("Terminal Output")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                Spacer()

                if isRunning {
                    // Pulsing green dot to show server is running
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    Text("Running")
                        .font(.caption2)
                        .foregroundColor(.green)
                }

                Button(action: { onClear?() }) {
                    Text("Clear")
                        .font(.caption)
                }
                .buttonStyle(.borderless)

                if isRunning {
                    Button(action: { onStop?() }) {
                        Text("Stop")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // ── Log Content ──
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(logs.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(colorForLine(line))
                                .textSelection(.enabled)
                                .id(index)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                .onChange(of: logs.count) { _ in
                    // Auto-scroll to bottom when new output arrives
                    if let lastIndex = logs.indices.last {
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(lastIndex, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(height: 200)
    }

    // MARK: - Helpers

    /// Color-code terminal output lines for readability.
    private func colorForLine(_ line: String) -> Color {
        let lower = line.lowercased()
        if lower.contains("error") || lower.contains("failed") || lower.contains("fatal") {
            return .red
        }
        if lower.contains("warning") || lower.contains("warn") {
            return .orange
        }
        if lower.contains("[renderkit]") {
            return .blue
        }
        if lower.contains("ready") || lower.contains("started") || lower.contains("compiled") {
            return .green
        }
        return .primary
    }
}
