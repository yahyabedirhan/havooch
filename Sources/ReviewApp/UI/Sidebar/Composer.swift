import AppKit
import ReviewCore
import SwiftUI

struct Composer: View {
    let model: WindowModel
    @Environment(\.palette) private var palette
    @Environment(\.controlActiveState) private var activeState
    @State private var height = ComposerEditor.lineHeight
    @State private var isFocused = false

    private static let corner: CGFloat = 10
    private static let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
    private static let minLines: CGFloat = 3

    static func sendTitle(_ count: Int) -> String {
        count > 1 ? "Send \(count)" : "Send"
    }

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

    private var focused: Bool { isFocused && activeState == .key && target != nil }

    private var border: Color {
        if target?.answers == true { return palette[.question].opacity(focused ? 0.7 : 0.4) }
        return focused ? palette[.accent].opacity(0.6) : palette[.separator]
    }

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

private struct DockBand: View {
    let model: WindowModel
    let answers: Bool
    let hasField: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 7) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
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

private struct ComposerEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    let focusRequests: Int
    let focusChanged: (Bool) -> Void
    let commit: () -> Void
    let cancel: () -> Bool

    static let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    static let lineHeight: CGFloat = ceil(NSLayoutManager().defaultLineHeight(for: font))
    static let inset = NSSize(width: 0, height: 0)
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
                if !parent.cancel() { textView.window?.makeFirstResponder(nil) }
            case nil: return false
            }
            return true
        }
    }
}
