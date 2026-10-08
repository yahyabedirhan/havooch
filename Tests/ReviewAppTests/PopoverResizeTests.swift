import AppKit
import Foundation
@testable import ReviewApp
import ReviewCore
import ReviewWire
import SwiftUI
import Testing

/// A thread's popover resized by the pointer, in the real view: the
/// stage's popover layer hosted in a window that is never seen (fully
/// transparent, behind every other window and far off every screen), with
/// mouse events sent straight to it. Nothing moves the pointer or takes
/// the focus.
@Suite("A thread's popover resizes from its edges and corners by the drag alone", .serialized)
struct PopoverResizeTests {
    let support = FileManager.default.temporaryDirectory
        .appendingPathComponent("havooch-tests-\(UUID().uuidString)", isDirectory: true)
    /// The stage the popover layer is laid out on.
    static let stage = CGSize(width: 1000, height: 600)

    private func cleanUp() {
        try? FileManager.default.removeItem(at: support)
    }

    /// The fixture video with one thread at 12.5 s, its popover open on
    /// it, at `frame` when the thread keeps one.
    private func model(frame: PopoverFrame?) async throws -> WindowModel {
        let model = AppModel(environment: [SupportFolder.overrideVariable: support.path]).makeWindow()
        try await model.open(MessageTests.fixture)
        _ = try await model.addMessage(text: "Here", at: 12.5)
        _ = try await model.openThread("1", frame: frame)
        return model
    }

    /// The popover layer for `model` in a window no one sees.
    private func window(for model: WindowModel) -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: Self.stage), styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: StagePopoverLayer(model: model).frame(width: Self.stage.width, height: Self.stage.height)
        )
        window.alphaValue = 0
        window.setFrameOrigin(CGPoint(x: -20000, y: -20000))
        // Ordered in, behind everything, so its views take mouse events.
        window.orderBack(nil)
        settle()
        return window
    }

    private func settle(_ seconds: Double = 0.3) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// A press at `point` on the stage (from its top-left corner), moved by
    /// `by`, then released.
    private func drag(at point: CGPoint, by: CGSize, in window: NSWindow) {
        let from = CGPoint(x: point.x, y: Self.stage.height - point.y)
        let to = CGPoint(x: from.x + by.width, y: from.y - by.height)
        for (type, location) in [(NSEvent.EventType.leftMouseDown, from), (.leftMouseDragged, to), (.leftMouseUp, to)] {
            let event = NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            )
            if let event { window.sendEvent(event) }
            settle(0.1)
        }
    }

    /// The popover's kept frame on the stage, in points.
    private func kept(_ model: WindowModel) -> CGRect? {
        model.draftThread?.popoverFrame.map {
            CGRect(x: $0.x * Self.stage.width, y: $0.y * Self.stage.height, width: $0.w * Self.stage.width, height: $0.h * Self.stage.height)
        }
    }

    /// Where a moment's popover at its own place has its leading edge.
    private func naturalLeading(_ model: WindowModel) -> CGFloat {
        CommentPopover.placement(
            playhead: CommentPopover.playhead(fraction: 12.5 / model.engine.duration, track: .zero, stage: .zero),
            stageWidth: Self.stage.width
        ).leading
    }

    /// Just inside the lower right corner of a moment's popover at its own
    /// place: it stands 4 pt above the stage's foot, on its notch.
    private func naturalCorner(_ leading: CGFloat) -> CGPoint {
        CGPoint(x: leading + CommentPopover.width - 2, y: Self.stage.height - 4 - CommentPopover.notchHeight - 2)
    }

    @Test(
        "a small drag on the corner of a popover at its own place changes its size by the drag, in either direction",
        arguments: [CGFloat(3), -3]
    )
    func smallDrag(step: CGFloat) async throws {
        defer { cleanUp() }
        let model = try await model(frame: nil)
        let window = window(for: model)
        defer { window.close() }
        let leading = naturalLeading(model)
        drag(at: naturalCorner(leading), by: CGSize(width: step, height: step), in: window)
        let rect = try #require(kept(model))
        // A step in grows the popover by the step; a step out stops at the minimum size it opened at.
        #expect(abs(rect.width - max(CommentPopover.width + step, ThreadPopover.minimumSize.width)) < 0.5)
        #expect(abs(rect.minX - leading) < 0.5)
        #expect(rect.height < 400)
    }

    @Test("a click on the corner, without a drag, changes nothing")
    func click() async throws {
        defer { cleanUp() }
        let model = try await model(frame: nil)
        let window = window(for: model)
        defer { window.close() }
        drag(at: naturalCorner(naturalLeading(model)), by: .zero, in: window)
        #expect(model.draftThread?.popoverFrame == nil)
    }

    /// The popover kept at 300, 120, 400 by 360 on the stage.
    static let keptFrame = PopoverFrame(x: 0.3, y: 0.2, w: 0.4, h: 0.6)

    @Test(
        "a drag on an edge moves only that edge, a drag on a corner its two edges, and the header still moves the whole popover",
        arguments: [
            // The leading edge, at its middle.
            (CGPoint(x: 301, y: 300), CGSize(width: -20, height: 15), CGRect(x: 280, y: 120, width: 420, height: 360)),
            // The top edge.
            (CGPoint(x: 500, y: 121), CGSize(width: 15, height: -30), CGRect(x: 300, y: 90, width: 400, height: 390)),
            // The trailing edge.
            (CGPoint(x: 699, y: 300), CGSize(width: 25, height: -10), CGRect(x: 300, y: 120, width: 425, height: 360)),
            // The bottom edge.
            (CGPoint(x: 500, y: 479), CGSize(width: -10, height: 20), CGRect(x: 300, y: 120, width: 400, height: 380)),
            // The top leading corner.
            (CGPoint(x: 302, y: 122), CGSize(width: 30, height: 30), CGRect(x: 330, y: 150, width: 370, height: 330)),
            // The bottom trailing corner, past the minimum size.
            (CGPoint(x: 698, y: 478), CGSize(width: -300, height: -300), CGRect(x: 300, y: 120, width: 340, height: 320)),
            // The header: the whole popover moves, at its size.
            (CGPoint(x: 400, y: 135), CGSize(width: 40, height: 20), CGRect(x: 340, y: 140, width: 400, height: 360)),
        ]
    )
    func edges(at point: CGPoint, by translation: CGSize, expected: CGRect) async throws {
        defer { cleanUp() }
        let model = try await model(frame: Self.keptFrame)
        let window = window(for: model)
        defer { window.close() }
        drag(at: point, by: translation, in: window)
        let rect = try #require(kept(model))
        #expect(abs(rect.minX - expected.minX) < 0.5 && abs(rect.minY - expected.minY) < 0.5)
        #expect(abs(rect.width - expected.width) < 0.5 && abs(rect.height - expected.height) < 0.5)
    }

    /// The size `popover` lays itself out at, in a window no one sees.
    private func ownSize(of popover: CommentPopover) -> CGSize {
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: Self.stage), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: popover)
        window.contentView = host
        window.alphaValue = 0
        window.setFrameOrigin(CGPoint(x: -20000, y: -20000))
        window.orderBack(nil)
        settle()
        return host.fittingSize
    }

    @Test("each popover opens no smaller than its minimum size: a thread's with one short message, and a new message's")
    func ownSizeIsNoSmallerThanTheMinimum() async throws {
        defer { cleanUp() }
        let model = try await model(frame: nil)
        let thread = try #require(model.draftThread)
        let draft = try #require(model.draft)
        let threadSize = ownSize(of: CommentPopover(model: model, draft: draft, notch: nil, thread: thread))
        #expect(threadSize.width >= ThreadPopover.minimumSize.width - 0.5)
        #expect(threadSize.height >= ThreadPopover.minimumSize.height - 0.5)

        _ = model.escape()
        try await model.seek(to: 18)
        model.startDraft()
        let fresh = try #require(model.draft)
        #expect(model.draftThread == nil)
        let messageSize = ownSize(of: CommentPopover(model: model, draft: fresh, notch: 100))
        let box = CGSize(width: messageSize.width, height: messageSize.height - CommentPopover.notchHeight)
        #expect(box.width >= CommentPopover.rules.minimum.width - 0.5)
        #expect(box.height >= CommentPopover.rules.minimum.height - 0.5)
        // It opens at its minimum, with a roomy field.
        #expect(abs(box.height - CommentPopover.rules.minimum.height) < 4, "\(box)")
    }
}
