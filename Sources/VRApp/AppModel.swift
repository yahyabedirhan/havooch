import AppKit
import Observation
import UniformTypeIdentifiers
import VRLease
import VRReview
import VRStore
import VRWire

/// Why an action is refused: its `message` is the one line a command
/// prints on standard error, and what the window shows a person.
enum ActionError: Error, Equatable {
    case noVideo
    case cannotOpen(path: String, why: String)
    case timeOutsideVideo(Double, duration: Double)
    case noDraft
    case keyframe(String)
    case review(ReviewError)

    var message: String {
        switch self {
        case .noVideo:
            "no video is open"
        case .cannotOpen(let path, let why):
            "can't open \(path): \(why)"
        case .timeOutsideVideo(let seconds, let duration), .review(.timeOutsideVideo(let seconds, let duration)):
            "\(TimeText.precise(seconds)) is outside the video, which ends at \(TimeText.precise(duration))"
        case .noDraft:
            "no comment is being written"
        case .keyframe(let why):
            "can't keep the comment's keyframe: \(why)"
        case .review(let refusal):
            refusal.message
        }
    }
}

/// The orchestrator: every action a person or an agent can take is one
/// method here, called by the views and by `ControlServer` alike, so the
/// window and the command line can't drift apart.
@MainActor @Observable
final class AppModel {
    let player = PlayerEngine()
    let desk: ReviewDesk
    /// The folder this run keeps its data in, and whether it's a demo's.
    let support: URL
    let isDemo: Bool
    /// The comment whose marker and card are in focus.
    private(set) var selection: CommentID?
    /// The last refusal of something the person did, shown until dismissed.
    var failure: String?
    /// The app's one window, for `Screenshotter`.
    @ObservationIgnored weak var window: NSWindow?

    init(environment: [String: String]) {
        support = SupportFolder.current(environment: environment)
        isDemo = SupportFolder.demo(environment: environment) != nil
        desk = ReviewDesk(layout: SupportLayout(root: support))
    }

    // MARK: - Actions

    /// Opens `video`, replacing the one that was open, with its review.
    @discardableResult
    func open(_ video: URL) async throws(ActionError) -> VideoInfo {
        // What names the video whatever its file is called. A file that
        // can't be read for it can't be played either.
        guard let hash = try? ContentHash.of(video) else {
            throw .cannotOpen(path: video.path, why: "there's no readable file")
        }
        let opened: OpenVideo
        do {
            opened = try await player.open(video)
        } catch {
            if player.video == nil {
                desk.close()
                selection = nil
            }
            throw .cannotOpen(path: video.path, why: error.why)
        }
        selection = nil
        return desk.load(VideoInfo(contentHash: hash, path: opened.url.path, title: opened.title, duration: opened.duration)).video
    }

    func play() throws(ActionError) {
        guard player.video != nil else { throw .noVideo }
        player.play()
    }

    func pause() throws(ActionError) {
        guard player.video != nil else { throw .noVideo }
        player.pause()
    }

    /// Moves to `seconds` exactly; the time the player then stands at.
    @discardableResult
    func seek(to seconds: Double) async throws(ActionError) -> Double {
        guard let video = player.video else { throw .noVideo }
        guard seconds.isFinite, (0...video.duration).contains(seconds) else {
            throw .timeOutsideVideo(seconds, duration: video.duration)
        }
        return await player.seek(to: seconds)
    }

    /// The scrubber's drag: moves to `seconds`, kept inside the video,
    /// without waiting for the seek to land.
    func scrub(to seconds: Double) {
        player.scrub(to: seconds)
    }

    /// Sets the speed playback runs at.
    func setSpeed(_ speed: Double) {
        player.speed = speed
    }

    // MARK: - Comments

    /// Pauses, and opens the comment box for a comment at the playhead.
    func startDraft() throws(ActionError) {
        guard let video = player.video else { throw .noVideo }
        guard desk.draft == nil else { return }
        let resumes = player.playing
        player.pause()
        desk.startDraft(time: player.time, resumes: resumes, video: video.url)
    }

    /// Return in the comment box: queues what was typed, closes the box,
    /// and plays on when the video was playing as the box opened.
    @discardableResult
    func commitDraft(text: String) async throws(ActionError) -> Comment {
        guard let draft = desk.draft else { throw .noDraft }
        let comment = try await queueComment(text: text, time: draft.time, frame: draft.frame)
        desk.endDraft()
        if draft.resumes { player.play() }
        return comment
    }

    /// Escape in the comment box: closes it and keeps nothing.
    func discardDraft() {
        desk.endDraft()
    }

    /// The command line's way to a comment: at `at`, or at the playhead.
    /// The playhead stays where it is.
    @discardableResult
    func addComment(text: String, at: Double?) async throws(ActionError) -> Comment {
        try await queueComment(text: text, time: at ?? player.time, frame: nil)
    }

    /// The one way a comment comes to be, from the comment box and the
    /// command line alike: refused first by the review's own rules, then
    /// queued with the frame at its time as its keyframe. `frame` is that
    /// frame when it is already being read.
    private func queueComment(
        text: String, time: Double, frame: Task<Result<CGImage, FrameFailure>, Never>?
    ) async throws(ActionError) -> Comment {
        guard let review = desk.open, let video = player.video else { throw .noVideo }
        do throws(ReviewError) {
            _ = try review.checkedText(text, at: time)
        } catch {
            throw .review(error)
        }
        let grabbed: Result<CGImage, FrameFailure>
        if let frame {
            grabbed = await frame.value
        } else {
            grabbed = await ReviewDesk.frame(of: video.url, at: time)
        }
        switch grabbed {
        case .success(let image): return try desk.add(text: text, time: time, frame: image, to: review.video.contentHash)
        case .failure(let failure): throw .keyframe(failure.why)
        }
    }

    @discardableResult
    func editComment(_ id: CommentID, text: String) throws(ActionError) -> Comment {
        guard let review = desk.open else { throw .noVideo }
        return try desk.change(review.video.contentHash) { review throws(ReviewError) in try review.editComment(id, text: text) }
    }

    func deleteComment(_ id: CommentID) throws(ActionError) {
        guard let review = desk.open else { throw .noVideo }
        try desk.delete(id, from: review.video.contentHash)
        if selection == id { selection = nil }
    }

    /// A click on a comment's marker or card: moves to its time, paused,
    /// with the comment in focus in both places.
    func select(_ id: CommentID) {
        guard let comment = try? desk.open?.comment(id) else { return }
        selection = id
        player.pause()
        player.scrub(to: comment.time)
    }

    // MARK: - The person's ways into the actions

    /// Runs what the person asked for: a refusal is shown, not thrown.
    @discardableResult
    func attempt<T>(_ action: () throws(ActionError) -> T) -> T? {
        do throws(ActionError) {
            return try action()
        } catch {
            failure = error.message
            return nil
        }
    }

    /// Opens `video` for the person.
    func openForPerson(_ video: URL) {
        Task {
            do throws(ActionError) {
                try await open(video)
            } catch {
                failure = error.message
            }
        }
    }

    /// Queues the comment box's text for the person; whether it was queued.
    func commitDraftForPerson(text: String) async -> Bool {
        do throws(ActionError) {
            try await commitDraft(text: text)
            return true
        } catch {
            failure = error.message
            return false
        }
    }

    /// Asks the person for a video, and opens it.
    func chooseVideo() {
        let panel = NSOpenPanel()
        // mp4, mov and m4v: the kinds the app opens.
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie, UTType("com.apple.m4v-video") ?? .movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a video to review"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openForPerson(url)
    }

    /// The play button, and a click on the frame.
    func togglePlayback() {
        if player.playing {
            try? pause()
        } else {
            try? play()
        }
    }

    /// What a player key does.
    func perform(_ action: PlayerAction) {
        guard let video = player.video else { return }
        switch action {
        case .togglePlayback:
            togglePlayback()
        case .skip(let seconds):
            scrub(to: player.time + seconds)
        case .step(let frames):
            player.pause()
            scrub(to: player.time + Double(frames) / video.frameRate)
        case .comment:
            attempt { () throws(ActionError) in try startDraft() }
        case .deleteSelection:
            guard let selection, (try? desk.open?.comment(selection))?.state == .queued else { return }
            attempt { () throws(ActionError) in try deleteComment(selection) }
        }
    }

    // MARK: - State

    /// What the window shows now, for `state` and `app status`.
    func snapshot(lease: ControlLease.Status?) -> StateSnapshot {
        StateSnapshot(
            app: .init(version: Identity.version, variant: Identity.variant, demo: isDemo, support: support.path),
            video: player.video.map {
                .init(path: $0.url.path, contentHash: desk.open?.video.contentHash, title: $0.title, duration: $0.duration)
            },
            player: .init(time: player.time, playing: player.playing, rate: player.speed),
            draft: desk.draft.map { .init(time: $0.time) },
            comments: desk.open?.comments.map(shown) ?? [],
            queue: desk.open?.queue.map(\.id.rawValue) ?? [],
            lease: lease
        )
    }

    /// `comment` as `state` and a comment command's `--json` print it.
    func shown(_ comment: Comment) -> StateSnapshot.Comment {
        .init(
            id: comment.id.rawValue, time: comment.time, text: comment.text, state: comment.state.rawValue,
            batchId: comment.batch?.rawValue, keyframePath: desk.keyframe(of: comment.id).path, thread: comment.thread
        )
    }
}
