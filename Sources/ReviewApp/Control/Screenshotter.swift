import AppKit
import ImageIO
import ReviewWire
import ScreenCaptureKit
import UniformTypeIdentifiers

/// What the control server asks for a `video-review screenshot`.
@MainActor
protocol Screenshotting: AnyObject {
    /// The app's window written as a PNG at `file`, in `appearance` when
    /// it's set (and back to the app's own afterwards).
    func capture(to file: URL, appearance: ControlRequest.Appearance?) async throws(AppRefusal)
}

/// Captures the app's own window through ScreenCaptureKit, limited to this
/// process's windows (`SCShareableContent.currentProcess`), which needs no
/// Screen Recording permission and never shows another app.
@MainActor
final class Screenshotter: Screenshotting {
    /// How long the window gets to redraw in a new appearance before it's
    /// captured.
    private static let settle = Duration.milliseconds(400)

    /// The capture before this one. Captures take turns: each one changes
    /// the app's appearance and puts it back.
    private var last: Task<Void, Never>?

    func capture(to file: URL, appearance: ControlRequest.Appearance?) async throws(AppRefusal) {
        let before = last
        let turn = Task { () -> AppRefusal? in
            await before?.value
            do throws(AppRefusal) {
                try await self.captureNow(to: file, appearance: appearance)
                return nil
            } catch {
                return error
            }
        }
        last = Task { _ = await turn.value }
        if let refusal = await turn.value { throw refusal }
    }

    private func captureNow(to file: URL, appearance: ControlRequest.Appearance?) async throws(AppRefusal) {
        guard let window = Self.appWindow else { throw AppRefusal("the app's window isn't on screen") }
        let previous = NSApp.appearance
        if let appearance {
            NSApp.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
        }
        defer { NSApp.appearance = previous }
        if appearance != nil { try? await Task.sleep(for: Self.settle) }
        let image = try await Self.captureOwnWindow(CGWindowID(window.windowNumber))
        try Self.write(image, to: file)
    }

    /// The player's window: the one titled window the app shows.
    private static var appWindow: NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.styleMask.contains(.titled) && !($0 is NSPanel) }
    }

    /// The window `windowID` names, captured from this process's shareable
    /// content only, at its display's scale.
    nonisolated private static func captureOwnWindow(_ windowID: CGWindowID) async throws(AppRefusal) -> CGImage {
        do {
            let content = try await SCShareableContent.currentProcess
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                throw AppRefusal("ScreenCaptureKit doesn't list the app's window; is it minimized?")
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let configuration = SCStreamConfiguration()
            let scale = CGFloat(filter.pointPixelScale)
            configuration.width = Int((filter.contentRect.width * scale).rounded())
            configuration.height = Int((filter.contentRect.height * scale).rounded())
            configuration.showsCursor = false
            configuration.ignoreShadowsSingleWindow = true
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch let refusal as AppRefusal {
            throw refusal
        } catch {
            throw AppRefusal("couldn't capture the window: \(error.localizedDescription)")
        }
    }

    /// `image` written as a PNG at `file`, replacing what's there; its
    /// folder is made when it's missing.
    private static func write(_ image: CGImage, to file: URL) throws(AppRefusal) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw AppRefusal("couldn't write \(file.path): its folder can't be written")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw AppRefusal("couldn't write \(file.path)") }
    }
}
