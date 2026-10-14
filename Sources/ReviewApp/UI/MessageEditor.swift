import ReviewCore
import AppKit
import SwiftUI

struct MessageEditor: NSViewRepresentable {
    @Binding var text: String
    var takesFocus = true
    var focusChanged: ((Bool) -> Void)? = nil
    let commit: () -> Void
    let cancel: () -> Void

    enum KeyAction: Equatable {
        case commit, newLine, cancel, nextControl, previousControl
    }

    static func keyAction(for selector: Selector, shift: Bool) -> KeyAction? {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)): shift ? .newLine : .commit
        case #selector(NSResponder.cancelOperation(_:)): .cancel
        case #selector(NSResponder.insertTab(_:)): .nextControl
        case #selector(NSResponder.insertBacktab(_:)): .previousControl
        default: nil
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        let size = scroll.contentSize
        let view = FocusTextView(frame: NSRect(origin: .zero, size: size))
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.containerSize = NSSize(width: size.width, height: .greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = true
        scroll.documentView = view
        view.focusChanged = focusChanged
        view.delegate = context.coordinator
        view.isRichText = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.font = .systemFont(ofSize: NSFont.systemFontSize)
        view.textColor = context.environment.palette.nsColor(.textPrimary)
        view.insertionPointColor = context.environment.palette.nsColor(.textPrimary)
        view.textContainerInset = Self.inset
        view.string = text
        view.setAccessibilityLabel("Message")
        guard takesFocus else { return scroll }
        Task { [weak view] in
            guard let view, let window = view.window else { return }
            window.makeFirstResponder(view)
            view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NSTextView else { return }
        (view as? FocusTextView)?.focusChanged = focusChanged
        let ink = context.environment.palette.nsColor(.textPrimary)
        if view.textColor != ink {
            view.textColor = ink
            view.insertionPointColor = ink
        }
        guard view.string != text else { return }
        view.string = text
    }

    static let inset = NSSize(width: 3, height: 6)

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MessageEditor

        init(_ parent: MessageEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            let shift = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
            switch MessageEditor.keyAction(for: selector, shift: shift) {
            case .commit: parent.commit()
            case .newLine: textView.insertNewlineIgnoringFieldEditor(nil)
            case .nextControl: textView.window?.selectNextKeyView(nil)
            case .previousControl: textView.window?.selectPreviousKeyView(nil)
            case .cancel:
                parent.cancel()
                if !parent.takesFocus { textView.window?.makeFirstResponder(nil) }
            case nil: return false
            }
            return true
        }
    }
}

final class FocusTextView: NSTextView {
    var focusChanged: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let took = super.becomeFirstResponder()
        if took { report(true) }
        return took
    }

    override func resignFirstResponder() -> Bool {
        let gave = super.resignFirstResponder()
        if gave { report(false) }
        return gave
    }

    private func report(_ focused: Bool) {
        guard let focusChanged else { return }
        Task { @MainActor in focusChanged(focused) }
    }
}

struct MessageField: View {
    @Binding var text: String
    var placeholder = "Add a message…"
    var takesFocus = true
    var wellFocus: ThemeToken? = nil
    let commit: () -> Void
    let cancel: () -> Void
    @State private var isFocused = false
    @Environment(\.palette) private var palette
    @Environment(\.controlActiveState) private var activeState

    private static let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)

    var body: some View {
        MessageEditor(text: $text, takesFocus: takesFocus, focusChanged: { isFocused = $0 }, commit: commit, cancel: cancel)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(palette[.textTertiary])
                        .padding(.leading, MessageEditor.inset.width + 5)
                        .padding(.top, MessageEditor.inset.height)
                        .allowsHitTesting(false)
                }
            }
            .background(palette[wellFocus == nil ? .field : .well], in: Self.shape)
            .overlay { Self.shape.strokeBorder(hairline, lineWidth: 1) }
            .overlay {
                if wellFocus == nil, isFocused, activeState == .key {
                    FocusRing(cornerRadius: 7)
                }
            }
            .animation(.easeOut(duration: 0.15), value: isFocused && activeState == .key)
    }

    private var hairline: Color {
        guard let wellFocus, isFocused, activeState == .key else { return palette[.separator] }
        return palette[wellFocus].opacity(0.5)
    }
}

struct FocusRing: View {
    let cornerRadius: CGFloat
    static let width: CGFloat = 3
    @Environment(\.palette) private var palette

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius + Self.width / 2, style: .continuous)
            .stroke(palette.focusRing, lineWidth: Self.width)
            .padding(-Self.width / 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
