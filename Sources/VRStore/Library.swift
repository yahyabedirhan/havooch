import Foundation

/// The support folder as the app keeps things in it: where each file is, and
/// the numbers ids are made from.
///
///     index.json                          the next comment and batch numbers
///     videos/<contentHash>/frames/<id>.png   a comment's keyframe
///     videos/<contentHash>/crops/<id>.png    the crop of a comment's region
public struct Library: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// The next comment id: `c1`, `c2`, … across every video of this
    /// library, so an id names one comment wherever it's used. The number is
    /// kept in `index.json`; an id given out is never given again, also when
    /// its comment was dropped.
    public func nextCommentID() throws -> String {
        var index = try JSONFile.read(Index.self, at: indexFile) ?? Index()
        let id = "c\(index.nextComment)"
        index.nextComment += 1
        try JSONFile.write(index, to: indexFile)
        return id
    }

    /// The next batch id: `b1`, `b2`, … across every video of this library,
    /// kept as the comment numbers are.
    public func nextBatchID() throws -> String {
        var index = try JSONFile.read(Index.self, at: indexFile) ?? Index()
        let id = "b\(index.nextBatch)"
        index.nextBatch += 1
        try JSONFile.write(index, to: indexFile)
        return id
    }

    /// Where the keyframe of the comment `comment` on the video `hash` is.
    public func keyframeURL(_ hash: String, comment: String) -> URL {
        image("frames", hash, comment: comment)
    }

    /// Where the crop of the region of the comment `comment` on the video
    /// `hash` is.
    public func cropURL(_ hash: String, comment: String) -> URL {
        image("crops", hash, comment: comment)
    }

    private func image(_ folder: String, _ hash: String, comment: String) -> URL {
        root
            .appendingPathComponent("videos", isDirectory: true)
            .appendingPathComponent(hash, isDirectory: true)
            .appendingPathComponent(folder, isDirectory: true)
            .appendingPathComponent(comment + ".png")
    }

    private var indexFile: URL {
        root.appendingPathComponent("index.json")
    }

    private struct Index: Codable {
        var nextComment = 1
        var nextBatch = 1

        init() {}

        /// An index written before batches were numbered has no batch number.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            nextComment = try container.decodeIfPresent(Int.self, forKey: .nextComment) ?? 1
            nextBatch = try container.decodeIfPresent(Int.self, forKey: .nextBatch) ?? 1
        }
    }
}
