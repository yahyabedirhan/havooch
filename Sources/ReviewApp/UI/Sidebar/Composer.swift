import AppKit
import ReviewCore
import SwiftUI

/// The one composer of the sidebar (L41, L68), at its foot above the
/// footer, in the thread list and in a thread view alike: one rounded card.
/// The words take its top, in a field that starts two lines tall and grows
/// with them up to `ComposerEditor.maxHeight`. A slim toolbar under them
/// says where they go (`ComposerTarget.toolbarLabel`): "New thread at 0:12",
/// "#3", "General thread", or "Answer #3, goes at once" in the question
/// colour. Then the region chip with its remove button, in the list the
/// General chip, and Send, whose menu queues instead; an answer has one
/// Answer button. Return queues, Shift+Return adds a line, Cmd+Return sends
/// the queue with the words. No focus ring: the card's hairline turns a
/// soft accent while the field has the focus in the key window.
struct Composer: View {
    let model: WindowModel
    @Environment(\.palette) private var palette
    @Environment(\.controlActiveState) private var activeState
    @State private var height = ComposerEditor.lineHeight
    @State private var isFocused = false

    private static let corner: CGFloat = 10
    private static let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
    /// The field's height at rest, in lines.
    private static let minLines: CGFloat = 2

    /// The Send button's title for `count` messages a send would deliver:
    /// "Send" for one or none, else "Send 3".
    static func sendTitle(_ count: Int) -> String {
        count > 1 ? "Send \(count)" : "Send"
    }

    var body: some View {
        if let target = model.composerTarget {
            VStack(spacing: 0) {
                editor(target)
                toolbar(target)
            }
            .background(palette[.field], in: Self.shape)
            .overlay { Self.shape.strokeBorder(border(target), lineWidth: 1) }
            .animation(.smooth(duration: 0.15), value: focused)
            // The tour's write step rings the card (H4).
            .coachRing(model.tourRings(.composer), radius: Self.corner)
            .padding(10)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .top) { Hairline(axis: .horizontal) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Composer")
        }
    }

    /// The field has the focus in the key window: a window behind another
    /// draws no focus look.
    private var focused: Bool { isFocused && activeState == .key }

    /// The card's hairline: `separator` at rest, a soft accent with the
    /// focus; for an answer, the question colour, stronger with the focus.
    private func border(_ target: ComposerTarget) -> Color {
        if target.answers { return palette[.question].opacity(focused ? 0.7 : 0.4) }
        return focused ? palette[.accent].opacity(0.6) : palette[.separator]
    }

    private func editor(_ target: ComposerTarget) -> some View {
        let rest = ComposerEditor.lineHeight * Self.minLines
        return ComposerEditor(
            text: Binding(get: { model.composerText }, set: { model.composerText = $0 }),
            height: $height, focusRequests: model.composerFocusRequests,
            focusChanged: { focused in
                isFocused = focused
                if focused { model.composerBegan() }
            },
            commit: { model.submitComposer() },
            cancel: {
                // Escape drops the region chip first; else the player gets the keys back.
                guard model.composerRegion != nil else { return false }
                model.removeComposerRegion()
                return true
            }
        )
        .frame(height: min(max(height, rest), ComposerEditor.maxHeight))
        .overlay(alignment: .topLeading) {
            if model.composerText.isEmpty {
                Text(target.placeholder)
                    .foregroundStyle(palette[.textTertiary])
                    .lineLimit(1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel(target.answers ? "\(target.label), goes at once" : target.label)
        .padding(.horizontal, 11)
        .padding(.top, 9)
        .padding(.bottom, 4)
    }

    /// Where the words go, the region chip, the General chip in the thread
    /// list, and Send.
    private func toolbar(_ target: ComposerTarget) -> some View {
        HStack(spacing: 6) {
            TargetLabel(target: target)
            if model.composerRegion != nil {
                RegionChip(model: model) { model.removeComposerRegion() }
            }
            Spacer(minLength: 4)
            if model.shown == nil {
                GeneralChip(isOn: model.isComposerGeneral) { model.toggleComposerGeneral() }
                    .pressedByKeys(in: model) { model.toggleComposerGeneral() }
            }
            SendControl(model: model, target: target)
        }
        .padding(.leading, 11)
        .padding(.trailing, 6)
        .padding(.bottom, 6)
        .frame(height: 30)
    }
}

/// Where the words go, as a quiet label: "New thread at 0:12", "#3",
/// "General thread", or "Answer #3, goes at once" in the question colour.
private struct TargetLabel: View {
    let target: ComposerTarget
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: target.glyph)
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(target.toolbarLabel)
                .lineLimit(1)
        }
        .font(.subheadline.monospacedDigit())
        .foregroundStyle(target.answers ? palette[.question] : palette[.textTertiary])
        .help(target.line)
        .accessibilityElement(children: .combine)
    }
}

/// The chip of the region that goes with the words, with its remove button.
private struct RegionChip: View {
    let model: WindowModel
    let remove: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "rectangle.dashed")
                .imageScale(.small)
                .accessibilityHidden(true)
            Text("Region")
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .frame(width: 12, height: 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .pressedByKeys(in: model, action: remove)
            .help("Remove the region")
            .accessibilityLabel("Remove the region")
        }
        .font(.subheadline)
        .foregroundStyle(palette[.regionOutline])
        .padding(.leading, 6)
        .padding(.trailing, 3)
        .frame(height: 20)
        .background(palette[.regionOutline].opacity(0.13), in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Region")
    }
}

/// The General toggle as a small capsule chip: the words go to General,
/// not to the frame. Quiet when off, the accent when on.
private struct GeneralChip: View {
    let isOn: Bool
    let toggle: () -> Void
    @Environment(\.palette) private var palette
    @State private var isHovered = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 3) {
                Image(systemName: "globe")
                    .imageScale(.small)
                Text("General")
            }
            .font(.subheadline)
            .foregroundStyle(isOn ? palette[.accent] : palette[isHovered ? .textSecondary : .textTertiary])
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(fill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { isHovered = $0 }
        .animation(.smooth(duration: 0.12), value: isHovered)
        .help(isOn ? "Write at the playhead" : "Write in General, not at a moment")
        .accessibilityLabel("General")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// Off, clear, and `controlHover` under the pointer; on, the accent
    /// tint, a shade stronger under the pointer.
    private var fill: Color {
        if isOn { return palette[.accent].opacity(isHovered ? 0.2 : 0.14) }
        return isHovered ? palette[.controlHover] : .clear
    }
}

/// Send, Cmd+Return's send with the words, and a menu beside it that
/// queues instead. An answer has one Answer button: it goes at once, as
/// Return takes it. Both are filled buttons on `accentFill` (ADR 0006).
private struct SendControl: View {
    let model: WindowModel
    let target: ComposerTarget
    @Environment(\.palette) private var palette

    var body: some View {
        if target.answers {
            Button("Answer") { model.submitComposer() }
                .filledButton(palette)
                .controlSize(.small)
                .fixedSize()
                .disabled(!hasWords)
                .pressedByKeys(in: model) { model.submitComposer() }
                .help("Answer at once (↩)")
        } else {
            // A `Menu` draws no prominent button on macOS, so Send is a
            // filled button of its own and its menu a chevron beside it.
            HStack(spacing: 2) {
                Button(Composer.sendTitle(model.sendCount)) { model.send() }
                    .filledButton(palette)
                    .controlSize(.small)
                    .fixedSize()
                    .disabled(!model.canSend)
                    .pressedByKeys(in: model) { model.send() }
                    .help("Send the queue (⌘↩). Return queues the message.")
                Menu {
                    Button("Queue  ↩") { model.submitComposer() }
                        .disabled(!hasWords)
                    Button("Send  ⌘↩") { model.send() }
                        .disabled(!model.canSend)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(palette[.textSecondary])
                .disabled(!model.canSend)
                .help("Queue or send")
                .accessibilityLabel("Queue or send")
            }
        }
    }

    private var hasWords: Bool { WindowModel.hasWords(model.composerText) }
}

/// The text view of the composer: a standard `NSTextView` (`FocusTextView`),
/// so dictation and the text system work as everywhere, that grows with
/// its words. It never takes the focus by itself, only on a click or a
/// request (`focusRequests`).
private struct ComposerEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    let focusRequests: Int
    /// The text view took (true) or gave up the focus.
    let focusChanged: (Bool) -> Void
    let commit: () -> Void
    /// Escape: true when it was taken; else the field gives the keys back.
    let cancel: () -> Bool

    /// One line of the system font.
    static let lineHeight: CGFloat = 17
    /// About six lines; the field scrolls past them.
    static let maxHeight: CGFloat = 104

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        let view = FocusTextView()
        view.delegate = context.coordinator
        view.isRichText = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.lineFragmentPadding = 0
        view.textContainerInset = .zero
        view.font = .systemFont(ofSize: NSFont.systemFontSize)
        view.textColor = context.environment.palette.nsColor(.textPrimary)
        view.insertionPointColor = context.environment.palette.nsColor(.textPrimary)
        view.string = text
        view.setAccessibilityLabel("Message")
        view.focusChanged = focusChanged
        scroll.documentView = view
        context.coordinator.lastFocusRequest = focusRequests
        // A wider or narrower sidebar wraps the words again: measure anew.
        view.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator, selector: #selector(Coordinator.frameChanged(_:)),
            name: NSView.frameDidChangeNotification, object: view
        )
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? FocusTextView else { return }
        view.focusChanged = focusChanged
        // The theme may change while the composer is on screen.
        let ink = context.environment.palette.nsColor(.textPrimary)
        if view.textColor != ink {
            view.textColor = ink
            view.insertionPointColor = ink
        }
        if view.string != text {
            view.string = text
            view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
        }
        context.coordinator.measure(view)
        if context.coordinator.lastFocusRequest != focusRequests {
            context.coordinator.lastFocusRequest = focusRequests
            // Once the view is in its window: the person types at once.
            Task { @MainActor [weak view] in
                guard let view, let window = view.window else { return }
                window.makeFirstResponder(view)
                view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerEditor
        var lastFocusRequest = 0

        init(_ parent: ComposerEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
            measure(view)
        }

        @objc func frameChanged(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            measure(view)
        }

        /// The height of the words, for the field to grow to.
        func measure(_ view: NSTextView) {
            guard let layout = view.layoutManager, let container = view.textContainer else { return }
            layout.ensureLayout(for: container)
            let used = ceil(layout.usedRect(for: container).height)
            let height = max(used, ComposerEditor.lineHeight)
            guard abs(height - parent.height) > 0.5 else { return }
            Task { @MainActor [parent] in parent.height = height }
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            let shift = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
            switch MessageEditor.keyAction(for: selector, shift: shift) {
            case .commit: parent.commit()
            case .newLine: textView.insertNewlineIgnoringFieldEditor(nil)
            case .nextControl: textView.window?.selectNextKeyView(nil)
            case .previousControl: textView.window?.selectPreviousKeyView(nil)
            case .cancel:
                // The keys go back to the player.
                if !parent.cancel() { textView.window?.makeFirstResponder(nil) }
            case nil: return false
            }
            return true
        }
    }
}
