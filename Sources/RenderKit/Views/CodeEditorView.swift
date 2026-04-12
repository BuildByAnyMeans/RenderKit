// ───────────────────────────────────────────────────────────────────────────────
// CodeEditorView.swift — NSTextView wrapper with native find bar support
// ───────────────────────────────────────────────────────────────────────────────
// Wraps NSTextView in an NSViewRepresentable so we get:
//   - ⌘F find bar (built into NSTextView)
//   - ⌘G find next, ⇧⌘G find previous
//   - ⌘⌥F find and replace
//   - Proper undo/redo
//   - Line wrapping with horizontal scroll when needed
// ───────────────────────────────────────────────────────────────────────────────

import SwiftUI
import AppKit

struct CodeEditorView: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    var onTextChange: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = FindableTextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.font = font
        textView.textColor = NSColor.textColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false

        // Use text wrapping so horizontal scroll isn't needed
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true

        // Insets for comfortable editing
        textView.textContainerInset = NSSize(width: 6, height: 8)

        // Enable the find bar (uses NSTextView's built-in support)
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true

        // Set initial text
        textView.string = text

        scrollView.documentView = textView
        context.coordinator.textView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Only update if the text actually changed from outside (avoid cursor jump)
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }
        textView.font = font
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditorView
        weak var textView: NSTextView?

        init(_ parent: CodeEditorView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.onTextChange?()
        }
    }
}

// MARK: - FindableTextView

/// Custom NSTextView subclass that ensures ⌘F works by responding to
/// performFindPanelAction even when embedded in SwiftUI.
class FindableTextView: NSTextView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Intercept ⌘F to show the find bar (SwiftUI sometimes eats it)
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "f" {
            performFindPanelAction(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
