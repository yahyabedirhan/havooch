import AppKit
import Observation
import ReviewWire
import UniformTypeIdentifiers

/// The orchestrator: which video is open, and every action a person or an
/// operator can take. The UI and the control server call the same methods,
/// so a click and its CLI command are one code path.
@MainActor
@Observable
final class AppModel: AppControlling {
    /// The video that's open.
    struct OpenVideo: Equatable {
        var url: URL
        /// The file's name without its extension.
        var title: String
    }

    let engine = PlayerEngine()
    /// Where this run keeps its data: the person's own, or a demo's.
    let support: URL
    /// Whether this run is on demo data (`app open --demo`).
    let isDemo: Bool
    private(set) var video: OpenVideo?
    /// Whether the rail is shown beside the stage.
    var isRailVisible = true
    /// Why the last thing the person asked for didn't work, until they
    /// dismiss it.
    var problem: String?

    /// The files the Open panel offers: what the spec names.
    static let videoTypes: [UTType] = [.mpeg4Movie, .quickTimeMovie, UTType("com.apple.m4v-video")].compactMap(\.self)

    init(environment: [String: String]) {
        support = SupportFolder.app(environment: environment)
        isDemo = SupportFolder.moved(environment: environment) != nil
    }

    // MARK: - Actions, for the person and the operator alike

    func open(_ url: URL) async throws(AppRefusal) {
        let url = url.standardizedFileURL
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), !isFolder.boolValue else {
            throw AppRefusal("no video file at \(url.path)")
        }
        try await engine.load(url)
        video = OpenVideo(url: url, title: url.deletingPathExtension().lastPathComponent)
    }

    func play() throws(AppRefusal) {
        try needVideo()
        engine.play()
    }

    func pause() throws(AppRefusal) {
        try needVideo()
        engine.pause()
    }

    func seek(to seconds: Double) async throws(AppRefusal) {
        try needVideo()
        guard (0...engine.duration).contains(seconds) else {
            throw AppRefusal(
                "\(TimeCode.text(seconds)) is outside the video (0:00 to \(TimeCode.text(engine.duration)))"
            )
        }
        await engine.seek(to: seconds)
    }

    func state() -> StateReport {
        StateReport(
            app: .init(version: Version.app, variant: AppIdentity.variant, demo: isDemo, support: support.path),
            video: video.map { .init(path: $0.url.path, title: $0.title, duration: engine.duration) },
            player: .init(time: engine.time, playing: engine.isPlaying)
        )
    }

    private func needVideo() throws(AppRefusal) {
        guard video != nil else { throw AppRefusal("no video is open; open one with `video-review player open <path>`") }
    }

    // MARK: - The person's gestures

    /// Space, K, a click on the frame, the play button.
    func togglePlay() {
        guard video != nil else { return }
        if engine.isPlaying { engine.pause() } else { engine.play() }
    }

    /// Left and Right: `seconds` back or forward, kept inside the video.
    func skip(by seconds: Double) {
        move(to: engine.time + seconds)
    }

    /// Shift+Left and Shift+Right: `frames` back or forward.
    func step(frames: Int) {
        engine.pause()
        move(to: engine.time + Double(frames) * engine.frameDuration)
    }

    /// A drag on the scrubber, to `seconds`.
    func scrub(to seconds: Double) {
        move(to: seconds)
    }

    private func move(to seconds: Double) {
        guard video != nil else { return }
        let target = min(max(seconds, 0), engine.duration)
        Task { await engine.seek(to: target) }
    }

    /// Cmd+O and the Open button: the file the person picks.
    func openFromPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.videoTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a video to review"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openForPerson(url)
    }

    /// Opens `url` for the person, who is shown why when it doesn't play.
    func openForPerson(_ url: URL) {
        Task {
            do throws(AppRefusal) {
                try await open(url)
            } catch {
                problem = error.reason
            }
        }
    }
}
