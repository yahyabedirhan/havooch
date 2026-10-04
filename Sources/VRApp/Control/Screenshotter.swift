import AppKit
import ScreenCaptureKit
import VRWire

/// How a screenshot was made: the window captured from the screen as drawn,
/// its contents rendered by the app instead (with why capturing didn't
/// work), or nothing written at all.
enum ScreenshotOutcome: Equatable {
    case captured
    case rendered(why: String)
    case failed(why: String)
}

/// Captures the app's window through ScreenCaptureKit, limited to this
/// process's own windows (`SCShareableContent.currentProcess`), which needs
/// no Screen Recording permission. When that fails, it renders the window's
/// views itself; the video's frame, which the window server draws, is then
/// missing, and the outcome says so.
@MainActor
final class Screenshotter {
    /// The window to capture, or nil when there's none on screen.
    private let window: @MainActor () -> NSWindow?
    /// One capture at a time: two would fight over the app's appearance.
    private var isCapturing = false
    /// How long the window gets to redraw in a new appearance before it's
    /// captured.
    private static let settle = Duration.milliseconds(350)

    init(window: @escaping @MainActor () -> NSWindow?) {
        self.window = window
    }

    /// The window written as a PNG at `file`, in `appearance` when it's set
    /// (and back to the app's own afterwards).
    func capture(to file: URL, appearance: ControlRequest.Appearance?) async -> ScreenshotOutcome {
        guard !isCapturing else { return .failed(why: "another screenshot is being taken; try again") }
        isCapturing = true
        defer { isCapturing = false }
        guard let window = window() else { return .failed(why: "the app has no window on screen") }

        let previous = NSApp.appearance
        if let appearance {
            NSApp.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
        }
        defer { NSApp.appearance = previous }
        try? await Task.sleep(for: Self.settle)

        let image: CGImage
        var captureFailure: String?
        do throws(ScreenshotFailure) {
            image = try await Self.captureOwnWindow(CGWindowID(window.windowNumber))
        } catch {
            guard let drawn = Self.render(window) else {
                return .failed(why: "couldn't capture the window (\(error.why)) or render it")
            }
            image = drawn
            captureFailure = error.why
        }
        do throws(PNGFile.Failure) {
            try PNGFile.write(image, to: file)
        } catch {
            return .failed(why: error.localizedDescription)
        }
        return captureFailure.map { .rendered(why: $0) } ?? .captured
    }

    /// The window `windowID` names, captured by ScreenCaptureKit from this
    /// process's shareable content only, at its display's scale.
    nonisolated private static func captureOwnWindow(_ windowID: CGWindowID) async throws(ScreenshotFailure) -> CGImage {
        do {
            let content = try await SCShareableContent.currentProcess
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                throw ScreenshotFailure("ScreenCaptureKit doesn't list the window among this app's")
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let configuration = SCStreamConfiguration()
            let scale = CGFloat(filter.pointPixelScale)
            configuration.width = Int((filter.contentRect.width * scale).rounded())
            configuration.height = Int((filter.contentRect.height * scale).rounded())
            configuration.showsCursor = false
            configuration.ignoreShadowsSingleWindow = true
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch let failure as ScreenshotFailure {
            throw failure
        } catch {
            throw ScreenshotFailure("ScreenCaptureKit: \(error.localizedDescription)")
        }
    }

    /// The window's views as AppKit draws them, title bar included, at the
    /// window's scale.
    private static func render(_ window: NSWindow) -> CGImage? {
        guard let view = window.contentView?.superview ?? window.contentView else { return nil }
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        view.cacheDisplay(in: bounds, to: bitmap)
        return bitmap.cgImage
    }
}

/// Why a screenshot step didn't work, as one line.
struct ScreenshotFailure: Error, Equatable {
    var why: String

    init(_ why: String) {
        self.why = why
    }
}
