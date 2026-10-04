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
    case crop(String)
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
        case .crop(let why):
            "can't keep the comment's crop: \(why)"
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
    /// The rectangle the person is dragging on the frame, until it is let go.
    private(set) var draw = RegionDraw()
    /// Whether the video was playing when that rectangle began.
    private var drawResumes = false
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

    /// Pauses, and opens the comment box for a comment at the playhead:
    /// on `region` of the frame when there is one. With the box already
    /// open, a region becomes that comment's and nothing else changes.
    func startDraft(region: Region? = nil) throws(ActionError) {
        guard player.video != nil else { throw .noVideo }
        guard desk.draft == nil || region != nil else { return }
        let resumes = player.playing
        player.pause()
        openDraft(region: region, resumes: resumes)
    }

    /// The comment box for a comment at the playhead of the paused video.
    private func openDraft(region: Region?, resumes: Bool) {
        guard let video = player.video else { return }
        if let draft = desk.draft, draft.time == player.time {
            desk.pointDraft(at: region)
        } else {
            // A box left open while the video moved on starts over at the frame on screen.
            desk.startDraft(time: player.time, region: region, resumes: resumes || desk.draft?.resumes == true, video: video.url)
        }
    }

    /// Return in the comment box: queues what was typed, closes the box,
    /// and plays on when the video was playing as the box opened.
    @discardableResult
    func commitDraft(text: String) async throws(ActionError) -> Comment {
        guard let draft = desk.draft else { throw .noDraft }
        let comment = try await queueComment(text: text, time: draft.time, region: draft.region, frame: draft.frame)
        desk.endDraft()
        if draft.resumes { player.play() }
        return comment
    }

    /// Escape in the comment box: closes it and keeps nothing, its region
    /// neither.
    func discardDraft() {
        desk.endDraft()
    }

    // MARK: - Drawing a region

    /// The button went down on the frame's view, at `point` of it.
    func beginRegion(at point: CGPoint) {
        guard player.video != nil else { return }
        draw.begin(at: point)
    }

    /// The pointer moved to `point` with the button down. The move that
    /// makes the press a rectangle pauses the video, so the frame drawn on
    /// is the frame commented on.
    func dragRegion(to point: CGPoint) {
        guard draw.move(to: point) == .began else { return }
        drawResumes = player.playing
        player.pause()
    }

    /// The button was let go, with the frame placed as `geometry` says: a
    /// rectangle opens the comment box on its region, and a press that
    /// didn't move plays or pauses.
    func endRegion(in geometry: FrameGeometry) {
        switch draw.end(in: geometry) {
        case .nothing:
            break
        case .click:
            togglePlayback()
        case .region(let region):
            openDraft(region: region, resumes: drawResumes)
        case .empty:
            if drawResumes { player.play() }
        }
        drawResumes = false
    }

    /// Escape while a rectangle is drawn: gives it up, and plays on when
    /// the video was playing. Whether there was one to give up.
    @discardableResult
    func cancelRegion() -> Bool {
        let wasDrawing = draw.isDrawing
        guard draw.cancel() else { return false }
        if wasDrawing, drawResumes { player.play() }
        drawResumes = false
        return true
    }

    /// The command line's way to a comment: at `at`, or at the playhead,
    /// and on `region` of the frame when there is one. The playhead stays
    /// where it is.
    @discardableResult
    func addComment(text: String, at: Double?, region: Region? = nil) async throws(ActionError) -> Comment {
        try await queueComment(text: text, time: at ?? player.time, region: region, frame: nil)
    }

    /// The one way a comment comes to be, from the comment box and the
    /// command line alike: refused first by the review's own rules, then
    /// queued with the frame at its time as its keyframe and, with a
    /// region, that part of the keyframe as its crop. `frame` is that frame
    /// when it is already being read. The new comment is the one in focus.
    private func queueComment(
        text: String, time: Double, region: Region?, frame: Task<Result<CGImage, FrameFailure>, Never>?
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
        case .success(let image):
            let comment = try desk.add(text: text, time: time, region: region, frame: image, to: review.video.contentHash)
            selection = comment.id
            return comment
        case .failure(let failure):
            throw .keyframe(failure.why)
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
            draft: desk.draft.map { .init(time: $0.time, region: $0.region) },
            comments: desk.open?.comments.map(shown) ?? [],
            queue: desk.open?.queue.map(\.id.rawValue) ?? [],
            lease: lease
        )
    }

    /// `comment` as `state` and a comment command's `--json` print it.
    func shown(_ comment: Comment) -> StateSnapshot.Comment {
        .init(
            id: comment.id.rawValue, time: comment.time, text: comment.text, region: comment.region,
            state: comment.state.rawValue, batchId: comment.batch?.rawValue, keyframePath: desk.keyframe(of: comment.id).path,
            cropPath: comment.region == nil ? nil : desk.crop(of: comment.id).path, thread: comment.thread
        )
    }
}
