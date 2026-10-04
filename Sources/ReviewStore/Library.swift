import Foundation
import ReviewCore

/// What the app keeps between runs, under the one support folder it's
/// given: the person's own, or a demo's. It never looks outside that
/// folder, so demo data and real data can't mix.
///
///     <support>/outbox.json                    the batches in line for the listener
///     <support>/recent.json                    the path of the last open video
///     <support>/videos/<contentHash>/review.json   one video's review
///
/// A video's folder is named after the hash of its content, so a renamed or
/// moved file finds its review again. Every save writes the whole file to a
/// temporary one and renames it over the old one: a reader, and a run that
/// ends half way, see the old file or the new one, never a part of one.
///
/// A file that doesn't read, or that a newer build wrote, is never written
/// over: its video's history isn't opened, and the reason is given.
///
/// One per support folder, used on the main actor.
public final class Library {
    public let support: URL

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

    /// The video of each comment and batch on disk, by its id: a listener's
    /// command names an item and no video.
    private var index: [ItemID: String] = [:]
    /// The batches on disk with a comment the listener hasn't finished, in
    /// the order they were sent, as the reviews read at launch.
    private var unfinished: [BatchRef] = []
    /// Whether `outbox.json` is a newer build's, which is left as it is.
    private var outboxIsNewer = false

    /// Reads every review under `support` once, for the ids in it. Nothing
    /// is written.
    public init(support: URL) {
        self.support = support
        var sent: [(Date, BatchRef)] = []
        let folders = (try? FileManager.default.contentsOfDirectory(at: videos, includingPropertiesForKeys: nil)) ?? []
        for folder in folders {
            // A review that doesn't read stays out; opening its video says why.
            guard let review = try? load(folder.lastPathComponent) else { continue }
            note(review)
            for batch in review.batches where !review.isFinished(batch.id) {
                sent.append((batch.sentAt, BatchRef(batchID: batch.id, contentHash: review.video.contentHash)))
            }
        }
        unfinished = sent.sorted { $0.0 < $1.0 }.map(\.1)
    }

    // MARK: - Where the files are

    private var videos: URL { support.appendingPathComponent("videos", isDirectory: true) }

    /// The review file of the video with `contentHash`.
    public func reviewFile(of contentHash: String) -> URL {
        videos.appendingPathComponent(contentHash, isDirectory: true).appendingPathComponent("review.json")
    }

    public var outboxFile: URL { support.appendingPathComponent("outbox.json") }
    public var recentFile: URL { support.appendingPathComponent("recent.json") }

    // MARK: - Reviews

    /// The content hash of the video whose review has the comment or the
    /// batch `id`; nil when no review on disk has it.
    public func contentHash(of id: ItemID) -> String? {
        index[id]
    }

    /// The review kept for the video with `contentHash`; nil when there's
    /// none yet. Throws when there is a file and it doesn't read, or a
    /// newer build wrote it: that file must not be written over.
    public func load(_ contentHash: String) throws(Failure) -> VideoReview? {
        let file = reviewFile(of: contentHash)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let kept: Kept<VideoReview> = try read(file)
        // A folder that was copied or renamed by hand isn't that video's.
        guard kept.content.video.contentHash == contentHash else {
            throw Failure(reason: "\(file.path) is the review of another video (\(kept.content.video.contentHash))")
        }
        return kept.content
    }

    /// Keeps `review`, replacing its video's file.
    public func save(_ review: VideoReview) throws(Failure) {
        try write(Kept(content: review), to: reviewFile(of: review.video.contentHash))
        let hash = review.video.contentHash
        index = index.filter { $0.value != hash }
        note(review)
    }

    private func note(_ review: VideoReview) {
        for comment in review.comments { index[comment.id] = review.video.contentHash }
        for batch in review.batches { index[batch.id] = review.video.contentHash }
    }

    // MARK: - The outbox

    /// The outbox as the last run left it, made to agree with the reviews
    /// on disk (`Outbox.reconcile`): with no file, or one that doesn't
    /// read, every unfinished batch is in line again, so no feedback is
    /// lost with the file.
    public func loadOutbox() -> Outbox {
        var outbox = Outbox()
        if FileManager.default.fileExists(atPath: outboxFile.path) {
            do throws(Failure) {
                let kept: Kept<Outbox> = try read(outboxFile)
                outbox = kept.content
            } catch {
                outboxIsNewer = isNewer(outboxFile)
            }
        }
        outbox.reconcile(unfinished: unfinished)
        return outbox
    }

    /// Keeps `outbox`. A newer build's file is left as it is.
    public func save(_ outbox: Outbox) throws(Failure) {
        guard !outboxIsNewer else { throw Failure(reason: "\(outboxFile.path) is from a newer version of the app") }
        try write(Kept(content: outbox), to: outboxFile)
    }

    // MARK: - The last open video

    private struct Recent: Codable {
        var path: String
    }

    /// The path of the video that was open last; nil when there's none, or
    /// the file doesn't read.
    public func recent() -> URL? {
        guard FileManager.default.fileExists(atPath: recentFile.path),
              let kept: Kept<Recent> = try? read(recentFile), kept.content.path.hasPrefix("/")
        else { return nil }
        return URL(fileURLWithPath: kept.content.path)
    }

    /// Remembers `video` as the last open one. It's a convenience: when it
    /// can't be written, the next launch opens no video.
    public func saveRecent(_ video: URL) {
        guard !isNewer(recentFile) else { return }
        try? write(Kept(content: Recent(path: video.path)), to: recentFile)
    }

    // MARK: - Files

    /// A file's content with the schema version beside its own keys:
    ///
    ///     { "schemaVersion": 1, "video": { … }, "comments": [ … ], … }
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
