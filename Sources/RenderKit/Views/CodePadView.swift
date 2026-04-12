// ───────────────────────────────────────────────────────────────────────────────
// CodePadView.swift — Paste-and-preview code editor sidebar
// ───────────────────────────────────────────────────────────────────────────────
// Replaces the file tree sidebar when Code Pad mode is active.
// Provides:
//   - A language picker (HTML, JSX, TSX, CSS, JS, Markdown, JSON, SVG)
//   - A text editor for pasting/typing code
//   - Render button (also auto-renders on pause after typing)
//   - Save As button to export to a file
//   - Back button to return to the file tree
//
// The preview panel on the right renders whatever is in the editor,
// based on the selected language.
// ───────────────────────────────────────────────────────────────────────────────

import SwiftUI
import Combine

struct CodePadView: View {
    @ObservedObject var appState: AppState

    /// Debounce timer — auto-render 0.6s after user stops typing
    @State private var debounceTimer: AnyCancellable?

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "doc.text.magnifyingglass")
                        .foregroundColor(.accentColor)
                    Text("Code Pad")
                        .font(.headline)
                    Spacer()
                    Button(action: { appState.closeCodePad() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Back to file browser")
                }

                // Language picker
                Picker("Language", selection: $appState.codePadLanguage) {
                    ForEach(CodePadLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: appState.codePadLanguage) { _ in
                    // Re-render when language changes (same code, different renderer)
                    appState.renderCodePad()
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // ── Code Editor (NSTextView — supports ⌘F find bar) ──
            ZStack(alignment: .topLeading) {
                // Placeholder text when editor is empty
                if appState.codePadText.isEmpty {
                    Text(appState.codePadLanguage.placeholder)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }

                CodeEditorView(
                    text: $appState.codePadText,
                    onTextChange: {
                        // Auto-render after a short pause
                        debounceTimer?.cancel()
                        debounceTimer = Just(())
                            .delay(for: .milliseconds(600), scheduler: RunLoop.main)
                            .sink { _ in
                                appState.renderCodePad()
                            }
                    }
                )
            }

            Divider()

            // ── Bottom Actions ──
            HStack(spacing: 8) {
                // Render button
                Button(action: { appState.renderCodePad() }) {
                    Label("Render", systemImage: "play.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.return, modifiers: .command)

                // Save As
                Button(action: { appState.saveCodePadToFile() }) {
                    Label("Save As", systemImage: "square.and.arrow.down")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                // Character count
                Text("\(appState.codePadText.count) chars")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)

                // Clear button
                if !appState.codePadText.isEmpty {
                    Button(action: {
                        appState.codePadText = ""
                        appState.renderCodePad()
                    }) {
                        Text("Clear")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }
}
