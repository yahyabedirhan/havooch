import AVFoundation
import ReviewCore
import ReviewStore

/// A comment's pictures: the keyframe, which is the frame of the video at
/// the comment's time, and the crop of its region. Both are read from the
/// asset and not from the window. A comment from the UI and one from the
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

    /// The keyframe written as a PNG at `file`, and the crop of `region`
    /// at `cropFile` when the comment has one, off the main actor. When
    /// either can't be written, neither is left behind.
    @concurrent
    nonisolated static func writeImages(
        of asset: AVAsset, at seconds: Double, duration: Double, frameDuration: Double,
        keyframe file: URL, region: Region?, crop cropFile: URL
    ) async throws(AppRefusal) {
        let image = try await keyframe(of: asset, at: seconds, duration: duration, frameDuration: frameDuration)
        do {
            try ImageFiles.write(image, to: file)
            if let region { try ImageFiles.write(try crop(image, to: region), to: cropFile) }
        } catch {
            ImageFiles.remove(file)
            ImageFiles.remove(cropFile)
            throw (error as? AppRefusal) ?? AppRefusal((error as? ImageFiles.Failure)?.reason ?? "\(error)")
        }
    }
}
