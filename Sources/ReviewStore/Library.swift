import Foundation
import ReviewCore

/// Loads and saves what the app keeps between runs: the reviews, the
/// outboxes and the recent videos, at the paths its `SupportLayout` gives.
/// Every save writes the whole file to a
/// temporary one and renames it over the old one: a reader, and a run that
/// ends half way, see the old file or the new one, never a part of one.
///
/// A file that doesn't read, or that a newer build wrote, is never written
/// over: its video's history isn't opened, and the reason is given.
///
/// One per support folder, used on the main actor.
public final class Library {
    public let layout: SupportLayout

    /// The version of the files this build writes. A file with a higher
    /// one is left as it is.
    public static let schemaVersion = 1

    /// Why a file wasn't read or written, as one line.
    public struct Failure: Error, Equatable {
        public var reason: String

        public init(reason: String) {
            self.reason = reason
        }
    }

    /// The review on disk with each id prefix: a listener's command names
    /// an id, whose prefix names its review.
    private var index: [String: ReviewKey] = [:]
    /// The content hash of each plain video with a review on disk, by the
    /// path its review records: `recent.json` named a path only.
    private var paths: [String: String] = [:]
    /// The sends on disk with a message the listener hasn't finished, in
    /// the order they were sent, as the reviews read at launch.
    private var unfinished: [SendRef] = []
    /// The reviews whose outbox file a newer build wrote: each is left as it is.
    private var newerOutboxes: Set<ReviewKey> = []

    /// Reads every review under `layout` once, the plain videos' and the
    /// projects', for its key and its unfinished sends. Nothing is written.
    public init(layout: SupportLayout) {
        self.layout = layout
        var sent: [(Date, SendRef)] = []
        let fileManager = FileManager.default
        let videos = (try? fileManager.contentsOfDirectory(at: layout.videosFolder, includingPropertiesForKeys: nil)) ?? []
        let projects = (try? fileManager.contentsOfDirectory(at: layout.projectsFolder, includingPropertiesForKeys: nil)) ?? []
        let keys = videos.map { ReviewKey.video(contentHash: $0.lastPathComponent) }
            + projects.map { ReviewKey.project(slug: $0.lastPathComponent) }
        for key in keys {
            // A review that doesn't read stays out; opening it says why.
            guard let review = try? load(key) else { continue }
            note(review)
            for send in review.sends where !review.isFinished(send.id) {
                sent.append((send.sentAt, SendRef(sendID: send.id, review: review.key)))
            }
        }
        unfinished = sent.sorted { $0.0 < $1.0 }.map(\.1)
    }

    // MARK: - Reviews

    /// The review on disk whose ids carry `prefix`; nil when there's none.
    public func key(prefix: String) -> ReviewKey? {
        index[prefix]
    }

    /// The review on disk the thread, message or send `id` is on; nil
    /// when no review has its prefix.
    public func key(of id: ItemID) -> ReviewKey? {
        key(prefix: id.hash8)
    }

    /// Whether a review other than `key` has the id prefix `hash8`.
    public func isTaken(_ hash8: String, by other: ReviewKey) -> Bool {
        index[hash8].map { $0 != other } ?? false
    }

    /// The review kept as `key`; nil when there's none yet. Throws when
    /// there is a file and it doesn't read, or a newer build wrote it:
    /// that file must not be written over.
    public func load(_ key: ReviewKey) throws(Failure) -> Review? {
        let file = layout.reviewFile(key)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let kept: Kept<Review> = try read(file)
        // A folder that was copied or renamed by hand isn't that review's.
        guard kept.content.key == key else {
            throw Failure(reason: "\(file.path) is the review of another video or project (\(Self.name(kept.content.key)))")
        }
        return kept.content
    }

    /// Keeps `review`, replacing its file.
    public func save(_ review: Review) throws(Failure) {
        try write(Kept(content: review), to: layout.reviewFile(review.key))
        note(review)
    }

    /// Moves the review kept as `old` to `review`'s own key (`project new
    /// --from`): `review` is written first, then the keyframes and crops
    /// move to its folder, then the old review file goes. The old folder
    /// keeps the video's transcript. When `review` can't be written,
    /// nothing changes.
    public func move(_ review: Review, from old: ReviewKey) throws(Failure) {
        try save(review)
        let fileManager = FileManager.default
        for (from, to) in [(layout.framesFolder(old), layout.framesFolder(review.key)), (layout.cropsFolder(old), layout.cropsFolder(review.key))] {
            guard let files = try? fileManager.contentsOfDirectory(at: from, includingPropertiesForKeys: nil) else { continue }
            try? fileManager.createDirectory(at: to, withIntermediateDirectories: true)
            for file in files {
                // A picture that can't move stays; the review file says what's kept.
                try? fileManager.moveItem(at: file, to: to.appendingPathComponent(file.lastPathComponent))
            }
            try? fileManager.removeItem(at: from)
        }
        try? fileManager.removeItem(at: layout.reviewFile(old))
        unfinished = unfinished.map { $0.review == old ? SendRef(sendID: $0.sendID, review: review.key) : $0 }
        if let contentHash = old.contentHash { paths = paths.filter { $0.value != contentHash } }
    }

    private func note(_ review: Review) {
        index[review.hash8] = review.key
        if let contentHash = review.key.contentHash { paths[review.video.path] = contentHash }
    }

    /// `the video <hash>` or `the project <slug>`.
    private static func name(_ key: ReviewKey) -> String {
        switch key {
        case .video(let contentHash): "the video \(contentHash)"
        case .project(let slug): "the project \(slug)"
        }
    }

    // MARK: - The outboxes

    /// The outbox of the review `key` as the last run left it, made to
    /// agree with the reviews on disk (`Outbox.reconcile`): with no file,
    /// or one that doesn't read, every unfinished send of the review is in
    /// line again, so no feedback is lost with the file.
    public func loadOutbox(_ key: ReviewKey) -> Outbox {
        let file = layout.outboxFile(key)
        var outbox = Outbox()
        if FileManager.default.fileExists(atPath: file.path) {
            do throws(Failure) {
                let kept: Kept<Outbox> = try read(file)
                outbox = kept.content
            } catch {
                if isNewer(file) { newerOutboxes.insert(key) }
            }
        }
        outbox.reconcile(unfinished: unfinished.filter(key.holds))
        return outbox
    }

    /// Keeps `outbox` as the review `key`'s. A newer build's file is left
    /// as it is.
    public func save(_ outbox: Outbox, of key: ReviewKey) throws(Failure) {
        let file = layout.outboxFile(key)
        guard !newerOutboxes.contains(key) else { throw Failure(reason: "\(file.path) is from a newer version of the app") }
        try write(Kept(content: outbox), to: file)
    }

    /// Deletes the outbox file of the review `key`, which became another
    /// review (`project new --from`) and whose outbox is kept under that
    /// one's key now. A newer build's file is left as it is.
    public func removeOutbox(_ key: ReviewKey) {
        guard !newerOutboxes.contains(key) else { return }
        try? FileManager.default.removeItem(at: layout.outboxFile(key))
    }

    /// Splits the one outbox of builds before a listener per review into
    /// the outbox of each review its sends are on, once: each part keeps
    /// its sends in line and taken, the listener session and the context
    /// it had of that review's videos, so the listener that comes back
    /// takes up where it was. A review that has its own outbox already
    /// keeps it. The old file is deleted once every part is written. One
    /// that doesn't read, or a newer build's, is left as it is: each
    /// review's outbox puts its unfinished sends back in line all the same.
    public func migrateFormerOutbox() {
        let file = layout.formerOutboxFile
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let former: Outbox
        do throws(Failure) {
            let kept: Kept<Outbox> = try read(file)
            former = kept.content
        } catch {
            return
        }
        var keys: [ReviewKey] = []
        for ref in former.pending + former.taken {
            let key = ref.review
            if !keys.contains(key) { keys.append(key) }
        }
        for key in keys where !FileManager.default.fileExists(atPath: layout.outboxFile(key).path) {
            do throws(Failure) {
                try write(Kept(content: former.part(for: key)), to: layout.outboxFile(key))
            } catch {
                // Tried again on the next launch; nothing is lost meanwhile.
                return
            }
        }
        try? FileManager.default.removeItem(at: file)
    }

    // MARK: - Recent videos

    /// How many recent videos are kept.
    public static let recentLimit = 10

    private struct Recents: Codable {
        var videos: [RecentVideo]
        /// When each project was last opened, by slug: the most recently
        /// used project opens a video two projects list (decision C4).
        var projects: [String: Date]?
    }

    /// The last open video, as `recent.json` kept it before the list.
    private struct FormerRecent: Codable {
        var path: String
    }

    /// The recent videos, the newest first, as the last save left them;
    /// nil until the first read.
    private var recentList: [RecentVideo]?
    /// When each project was last opened, as the last save left it.
    private var projectUses: [String: Date] = [:]
    /// Whether `recents.json` is a newer build's, which is left as it is.
    private var recentsAreNewer = false

    /// The recent videos, the newest first: at most `recentLimit`. Empty
    /// when there are none, or `recents.json` doesn't read. The first read
    /// on a folder with only `recent.json` makes its video the one entry
    /// and deletes `recent.json`.
    public func recents() -> [RecentVideo] {
        if let recentList { return recentList }
        var list: [RecentVideo] = []
        let file = layout.recentsFile
        if FileManager.default.fileExists(atPath: file.path) {
            do throws(Failure) {
                let kept: Kept<Recents> = try read(file)
                list = Array(kept.content.videos.prefix(Self.recentLimit))
                projectUses = kept.content.projects ?? [:]
            } catch {
                recentsAreNewer = isNewer(file)
            }
        } else {
            list = migrateFormerRecent()
        }
        recentList = list
        return list
    }

    /// Puts `video` first on the recent videos, opened at `time`. A video
    /// already on the list, by its content, moves to the front with its new
    /// path and keeps its position. It's a convenience: when it can't be
    /// written, the list stays as it was on disk.
    public func recordOpened(_ video: URL, contentHash: String, at time: Date) {
        var list = recents()
        let position = list.first { $0.contentHash == contentHash }?.position ?? 0
        list.removeAll { $0.contentHash == contentHash }
        list.insert(RecentVideo(path: video.path, contentHash: contentHash, openedAt: time, position: position), at: 0)
        saveRecents(Array(list.prefix(Self.recentLimit)))
    }

    /// Keeps `seconds` as the last position of the recent video with
    /// `contentHash`. A video not on the list saves nothing.
    public func savePosition(_ seconds: Double, of contentHash: String) {
        var list = recents()
        guard let index = list.firstIndex(where: { $0.contentHash == contentHash }), list[index].position != seconds else { return }
        list[index].position = seconds
        saveRecents(list)
    }

    /// Takes the video with `contentHash` off the recent videos. Its review
    /// stays on disk.
    public func removeRecent(_ contentHash: String) {
        let list = recents()
        guard list.contains(where: { $0.contentHash == contentHash }) else { return }
        saveRecents(list.filter { $0.contentHash != contentHash })
    }

    private func saveRecents(_ list: [RecentVideo]) {
        guard !recentsAreNewer else { return }
        recentList = list
        try? write(Kept(content: Recents(videos: list, projects: projectUses.isEmpty ? nil : projectUses)), to: layout.recentsFile)
    }

    // MARK: - Projects used

    /// When each project was last opened, by slug. Empty when none was,
    /// or `recents.json` doesn't read.
    public func projectsUsed() -> [String: Date] {
        _ = recents()
        return projectUses
    }

    /// The project `slug` was opened at `time`. A convenience, as the
    /// recent videos are: when it can't be written, it's only lost.
    public func recordProjectOpened(_ slug: String, at time: Date) {
        let list = recents()
        projectUses[slug] = time
        saveRecents(list)
    }

    /// The one entry `recent.json` gives, then `recent.json` deleted. Its
    /// content hash is the one of the review that records its path, else
    /// the file's own; a video that's neither gives no entry. A newer
    /// build's file is left as it is.
    private func migrateFormerRecent() -> [RecentVideo] {
        let file = layout.formerRecentFile
        guard FileManager.default.fileExists(atPath: file.path), !isNewer(file) else { return [] }
        var list: [RecentVideo] = []
        if let kept: Kept<FormerRecent> = try? read(file), kept.content.path.hasPrefix("/"),
           let hash = paths[kept.content.path] ?? Self.hashOfFile(at: kept.content.path) {
            let opened = (try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate]) as? Date
            list = [RecentVideo(path: kept.content.path, contentHash: hash, openedAt: opened ?? Date(), position: 0)]
            do throws(Failure) {
                try write(Kept(content: Recents(videos: list)), to: layout.recentsFile)
            } catch {
                // Read again next time.
                return list
            }
        }
        try? FileManager.default.removeItem(at: file)
        return list
    }

    private static func hashOfFile(at path: String) -> String? {
        #if canImport(CryptoKit)
        ContentHash.of(URL(fileURLWithPath: path))
        #else
        nil
        #endif
    }

    // MARK: - Files

    /// A file's content with the schema version beside its own keys:
    ///
    ///     { "schemaVersion": 1, "video": { … }, "threads": [ … ], … }
    private struct Kept<Content: Codable>: Codable {
        var schemaVersion = Library.schemaVersion
        var content: Content

        init(content: Content) {
            self.content = content
        }

        private enum CodingKeys: String, CodingKey {
            case schemaVersion
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
            guard schemaVersion <= Library.schemaVersion else { throw Newer(version: schemaVersion) }
            content = try Content(from: decoder)
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(schemaVersion, forKey: .schemaVersion)
            try content.encode(to: encoder)
        }
    }

    private struct Newer: Error {
        var version: Int
    }

    private struct Versioned: Decodable {
        var schemaVersion: Int?
    }

    /// Whether the file at `file` says a newer build wrote it.
    private func isNewer(_ file: URL) -> Bool {
        guard let data = try? Data(contentsOf: file), let versioned = try? Self.decoder.decode(Versioned.self, from: data)
        else { return false }
        return (versioned.schemaVersion ?? 1) > Self.schemaVersion
    }

    private func read<Content: Codable>(_ file: URL) throws(Failure) -> Kept<Content> {
        do {
            return try Self.decoder.decode(Kept<Content>.self, from: try Data(contentsOf: file))
        } catch let newer as Newer {
            throw Failure(reason:
                "\(file.path) is from a newer version of the app (schema \(newer.version), this one reads \(Self.schemaVersion)); "
                    + "it's left as it is")
        } catch {
            throw Failure(reason: "\(file.path) doesn't read (\(Self.words(of: error))); it's left as it is")
        }
    }

    private func write<Content: Codable>(_ kept: Kept<Content>, to file: URL) throws(Failure) {
        do {
            let data = try Self.encoder.encode(kept)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            // To a temporary file, then renamed over the old one.
            try data.write(to: file, options: .atomic)
        } catch {
            throw Failure(reason: "couldn't write \(file.path): \(Self.words(of: error))")
        }
    }

    private static func words(of error: any Error) -> String {
        switch error {
        case DecodingError.keyNotFound(let key, _): "no `\(key.stringValue)`"
        case DecodingError.dataCorrupted(let context), DecodingError.typeMismatch(_, let context),
             DecodingError.valueNotFound(_, let context):
            context.debugDescription
        default: error.localizedDescription
        }
    }

    /// Times are written as ISO 8601 with milliseconds, so a person can
    /// read the files.
    private static let timeStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(timeStyle))
        }
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = try? timeStyle.parse(text) { return date }
            if let date = try? Date.ISO8601FormatStyle().parse(text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "`\(text)` isn't a time"))
        }
        return decoder
    }
}
