import Foundation
import ReviewWire

/// "Try the Demo" on the empty state and the home screen: the launch
/// video bundled in the app (`Contents/Resources/Demo/`, copied there by
/// `make bundle`), opened on
/// demo data in a folder under the user's temporary folder, so demo threads
/// never mix with the person's. The running app switches to that
/// folder in the same window (`AppModel.enterDemo`).
enum DemoRun {
    /// The demo video's file name, in `fixtures/launch/` and in the bundle.
    static let videoName = "havooch-demo.mp4"

    /// The bundled launch video, when this build has one: a bundle made by
    /// `make bundle` does, a bare `swift build` doesn't.
    static func video(in bundle: Bundle = .main) -> URL? {
        guard let video = bundle.resourceURL?.appendingPathComponent("Demo/\(videoName)", isDirectory: false),
              FileManager.default.fileExists(atPath: video.path)
        else { return nil }
        return video
    }

    /// The demo's support folder, under the user's temporary folder.
    static func folder(temporary: URL = FileManager.default.temporaryDirectory) -> URL {
        temporary.appendingPathComponent("\(AppIdentity.appName) Demo", isDirectory: true)
    }
}
