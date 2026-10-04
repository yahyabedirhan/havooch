import AVFoundation
import Foundation
import VRReview
import VRStore

/// A video file read for opening: what a review says about it, and what the
/// player's controls need.
struct VideoFile: Equatable, Sendable {
    var url: URL
    var info: VideoInfo
    /// The video track's nominal frame rate, for stepping by frames.
    var frameRate: Double
    /// The frame's size as shown, with the track's transform applied.
    var size: CGSize

    /// Reads the file at `url`: refused when there's no file, when AVPlayer
    /// can't play it, or when it has no picture.
    static func read(_ url: URL) async throws(ModelRefusal) -> VideoFile {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), !isFolder.boolValue else {
            throw ModelRefusal("no file at \(url.path)")
        }
        let name = url.lastPathComponent
        let asset = AVURLAsset(url: url)
        do {
            let (playable, duration) = try await asset.load(.isPlayable, .duration)
            guard playable else {
                throw ModelRefusal("\(name) isn't a video the player can play")
            }
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                throw ModelRefusal("\(name) has no video track")
            }
            let (frameRate, naturalSize, transform) = try await track.load(.nominalFrameRate, .naturalSize, .preferredTransform)
            let shown = CGRect(origin: .zero, size: naturalSize).applying(transform)
            return VideoFile(
                url: url,
                info: VideoInfo(
                    path: url.path,
                    contentHash: try ContentHash.of(url),
                    duration: TimeText.rounded(duration.seconds),
                    title: url.deletingPathExtension().lastPathComponent
                ),
                frameRate: Double(frameRate),
                size: CGSize(width: abs(shown.width), height: abs(shown.height))
            )
        } catch let refusal as ModelRefusal {
            throw refusal
        } catch {
            throw ModelRefusal("\(name) isn't a video the player can play: \(error.localizedDescription)")
        }
    }
}
