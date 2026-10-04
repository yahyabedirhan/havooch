import AVFoundation
import AppKit
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers
import VRWire

/// How a screenshot was made: the window captured from the screen as
/// drawn, rendered by the app instead (with why capturing didn't work), or
/// not written at all.
enum ScreenshotOutcome: Equatable {
    case captured
    case rendered(why: String)
    case failed(why: String)
}

/// Writes the app's own window as a PNG. It captures through
/// ScreenCaptureKit limited to this process's windows
/// (`SCShareableContent.currentProcess`), which needs no Screen Recording
/// permission. When that fails, it draws the window's view itself, with the
/// video's current frame in the player's place, since a player layer doesn't
/// draw into a bitmap.
@MainActor
final class Screenshotter {
    private let model: AppModel
    /// How long the window gets to redraw in a new appearance before it's
    /// captured.
    private static let settle = Duration.milliseconds(350)

    init(model: AppModel) {
        self.model = model
    }

    /// The window written at `file`, in `appearance` when it's set (and
    /// back to the app's own afterwards), as the Mac shows it otherwise.
    func capture(to file: URL, appearance: ControlRequest.Appearance?) async -> ScreenshotOutcome {
        guard let window = model.window, window.isVisible else {
            return .failed(why: "the app has no window on screen to capture")
        }
        let previous = NSApp.appearance
        if let appearance {
            NSApp.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
            try? await Task.sleep(for: Self.settle)
        }
        defer { NSApp.appearance = previous }

        do throws(ScreenshotFailure) {
            let image: CGImage
            var captureFailure: String?
            do throws(ScreenshotFailure) {
                image = try await Self.captureOwnWindow(CGWindowID(window.windowNumber))
            } catch {
                captureFailure = error.why
                guard let drawn = await render(window) else {
                    throw ScreenshotFailure("couldn't capture the window (\(error.why)) or render it")
                }
                image = drawn
            }
            try Self.write(image, to: file)
            return captureFailure.map { .rendered(why: $0) } ?? .captured
        } catch {
            return .failed(why: error.why)
        }
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

    /// The window's content drawn by AppKit, in the window's appearance,
    /// with the video's frame at the playhead drawn where the player shows
    /// it. Only what the app itself draws: the title bar's place stays blank.
    private func render(_ window: NSWindow) async -> CGImage? {
        guard let view = window.contentView, view.bounds.width > 0, view.bounds.height > 0 else { return nil }
        let frame = await currentFrame()
        let scale = window.backingScaleFactor
        let width = Int((view.bounds.width * scale).rounded()), height = Int((view.bounds.height * scale).rounded())
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        var image: CGImage?
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let drawn = bitmap.cgImage,
                  let context = CGContext(
                      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else { return }
            let all = CGRect(x: 0, y: 0, width: width, height: height)
            context.setFillColor(NSColor.windowBackgroundColor.cgColor)
            context.fill(all)
            context.draw(drawn, in: all)
            if let frame, let surface = Self.playerView(in: view) {
                // Where the player shows the frame, in the content view's
                // points, then in the bitmap's pixels with its origin at the bottom.
                var rect = surface.convert(surface.playerLayer.videoRect, to: view)
                if view.isFlipped { rect.origin.y = view.bounds.height - rect.maxY }
                context.draw(frame, in: rect.applying(CGAffineTransform(scaleX: scale, y: scale)))
            }
            image = context.makeImage()
        }
        return image
    }

    /// The video's frame at the playhead, read from the file.
    private func currentFrame() async -> CGImage? {
        guard let video = model.player.video else { return nil }
        return try? await FrameGrabber.frame(of: video.url, at: model.player.time)
    }

    private static func playerView(in view: NSView) -> PlayerLayerView? {
        if let surface = view as? PlayerLayerView { return surface }
        for child in view.subviews {
            if let surface = playerView(in: child) { return surface }
        }
        return nil
    }

    /// `image` written as a PNG at `file`, replacing what's there.
    private static func write(_ image: CGImage, to file: URL) throws(ScreenshotFailure) {
        guard let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ScreenshotFailure("couldn't write \(file.path): its folder doesn't exist or can't be written")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ScreenshotFailure("couldn't write \(file.path)")
        }
    }
}

/// Why a screenshot step didn't work, as one line.
struct ScreenshotFailure: Error, Equatable {
    var why: String

    init(_ why: String) {
        self.why = why
    }
}
