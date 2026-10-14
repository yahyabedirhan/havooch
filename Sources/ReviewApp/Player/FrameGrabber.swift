import AVFoundation
import ReviewCore
import ReviewStore

enum FrameGrabber {
    nonisolated static func keyframe(
        of asset: AVAsset, at seconds: Double, duration: Double, frameDuration: Double
    ) async throws(AppRefusal) -> CGImage {
        let inside = min(max(seconds, 0), max(duration - frameDuration / 2, 0))
        var attempt = 1
        while true {
            let generator = AVAssetImageGenerator(asset: asset)
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            generator.appliesPreferredTrackTransform = true
            do {
                return try await generator.image(at: PlayerEngine.exact(inside)).image
            } catch where readsAgain(after: error, attempt: attempt) {
                try? await Task.sleep(for: .milliseconds(200) * attempt)
                attempt += 1
            } catch {
                throw AppRefusal("couldn't read the frame at \(seconds) s: \(error.localizedDescription)")
            }
        }
    }

    nonisolated static let readAttempts = 3

    nonisolated static func readsAgain(after error: any Error, attempt: Int) -> Bool {
        (error as? AVError)?.code == .decodeFailed && attempt < readAttempts
    }

    nonisolated static func crop(_ keyframe: CGImage, to region: Region) throws(AppRefusal) -> CGImage {
        let pixels = region.pixels(width: keyframe.width, height: keyframe.height)
        guard let crop = keyframe.cropping(to: CGRect(x: pixels.x, y: pixels.y, width: pixels.width, height: pixels.height)) else {
            throw AppRefusal("couldn't cut the region \(region.text) from the frame")
        }
        return crop
    }

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
