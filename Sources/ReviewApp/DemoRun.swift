import AppKit
import Foundation
import ReviewWire

/// "Try the demo" on the empty screen: the sample video bundled in the app
/// (`Contents/Resources/Demo/`, copied there by `make bundle`), opened on
/// demo data in a folder under the user's temporary folder, so demo threads
/// never mix with the person's (L17).
///
/// A run on the person's data starts a new copy of the app on the demo
/// folder, with the video to open, and quits; the CLI follows it through the
/// demo pointer, as after `app open --demo`. A demo run opens the video
/// itself.
enum DemoRun {
    /// The variable that names a video for the app to open at launch. Only
    /// a demo copy's launch sets it; any other launch opens no video.
    static let openVariable = "HAVOOCH_OPEN_VIDEO"

    /// The bundled sample video, when this build has one: a bundle made by
    /// `make bundle` does, a bare `swift build` doesn't.
    static func video(in bundle: Bundle = .main) -> URL? {
        guard let video = bundle.resourceURL?.appendingPathComponent("Demo/sample.mp4", isDirectory: false),
              FileManager.default.fileExists(atPath: video.path)
        else { return nil }
        return video
    }

    /// The demo's support folder, under the user's temporary folder.
    static func folder(temporary: URL = FileManager.default.temporaryDirectory) -> URL {
        temporary.appendingPathComponent("\(AppIdentity.appName) Demo", isDirectory: true)
    }

    /// The environment a demo copy of the app starts with.
    static func environment(folder: URL, video: URL) -> [String: String] {
        [SupportFolder.overrideVariable: folder.path, openVariable: video.path]
    }

    /// Starts a copy of this app on the demo folder, opening `video`, and
    /// calls `started` with nil once it runs, or with why it didn't.
    static func launch(video: URL, normalSupport: URL, started: @escaping @MainActor (String?) -> Void) {
        let demo = folder()
        do {
            try FileManager.default.createDirectory(at: demo, withIntermediateDirectories: true)
            // So `havooch` reaches the demo copy, as after `app open --demo`.
            try DemoPointer.record(demo, in: normalSupport)
        } catch {
            started("couldn't make the demo folder \(demo.path): \(error.localizedDescription)")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.addsToRecentItems = false
        configuration.environment = environment(folder: demo, video: video)
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            let reason = error.map(\.localizedDescription)
            Task { @MainActor in started(reason) }
        }
    }
}
