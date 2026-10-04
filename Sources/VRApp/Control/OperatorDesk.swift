import Foundation
import VRReview
import VRWire

/// The operator's requests: each one a call on the model a person's click
/// also ends in, answered with the text the command prints (lines, or one
/// JSON object with `--json`). A refusal by the model is the reply's error.
@MainActor
struct OperatorDesk {
    let model: ReviewModel
    /// Writes the window as a PNG at a file, in an appearance.
    let screenshot: @MainActor (URL, ControlRequest.Appearance?) async -> ScreenshotOutcome

    func open(_ path: String, json: Bool) async -> ControlReply {
        await answer { () async throws(ModelRefusal) in
            try await model.open(URL(fileURLWithPath: path))
            guard let video = model.video?.info else { throw ModelRefusal("the video didn't open") }
            struct Opened: Encodable { var video: VideoInfo }
            return json ? JSONLine.string(Opened(video: video)) : "opened \(video.title) (\(TimeText.exact(video.duration)))\n"
        }
    }

    func play(json: Bool) async -> ControlReply {
        await answer { () async throws(ModelRefusal) in
            try await model.play()
            return playback(json: json)
        }
    }

    func pause(json: Bool) async -> ControlReply {
        await answer { () async throws(ModelRefusal) in
            try model.pause()
            return playback(json: json)
        }
    }

    func seek(to seconds: Double, json: Bool) async -> ControlReply {
        await answer { () async throws(ModelRefusal) in
            try await model.seek(to: seconds)
            struct Sought: Encodable { var time: Double }
            let time = TimeText.rounded(model.time)
            return json ? JSONLine.string(Sought(time: time)) : "at \(TimeText.exact(time))\n"
        }
    }

    func addComment(text: String, at seconds: Double?, region wire: ControlRequest.WireRegion?, json: Bool) async -> ControlReply {
        await answer { () async throws(ModelRefusal) in
            var region: Region?
            if let wire {
                do throws(ReviewRefusal) {
                    region = try Region(x: wire.x, y: wire.y, w: wire.w, h: wire.h)
                } catch {
                    throw ModelRefusal(error.reason)
                }
            }
            let comment = try await model.addComment(text: text, at: seconds, region: region)
            return json
                ? JSONLine.string(CommentReport(comment, keyframe: model.keyframeURL(for: comment.id), crop: model.cropURL(for: comment.id)))
                : "\(comment.id) at \(TimeText.exact(comment.time))\n"
        }
    }

    func editComment(_ id: String, text: String, json: Bool) async -> ControlReply {
        await answer { () throws(ModelRefusal) in
            try model.editComment(id, text: text)
            return json ? JSONLine.string(Named(id: id)) : "edited \(id)\n"
        }
    }

    func deleteComment(_ id: String, json: Bool) async -> ControlReply {
        await answer { () throws(ModelRefusal) in
            try model.deleteComment(id)
            return json ? JSONLine.string(Named(id: id)) : "deleted \(id)\n"
        }
    }

    /// `batch send`: `sent b1 with 2 comments`, or `{id, sentAt, commentIds}`.
    func sendBatch(json: Bool) async -> ControlReply {
        await answer { () async throws(ModelRefusal) in
            let batch = try await model.sendBatch()
            struct Sent: Encodable { var id: String; var sentAt: String; var commentIds: [String] }
            let count = batch.commentIDs.count
            return json
                ? JSONLine.string(Sent(id: batch.id, sentAt: batch.sentAt.formatted(.iso8601), commentIds: batch.commentIDs))
                : "sent \(batch.id) with \(count) comment\(count == 1 ? "" : "s")\n"
        }
    }

    /// `context set`: `context note set` (`context note cleared` for an
    /// empty text), or `{note}` with the note as it was kept.
    func setNote(_ text: String, json: Bool) async -> ControlReply {
        await answer { () throws(ModelRefusal) in
            try model.setNote(text)
            struct Noted: Encodable { var note: String }
            let note = model.note
            return json ? JSONLine.string(Noted(note: note)) : "context note \(note.isEmpty ? "cleared" : "set")\n"
        }
    }

    /// `{id}`: what a change to one comment prints with `--json`.
    private struct Named: Encodable {
        var id: String
    }

    func screenshot(to path: String, appearance: ControlRequest.Appearance?, json: Bool) async -> ControlReply {
        struct Saved: Encodable { var path: String }
        let output = json ? JSONLine.string(Saved(path: path)) : path + "\n"
        switch await screenshot(URL(fileURLWithPath: path), appearance) {
        case .captured:
            return .done(output)
        case .rendered(let why):
            return .done(output, note: "captured by rendering: \(why)\n")
        case .failed(let why):
            return .refused(why)
        }
    }

    /// The reply for what `body` prints, or for the model's refusal.
    private func answer(_ body: () async throws(ModelRefusal) -> String) async -> ControlReply {
        do throws(ModelRefusal) {
            return .done(try await body())
        } catch {
            return .refused(error.reason)
        }
    }

    /// `playing at 0:10.000`, `paused at 0:10.000`, or `{playing, time}`.
    private func playback(json: Bool) -> String {
        struct Playback: Encodable { var playing: Bool; var time: Double }
        let time = TimeText.rounded(model.time)
        return json
            ? JSONLine.string(Playback(playing: model.isPlaying, time: time))
            : "\(model.isPlaying ? "playing" : "paused") at \(TimeText.exact(time))\n"
    }
}
