import AppKit
import Observation
import ReviewCore
import ReviewStore
import ReviewWire
import UniformTypeIdentifiers

/// The orchestrator: which video is open, the comment being written, the
/// selection, and every action a person or an operator can take. The UI and
/// the control server call the same methods, so a click and its CLI command
/// are one code path.
@MainActor
@Observable
final class AppModel: AppControlling {
    /// The video that's open.
    struct OpenVideo: Equatable {
        var url: URL
        /// The file's name without its extension.
        var title: String
        /// The hash of the file's content: the video's identity.
        var contentHash: String
    }

    /// The comment still in the comment box: it has a time, and no id and
    /// no keyframe until it's queued.
    struct Draft: Equatable {
        var time: Double
        var text: String
    }

    /// Why the last thing the person asked for didn't work.
    struct Problem: Equatable {
        var title: String
        var reason: String
    }

    let engine = PlayerEngine()
    /// The open video's review, and the one path for changing it.
    let desk = ReviewDesk()
    /// Where this run keeps its data: the person's own, or a demo's.
    let support: URL
    /// Whether this run is on demo data (`app open --demo`).
    let isDemo: Bool
    private(set) var video: OpenVideo?
    /// The comment being written; nil while the comment box is closed.
    var draft: Draft?
    /// The comment whose marker and card are picked out.
    private(set) var selection: ItemID?
    /// Whether the rail is shown beside the stage.
    var isRailVisible = true
    /// Shown to the person until they dismiss it.
    var problem: Problem?

    @ObservationIgnored private let images: ImageFiles

    /// The files the Open panel offers: what the spec names.
    static let videoTypes: [UTType] = [.mpeg4Movie, .quickTimeMovie, UTType("com.apple.m4v-video")].compactMap(\.self)

    init(environment: [String: String]) {
        support = SupportFolder.app(environment: environment)
        isDemo = SupportFolder.moved(environment: environment) != nil
        images = ImageFiles(support: support)
    }

    /// The open video's comments, in time order.
    var comments: [Comment] { desk.review?.comments ?? [] }

    // MARK: - Actions, for the person and the operator alike

    func open(_ url: URL) async throws(AppRefusal) {
        let url = url.standardizedFileURL
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), !isFolder.boolValue else {
            throw AppRefusal("no video file at \(url.path)")
        }
        guard let contentHash = await Task.detached(operation: { ContentHash.of(url) }).value else {
            throw AppRefusal("can't read \(url.path)")
        }
        try await engine.load(url)
        let title = url.deletingPathExtension().lastPathComponent
        video = OpenVideo(url: url, title: title, contentHash: contentHash)
        draft = nil
        selection = nil
        desk.open(VideoInfo(contentHash: contentHash, title: title, duration: engine.duration, path: url.path))
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
        try needInside(seconds)
        await engine.seek(to: seconds)
    }

    /// Queues a comment at `at`, or where the player is. As a person
    /// would, it pauses and moves the player to the comment's time first.
    func addComment(text: String, at: Double?) async throws(AppRefusal) -> StateReport.Comment {
        try needVideo()
        try needWords(text)
        if let at { try needInside(at) }
        engine.pause()
        if let at { await engine.seek(to: at) }
        return try await queueComment(text: text, time: at ?? currentCommentTime)
    }

    func editComment(_ id: String, text: String) throws(AppRefusal) -> StateReport.Comment {
        let id = try commentID(id)
        return report(try desk.change { review throws(ReviewRefusal) in try review.editComment(id, text: text) })
    }

    func deleteComment(_ id: String) throws(AppRefusal) -> StateReport.Comment {
        let id = try commentID(id)
        let comment = try desk.change { review throws(ReviewRefusal) in try review.deleteComment(id) }
        let report = report(comment)
        ImageFiles.remove(URL(fileURLWithPath: report.keyframePath))
        if selection == id { selection = nil }
        return report
    }

    func state() -> StateReport {
        StateReport(
            app: .init(version: Version.app, variant: AppIdentity.variant, demo: isDemo, support: support.path),
            video: video.map {
                .init(path: $0.url.path, contentHash: $0.contentHash, title: $0.title, duration: engine.duration)
            },
            player: .init(time: engine.time, playing: engine.isPlaying),
            draft: draft.map { .init(time: $0.time, text: $0.text) },
            comments: comments.map(report)
        )
    }

    // MARK: - Comments

    /// The time a comment made now gets: the player's, raised to the next
    /// millisecond.
    private var currentCommentTime: Double {
        Self.commentTime(player: engine.time, duration: engine.duration)
    }

    /// The player's time as a comment keeps it: to the millisecond, and
    /// never before the frame on screen. A frame rarely starts on a whole
    /// millisecond (7.2333… s at 30 frames a second); rounding down would
    /// name the frame before it.
    static func commentTime(player: Double, duration: Double) -> Double {
        // The player's own noise, far below a millisecond, isn't raised.
        let milliseconds = (max(player, 0) * 1000 - 1e-6).rounded(.up)
        return min(milliseconds / 1000, duration)
    }

    /// Writes the keyframe, then queues the comment and selects it. A
    /// comment never exists without its keyframe.
    private func queueComment(text: String, time: Double) async throws(AppRefusal) -> StateReport.Comment {
        guard let video, let asset = engine.asset else { throw Self.noVideo }
        try needWords(text)
        let id = ItemID.make(.comment)
        let file = images.keyframe(of: id, contentHash: video.contentHash)
        try await FrameGrabber.writeKeyframe(
            of: asset, at: time, duration: engine.duration, frameDuration: engine.frameDuration, to: file
        )
        guard self.video == video else {
            ImageFiles.remove(file)
            throw AppRefusal("another video opened before the comment was queued")
        }
        do throws(AppRefusal) {
            let comment = try desk.change { review throws(ReviewRefusal) in
                try review.addComment(id: id, time: time, text: text)
            }
            selection = id
            return report(comment)
        } catch {
            ImageFiles.remove(file)
            throw error
        }
    }

    private func report(_ comment: Comment) -> StateReport.Comment {
        StateReport.Comment(
            id: comment.id.text, time: comment.time, text: comment.text, state: comment.state.rawValue,
            keyframePath: keyframe(of: comment)?.path ?? ""
        )
    }

    /// The keyframe PNG of `comment` on the open video.
    func keyframe(of comment: Comment) -> URL? {
        video.map { images.keyframe(of: comment.id, contentHash: $0.contentHash) }
    }

    // MARK: - What an action needs

    private static let noVideo = AppRefusal("no video is open; open one with `video-review player open <path>`")

    private func needVideo() throws(AppRefusal) {
        guard video != nil else { throw Self.noVideo }
    }

    private func needInside(_ seconds: Double) throws(AppRefusal) {
        guard (0...engine.duration).contains(seconds) else {
            throw AppRefusal(
                "\(TimeCode.text(seconds)) is outside the video (0:00 to \(TimeCode.text(engine.duration)))"
            )
        }
    }

    private func needWords(_ text: String) throws(AppRefusal) {
        guard Self.hasWords(text) else { throw AppRefusal(ReviewRefusal.emptyText.line) }
    }

    static func hasWords(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func commentID(_ text: String) throws(AppRefusal) -> ItemID {
        guard let id = ItemID(text), id.kind == .comment else {
            throw AppRefusal(ReviewRefusal.unknownComment(text).line)
        }
        return id
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

    /// C, Return and the Comment button: pauses and opens the comment box
    /// at the player's time.
    func startDraft() {
        guard video != nil, draft == nil else { return }
        engine.pause()
        draft = Draft(time: currentCommentTime, text: "")
    }

    /// Escape in the comment box.
    func cancelDraft() {
        draft = nil
    }

    /// Return in the comment box: queues the draft. A draft with no words
    /// stays open.
    func commitDraft() {
        guard let draft, Self.hasWords(draft.text) else { return }
        self.draft = nil
        Task {
            do throws(AppRefusal) {
                _ = try await queueComment(text: draft.text, time: draft.time)
            } catch {
                // The words aren't lost: the box opens again with them.
                if self.draft == nil { self.draft = draft }
                problem = Problem(title: "The comment wasn't queued", reason: error.reason)
            }
        }
    }

    /// A click on a marker or a card: selects the comment, pauses and
    /// moves the player to its time.
    func select(_ id: ItemID) {
        guard let comment = desk.review?.comment(id) else { return }
        selection = id
        engine.pause()
        move(to: comment.time)
    }

    /// Up and Down: the marker before or after the player's time.
    func jumpToMarker(forward: Bool) {
        // Half a frame: the marker the player stands on isn't its own neighbour.
        let slack = engine.frameDuration / 2
        let next = forward
            ? comments.first { $0.time > engine.time + slack }
            : comments.last { $0.time < engine.time - slack }
        if let next { select(next.id) }
    }

    /// Save on a card: the comment's new text.
    func edit(_ id: ItemID, text: String) {
        do throws(AppRefusal) {
            _ = try editComment(id.text, text: text)
        } catch {
            problem = Problem(title: "The comment didn't change", reason: error.reason)
        }
    }

    /// Delete on a card.
    func delete(_ id: ItemID) {
        do throws(AppRefusal) {
            _ = try deleteComment(id.text)
        } catch {
            problem = Problem(title: "The comment wasn't deleted", reason: error.reason)
        }
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
                problem = Problem(title: "The video didn't open", reason: error.reason)
            }
        }
    }
}
