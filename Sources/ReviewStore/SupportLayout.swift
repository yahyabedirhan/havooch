import Foundation
import ReviewCore

/// Every path the store keeps under one support folder: the person's own,
/// or a demo's. The one place that names a file; `Library`, the image and
/// transcript files and the payload all ask it. It never looks outside its
/// root, so demo data and real data can't mix. A pure value: it touches no
/// file.
///
///     <root>/outboxes/<review>.json                   one review's sends in line for its listener (`video-<contentHash>`, `project-<slug>`)
///     <root>/outbox.json                              every video's sends, as builds before a listener per review kept them: split once into outboxes/
///     <root>/recents.json                             the 10 recent videos, the newest first, with their last position
///     <root>/settings.json                            the sidebar width (app state)
///     <root>/config-status.json                       the verdict on config.toml after the app's last reload
///     <root>/videos/<contentHash>/review.json         one plain video's review
///     <root>/videos/<contentHash>/transcript.json     a video's transcribed speech, plain or a project's version
///     <root>/videos/<contentHash>/frames/<id>.png     a thread's keyframe
///     <root>/videos/<contentHash>/crops/<id>.png      a region message's crop
///     <root>/projects/<slug>/review.json              one project's review
///     <root>/projects/<slug>/frames/<id>.png          a thread's keyframe, on any version
///     <root>/projects/<slug>/crops/<id>.png           a region message's crop
///
/// The settings a person sets on purpose and their own themes are not
/// here: they are in `config.toml` and `themes/` beside it, as
/// `ReviewConfig.ConfigLocation` defines.
///
/// A video's folder is named after the hash of its content, so a renamed or
/// moved file finds its review again. The socket and the demo pointer are
/// `ReviewWire`'s: the command needs them and doesn't link the store.
public struct SupportLayout: Equatable, Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// The one outbox of builds before a listener per review: split once
    /// into the outbox of each review its sends are on, then deleted.
    public var formerOutboxFile: URL { root.appendingPathComponent("outbox.json") }
    public var outboxesFolder: URL { root.appendingPathComponent("outboxes", isDirectory: true) }

    /// The sends in line for the listener of the review `key`.
    public func outboxFile(_ key: ReviewKey) -> URL {
        outboxesFolder.appendingPathComponent("\(key.fileName).json")
    }
    public var recentsFile: URL { root.appendingPathComponent("recents.json") }
    /// The last open video as builds before the recent videos kept it: read
    /// once into `recentsFile`, then deleted.
    public var formerRecentFile: URL { root.appendingPathComponent("recent.json") }
    public var settingsFile: URL { root.appendingPathComponent("settings.json") }
    /// Where builds before `config.toml` kept the person's themes: moved
    /// once into the themes folder beside `config.toml`.
    public var formerThemesFolder: URL { root.appendingPathComponent("Themes", isDirectory: true) }
    public var videosFolder: URL { root.appendingPathComponent("videos", isDirectory: true) }
    /// The projects' reviews, one folder per slug.
    public var projectsFolder: URL { root.appendingPathComponent("projects", isDirectory: true) }

    /// The folder of everything kept about the video with `contentHash`:
    /// its transcript, and its plain review.
    public func videoFolder(_ contentHash: String) -> URL {
        videosFolder.appendingPathComponent(contentHash, isDirectory: true)
    }

    /// The folder of the review `key`: its review file, keyframes and crops.
    public func folder(_ key: ReviewKey) -> URL {
        switch key {
        case .video(let contentHash): videoFolder(contentHash)
        case .project(let slug): projectsFolder.appendingPathComponent(slug, isDirectory: true)
        }
    }

    /// The review file of the review `key`.
    public func reviewFile(_ key: ReviewKey) -> URL {
        folder(key).appendingPathComponent("review.json")
    }

    /// The transcribed speech of the video with `contentHash`.
    public func transcriptFile(_ contentHash: String) -> URL {
        videoFolder(contentHash).appendingPathComponent("transcript.json")
    }

    /// The folder of the keyframes of the review `key`.
    public func framesFolder(_ key: ReviewKey) -> URL {
        folder(key).appendingPathComponent("frames", isDirectory: true)
    }

    /// The folder of the crops of the review `key`.
    public func cropsFolder(_ key: ReviewKey) -> URL {
        folder(key).appendingPathComponent("crops", isDirectory: true)
    }

    /// The keyframe of `thread` of the review `key`. General has none.
    public func keyframe(_ thread: ThreadID, of key: ReviewKey) -> URL {
        framesFolder(key).appendingPathComponent("\(thread.text).png")
    }

    /// The crop of `message`'s region of the review `key`. Only a message
    /// on a region has the file.
    public func crop(_ message: MessageID, of key: ReviewKey) -> URL {
        cropsFolder(key).appendingPathComponent("\(message.text).png")
    }

    /// The keyframe of `thread` of the review `key`; nil for General,
    /// which has no frame.
    public func keyframe(of thread: ReviewThread, on key: ReviewKey) -> URL? {
        thread.isGeneral ? nil : keyframe(thread.id, of: key)
    }

    /// The crop of `message` of the review `key`; nil for a message on the
    /// whole frame: only a region message has a crop.
    public func crop(of message: Message, on key: ReviewKey) -> URL? {
        message.region == nil ? nil : crop(message.id, of: key)
    }

    /// Where an image is written before the message it's for has its id:
    /// beside the keyframes, named by `token`, and renamed to its own path
    /// once the message is in the review.
    public func pendingImage(_ token: String, of key: ReviewKey) -> URL {
        framesFolder(key).appendingPathComponent(".pending-\(token).png")
    }
}
