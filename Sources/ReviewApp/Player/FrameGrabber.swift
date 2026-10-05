import AVFoundation
import ReviewCore
import ReviewStore

/// A message's pictures: the keyframe, which is the frame of the video at
/// its thread's time, and the crop of its region. Both are read from the
/// asset and not from the window. A message from the UI and one from the
/// CLI therefore get the same pixels, at the video's own size, whatever the
/// window's size, and with no screen permission.
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
            return try await generator.image(at: PlayerEngine.exact(inside)).image
        } catch {
            throw AppRefusal("couldn't read the frame at \(seconds) s: \(error.localizedDescription)")
        }
    }

    /// The part of `keyframe` inside `region`: the keyframe's own pixels.
    nonisolated static func crop(_ keyframe: CGImage, to region: Region) throws(AppRefusal) -> CGImage {
        let pixels = region.pixels(width: keyframe.width, height: keyframe.height)
        guard let crop = keyframe.cropping(to: CGRect(x: pixels.x, y: pixels.y, width: pixels.width, height: pixels.height)) else {
            throw AppRefusal("couldn't cut the region \(region.text) from the frame")
        }
        return crop
    }

    /// The keyframe written as a PNG at `file` when it's given, and the
    /// crop of `region` at `cropFile` when both are given, off the main
    /// actor. When either can't be written, neither is left behind.
    @concurrent
    nonisolated static func writeImages(
        of asset: AVAsset, at seconds: Double, duration: Double, frameDuration: Double,
        keyframe file: URL?, region: Region?, crop cropFile: URL?
    ) async throws(AppRefusal) {
        let image = try await keyframe(of: asset, at: seconds, duration: duration, frameDuration: frameDuration)
        do {
            if let file { try ImageFiles.write(image, to: file) }
            if let region, let cropFile { try ImageFiles.write(try crop(image, to: region), to: cropFile) }
        } catch {
            if let file { ImageFiles.remove(file) }
            if let cropFile { ImageFiles.remove(cropFile) }
            throw (error as? AppRefusal) ?? AppRefusal((error as? ImageFiles.Failure)?.reason ?? "\(error)")
        }
    }
}
