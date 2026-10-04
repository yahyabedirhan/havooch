import AVFoundation
import ReviewStore

/// A comment's keyframe: the frame of the video at the comment's time, read
/// from the asset and not from the window. A comment from the UI and one
/// from the CLI therefore get the same pixels, at the video's own size,
/// whatever the window's size, and with no screen permission.
enum FrameGrabber {
    /// The frame of `asset` on screen at `seconds`.
    nonisolated static func keyframe(
        of asset: AVAsset, at seconds: Double, duration: Double, frameDuration: Double
    ) async throws(AppRefusal) -> CGImage {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.appliesPreferredTrackTransform = true
        // The video's end is past its last frame: ask inside that frame.
        let inside = min(max(seconds, 0), max(duration - frameDuration / 2, 0))
        do {
            return try await generator.image(at: CMTime(seconds: inside, preferredTimescale: timescale)).image
        } catch {
            throw AppRefusal("couldn't read the frame at \(seconds) s: \(error.localizedDescription)")
        }
    }

    /// The keyframe written as a PNG at `file`, off the main actor.
    nonisolated static func writeKeyframe(
        of asset: AVAsset, at seconds: Double, duration: Double, frameDuration: Double, to file: URL
    ) async throws(AppRefusal) {
        let image = try await keyframe(of: asset, at: seconds, duration: duration, frameDuration: frameDuration)
        do throws(ImageFiles.Failure) {
            try ImageFiles.write(image, to: file)
        } catch {
            throw AppRefusal(error.reason)
        }
    }

    /// Fine enough to hold a millisecond exactly.
    private static let timescale: CMTimeScale = 60_000
}
