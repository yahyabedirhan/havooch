import AppKit
import ReviewCore
import SwiftUI

/// The one composer of the sidebar (L41), at its foot above the footer, in
/// the thread list and in a thread view alike. A line names where the
/// words go (`ComposerTarget`): "New thread at 0:12", "Reply on #3",
/// "Follow up on #3", or "Answer #3 · goes at once" in the question
/// colour. A region drawn on the frame shows as a chip with a remove
/// button; in the list a General toggle writes to General. The field
/// grows with the words up to `maxHeight`. Return writes, Shift+Return
/// adds a line, Cmd+Return sends the queue with the words.
struct Composer: View {
    let model: AppModel
    @Environment(\.palette) private var palette

    var body: some View {
        if let target = model.composerTarget {
            VStack(alignment: .leading, spacing: 6) {
                targetLine(target)
                field(target)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Hairline(axis: .horizontal) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Composer")
        }
    }

    /// What the words do and where they go, the region chip, and the
    /// General toggle in the thread list.
    private func targetLine(_ target: ComposerTarget) -> some View {
        HStack(spacing: 6) {
            Image(systemName: target.glyph)
                .imageScale(.small)
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(target.label)
                    .fontWeight(.medium)
                    .foregroundStyle(target.answers ? palette[.question] : palette[.textPrimary])
                if let note = target.note {
                    Text("· \(note)")
                        .font(.subheadline)
                        .foregroundStyle(target.answers ? palette[.question] : palette[.textTertiary])
                }
            }
            .lineLimit(1)
            .accessibilityElement(children: .combine)
            if let region = model.composerRegion {
                RegionChip(model: model, region: region) { model.removeComposerRegion() }
            }
            Spacer(minLength: 4)
            if model.shown == nil {
                GeneralToggle(isOn: model.isComposerGeneral) { model.toggleComposerGeneral() }
                    .pressedByKeys(in: model) { model.toggleComposerGeneral() }
            }
        }
        .font(.callout.monospacedDigit())
        .foregroundStyle(target.answers ? palette[.question] : palette[.textSecondary])
        .frame(height: 22)
    }

    private func field(_ target: ComposerTarget) -> some View {
        ComposerField(
            text: Binding(get: { model.composerText }, set: { model.composerText = $0 }),
            placeholder: target.placeholder,
            keys: target.keys,
            answers: target.answers,
            focusRequests: model.composerFocusRequests,
            began: { model.composerBegan() },
            commit: { model.submitComposer() },
            cancel: {
                // Escape drops the region chip first; else the player gets the keys back.
                guard model.composerRegion != nil else { return false }
                model.removeComposerRegion()
                return true
            }
        )
        .accessibilityLabel(target.answers ? "\(target.label), goes at once" : target.label)
    }
}

/// The chip of the region that goes with the words, with its remove button.
private struct RegionChip: View {
    let model: AppModel
    let region: Region
    let remove: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "rectangle.dashed")
                .imageScale(.small)
                .accessibilityHidden(true)
            Text("Region")
                .font(.subheadline.weight(.semibold))
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .pressedByKeys(in: model, action: remove)
            .help("Remove the region")
            .accessibilityLabel("Remove the region")
        }
        .foregroundStyle(palette[.regionOutline])
        .padding(.leading, 6)
        .padding(.trailing, 2)
        .padding(.vertical, 1)
        .background(palette[.regionOutline].opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Region")
    }
}

/// The General toggle: the words go to General, not to the frame.
private struct GeneralToggle: View {
    let isOn: Bool
    let toggle: () -> Void
    @Environment(\.palette) private var palette
    @State private var isHovered = false

    private static let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)

    var body: some View {
        Button(action: toggle) {
            Label("General", systemImage: "globe")
                .font(.subheadline)
                .labelStyle(.titleAndIcon)
                .foregroundStyle(isOn ? palette[.accent] : palette[isHovered ? .textPrimary : .textSecondary])
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(fill, in: Self.shape)
                .overlay(Self.shape.strokeBorder(border, lineWidth: 1))
                .contentShape(Self.shape)
        }
        .buttonStyle(.borderless)
        .fixedSize()
        .onHover { isHovered = $0 }
        .animation(.smooth(duration: 0.12), value: isHovered)
        .help(isOn ? "Write at the playhead" : "Write in General, not at a moment")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// Off, a hairline outline that takes `controlHover` under the pointer;
    /// on, the accent tint, a shade stronger under the pointer.
    private var fill: Color {
        if isOn { return palette[.accent].opacity(isHovered ? 0.22 : 0.14) }
        return isHovered ? palette[.controlHover] : .clear
    }

    private var border: Color {
        isOn ? palette[.accent].opacity(0.4) : palette[.separator]
    }
}

/// The composer's field: the editor that grows with its words, its
/// placeholder, and the keys at its trailing edge, on the theme's `field`
/// with a hairline at rest and the system focus ring (`FocusRing`) while
/// it has the focus in the key window, as every message field (L42).
private struct ComposerField: View {
    @Binding var text: String
    let placeholder: String
    let keys: String
    let answers: Bool
    let focusRequests: Int
    let began: () -> Void
    let commit: () -> Void
    let cancel: () -> Bool
    @Environment(\.palette) private var palette
    @Environment(\.controlActiveState) private var activeState
    @State private var height = ComposerEditor.lineHeight
    @State private var isFocused = false

    private static let shape = RoundedRectangle(cornerRadius: ComposerEditor.corner, style: .continuous)

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ComposerEditor(
                text: $text, height: $height, focusRequests: focusRequests,
                focusChanged: { focused in
                    isFocused = focused
                    if focused { began() }
                },
                commit: commit, cancel: cancel
            )
            .frame(height: min(max(height, ComposerEditor.lineHeight), ComposerEditor.maxHeight))
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(palette[.textTertiary])
                        .lineLimit(1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            Text(keys)
                .font(.caption)
                .foregroundStyle(palette[.textTertiary])
                .fixedSize()
                .frame(height: ComposerEditor.lineHeight)
                .accessibilityHidden(true)
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .padding(.vertical, ComposerEditor.padding)
        .background(palette[.field], in: Self.shape)
        .overlay {
            Self.shape.strokeBorder(answers ? palette[.question].opacity(0.55) : palette[.separator], lineWidth: 1)
        }
        .overlay {
            if isFocused, activeState == .key {
                FocusRing(cornerRadius: ComposerEditor.corner)
            }
        }
    }
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
    /// The space above and below the words inside the field.
    static let padding: CGFloat = 7
    static let corner: CGFloat = 15

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
