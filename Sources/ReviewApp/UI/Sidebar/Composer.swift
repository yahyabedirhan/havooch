import AppKit
import ReviewCore
import SwiftUI

/// The dock at the sidebar's foot (L41, L68): the one composer and the
/// one Send, in the thread list and in a thread view alike.
///
/// Above the card, where the words go: in the thread list one switch,
/// "At 0:12 | General" (`PlaceSwitch`); in a thread view the thread alone
/// ("#3"); while answering "Answer #3, goes at once" in the question
/// colour. The card holds the writing: the field that grows with the
/// words, three lines tall at rest, and the region chip under them. Its foot
/// is a band on `well`: the presence pill, which opens the Connect view,
/// and the agent's newest activity on the left, and on the right the one
/// `SplitButton`, "Send 3" with Queue and Send in its menu, or "Answer"
/// with Discard, after the queued count.
///
/// No focus ring: the card's hairline turns a soft accent while the field
/// has the focus in the key window. Return queues, Shift+Return adds a
/// line, Cmd+Return sends the queue with the words. While the Connect view
/// shows, or with no video, the card holds the band alone: nothing is
/// written there.
struct Composer: View {
    let model: WindowModel
    @Environment(\.palette) private var palette
    @Environment(\.controlActiveState) private var activeState
    @State private var height = ComposerEditor.lineHeight
    @State private var isFocused = false

    private static let corner: CGFloat = 10
    private static let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
    /// The field's height at rest, in lines.
    private static let minLines: CGFloat = 3

    /// The Send button's title for `count` messages a send would deliver:
    /// "Send" for one or none, else "Send 3".
    static func sendTitle(_ count: Int) -> String {
        count > 1 ? "Send \(count)" : "Send"
    }

    /// Where the words go, when the person writes: none in the Connect view.
    private var target: ComposerTarget? {
        model.connect == nil ? model.composerTarget : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let target {
                header(target)
            }
            VStack(spacing: 0) {
                if let target {
                    editor(target)
                        .padding(.horizontal, 11)
                        .padding(.top, 9)
                        .padding(.bottom, model.composerRegion == nil ? 9 : 4)
                    if model.composerRegion != nil {
                        HStack {
                            RegionChip(model: model) { model.removeComposerRegion() }
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 7)
                    }
                }
                DockBand(model: model, answers: target?.answers == true, hasField: target != nil)
            }
            .background(palette[.field])
            .clipShape(Self.shape)
            .overlay { Self.shape.strokeBorder(border, lineWidth: 1) }
            .animation(.smooth(duration: 0.15), value: focused)
            // The tour's write step rings the dock (H4).
            .coachRing(model.tourRings(.composer), radius: Self.corner)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(palette[.window])
        .overlay(alignment: .top) { Hairline(axis: .horizontal) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Composer")
    }

    /// The field has the focus in the key window: a window behind another
    /// draws no focus look.
    private var focused: Bool { isFocused && activeState == .key && target != nil }

    /// The card's hairline: `separator` at rest, a soft accent with the
    /// focus; for an answer, the question colour, stronger with the focus.
    private var border: Color {
        if target?.answers == true { return palette[.question].opacity(focused ? 0.7 : 0.4) }
        return focused ? palette[.accent].opacity(0.6) : palette[.separator]
    }

    /// The switch in the thread list; the target alone in a thread view
    /// and while answering.
    @ViewBuilder
    private func header(_ target: ComposerTarget) -> some View {
        if model.shown == nil, !target.answers {
            PlaceSwitch(model: model)
        } else {
            TargetLabel(target: target)
                .padding(.leading, 4)
                .frame(height: 22)
        }
    }

    private func editor(_ target: ComposerTarget) -> some View {
        let rest = ComposerEditor.lineHeight * Self.minLines + ComposerEditor.inset.height * 2
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
    }
}

/// One compact switch in the thread list: write at the playhead's moment,
/// or in General. The chosen half is a raised capsule in `field` on the
/// switch's `well`.
private struct PlaceSwitch: View {
    let model: WindowModel
    @Environment(\.palette) private var palette

    var body: some View {
        let moment = ComposerTarget.atMoment(model.engine.frameTime(of: model.engine.time))
        HStack(spacing: 0) {
            segment(moment, glyph: "plus.bubble", on: !model.isComposerGeneral, help: "Write at the playhead") {
                choose(general: false)
            }
            segment("General", glyph: "globe", on: model.isComposerGeneral, help: "Write in General, about the whole video") {
                choose(general: true)
            }
        }
        .padding(2)
        .background(palette[.well], in: Capsule())
        .overlay { Capsule().strokeBorder(palette[.separator], lineWidth: 0.5) }
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Where the words go")
    }

    private func choose(general: Bool) {
        if general != model.isComposerGeneral { model.toggleComposerGeneral() }
    }

    private func segment(_ title: String, glyph: String, on: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: glyph)
                    .imageScale(.small)
                Text(title)
                    .monospacedDigit()
            }
            .font(.subheadline.weight(on ? .medium : .regular))
            .foregroundStyle(on ? palette[.textPrimary] : palette[.textTertiary])
            .padding(.horizontal, 9)
            .frame(height: 20)
            .background {
                if on {
                    Capsule()
                        .fill(palette[.field])
                        .shadow(color: palette[.shadow].opacity(0.35), radius: 1, y: 0.5)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pressedByKeys(in: model, action: action)
        .help(help)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Where the words go, as a quiet label: "#3", "General thread", or
/// "Answer #3, goes at once" in the question colour.
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
                .truncationMode(.tail)
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

/// The band at the card's foot, on `well`: whether an agent listens and
/// what it does now (its newest activity) on the left; on the right the
/// queued count while an answer takes Send's place, and the dock's one
/// split button. A click on the presence pill opens the Connect view, and
/// goes back when it shows (G1). Sending is safe either way: with no agent
/// the send waits for the next one, and the Connect view opens to say so
/// (G8).
private struct DockBand: View {
    let model: WindowModel
    /// The field's words answer an open question.
    let answers: Bool
    /// The card has a field above the band, which a hairline separates.
    let hasField: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 7) {
            // Each second: an agent that stops answering turns absent with no event.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                // The window's own listener; a window with no video has none.
                let outbox = model.listener?.outbox ?? Outbox()
                let presence = outbox.presence(at: context.date)
                let pill = PresencePill.of(model.listenerPhase(at: context.date), presence: presence, pendingSends: outbox.pending.count)
                HStack(spacing: 7) {
                    Button {
                        model.toggleConnect(.pill)
                    } label: {
                        PresenceChip(presence: presence, pill: pill, isOpen: model.connect != nil)
                    }
                    .buttonStyle(.plain)
                    .pressedByKeys(in: model) { model.toggleConnect(.pill) }
                    // The newest activity of any thread, with no glyph: the chip pulses beside it.
                    if let activity = model.listener?.activities(at: context.date).first {
                        Text(activity.text)
                            .font(.subheadline)
                            .foregroundStyle(palette[.textSecondary])
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(activity.text)
                            .accessibilityLabel(ActivityLine.voice(agent: model.agentName, text: activity.text))
                    }
                }
            }
            // The pill and the activity take the width the button leaves,
            // so the activity truncates only when there is no room.
            .frame(maxWidth: .infinity, alignment: .leading)
            if answers, model.queuedCount > 0 {
                Text("\(model.queuedCount) queued")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(palette[.textTertiary])
                    .lineLimit(1)
                    .fixedSize()
            }
            DockSend(model: model, answers: answers)
                .coachRing(model.tourRings(.send), radius: SplitButton<EmptyView>.corner)
        }
        .padding(.horizontal, 6)
        .frame(height: 34)
        .frame(maxWidth: .infinity)
        .background(palette[.well])
        .overlay(alignment: .top) {
            if hasField { Hairline(axis: .horizontal) }
        }
    }
}

/// The dock's one Send: Cmd+Return's send with the words, its title
/// counting what a send delivers ("Send 3"), with Queue and Send in its
/// menu. An answer reads "Answer" on the same split button, with Discard
/// in its menu: it goes at once, as Return takes it.
private struct DockSend: View {
    let model: WindowModel
    let answers: Bool

    var body: some View {
        if answers {
            SplitButton("Answer", help: "Answer at once (↩)", isEnabled: hasWords, action: { model.submitComposer() }) {
                Button("Discard") { model.composerText = "" }
            }
            .pressedByKeys(in: model)
        } else {
            SplitButton(
                Composer.sendTitle(model.sendCount),
                help: model.canSend ? "Send the queue to your agent at once (⌘↩). Return queues the message." : "Nothing to send",
                isEnabled: model.canSend,
                action: { model.send() }
            ) {
                Button("Queue  ↩") { model.submitComposer() }
                    .disabled(!hasWords || model.composerTarget == nil || model.connect != nil)
                Button("Send  ⌘↩") { model.send() }
            }
            .pressedByKeys(in: model)
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

    /// The field's font, the system font at its regular size.
    static let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    /// One line of `font`, as the text view lays it out.
    static let lineHeight: CGFloat = ceil(NSLayoutManager().defaultLineHeight(for: font))
    /// The space between the text view's edge and its words, above and below.
    static let inset = NSSize(width: 0, height: 0)
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
        view.textContainerInset = Self.inset
        view.font = Self.font
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
