import Foundation
import ReviewWire

enum DemoRun {
    static let videoName = "havooch-demo.mp4"

    static func video(in bundle: Bundle = .main) -> URL? {
        guard let video = bundle.resourceURL?.appendingPathComponent("Demo/\(videoName)", isDirectory: false),
              FileManager.default.fileExists(atPath: video.path)
        else { return nil }
        return video
    }

    static func folder(temporary: URL = FileManager.default.temporaryDirectory) -> URL {
        temporary.appendingPathComponent("\(AppIdentity.appName) Demo", isDirectory: true)
    }
}
