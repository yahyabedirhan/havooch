import AppKit
import SwiftUI

/// The text view a comment is written in: in the comment box and on a card
/// that's being edited, and an answer under a question. It's a standard
/// `NSTextView` that takes the focus when it appears, so the player's keys
/// stand back while the person types and dictation has a normal text view
/// to type into. An answer box waits for a click instead (`takesFocus`
/// false): a question arrives while the person does something else.
///
/// Return commits, Shift+Return makes a new line, Escape cancels.
struct CommentEditor: NSViewRepresentable {
    @Binding var text: String
    var takesFocus = true
    let commit: () -> Void
    let cancel: () -> Void

    /// What a key does in the editor.
    enum KeyAction: Equatable {
        case commit, newLine, cancel
    }

    /// The action of the text view's command `selector`, if the editor
    /// takes it; any other command is the text view's own.
    static func keyAction(for selector: Selector, shift: Bool) -> KeyAction? {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)): shift ? .newLine : .commit
        case #selector(NSResponder.cancelOperation(_:)): .cancel
        default: nil
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        guard let view = scroll.documentView as? NSTextView else { return scroll }
        view.delegate = context.coordinator
        view.isRichText = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.font = .systemFont(ofSize: NSFont.systemFontSize)
        view.textColor = .labelColor
        view.textContainerInset = Self.inset
        view.string = text
        view.setAccessibilityLabel("Comment")
        guard takesFocus else { return scroll }
        // Once the view is in its window: the person types at once.
        Task { [weak view] in
            guard let view, let window = view.window else { return }
            window.makeFirstResponder(view)
            view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NSTextView, view.string != text else { return }
        view.string = text
    }

    /// The space around the text, which a placeholder over the editor
    /// lines up with.
    static let inset = NSSize(width: 3, height: 6)

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CommentEditor

        init(_ parent: CommentEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            let shift = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
            switch CommentEditor.keyAction(for: selector, shift: shift) {
            case .commit: parent.commit()
            case .newLine: textView.insertNewlineIgnoringFieldEditor(nil)
            case .cancel:
                parent.cancel()
                // A box that stays on screen gives the keys back to the player.
                if !parent.takesFocus { textView.window?.makeFirstResponder(nil) }
            case nil: return false
            }
            return true
        }
    }
}

/// The editor with its placeholder, in the field look both of its places
/// share.
struct CommentField: View {
    @Binding var text: String
    var placeholder = "Add a comment…"
    var takesFocus = true
    let commit: () -> Void
    let cancel: () -> Void

    var body: some View {
        CommentEditor(text: $text, takesFocus: takesFocus, commit: commit, cancel: cancel)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.tertiary)
                        // The text container's own 5 pt of line padding.
                        .padding(.leading, CommentEditor.inset.width + 5)
                        .padding(.top, CommentEditor.inset.height)
                        .allowsHitTesting(false)
                }
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.tint.opacity(0.55), lineWidth: 1.5)
            }
    }
}
