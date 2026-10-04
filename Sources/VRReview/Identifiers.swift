/// The name of one comment: the first eight hex digits of its video's
/// content hash, then a counter per video (`7f3a9c21-c3`). An id names its
/// video, so a command finds its comment whatever video is open. A number
/// is never used twice.
public struct CommentID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// The id of the comment numbered `number` on the video `contentHash` names.
    public init(contentHash: String, number: Int) {
        rawValue = "\(contentHash.prefix(VideoPrefix.length))-c\(number)"
    }
}

/// The name of one batch, made as a comment's is: `7f3a9c21-b1`.
public struct BatchID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// The id of the batch numbered `number` on the video `contentHash` names.
    public init(contentHash: String, number: Int) {
        rawValue = "\(contentHash.prefix(VideoPrefix.length))-b\(number)"
    }

    /// The batch's number on its video: the 1 of `7f3a9c21-b1`.
    public var number: Int? {
        rawValue.range(of: "-b", options: .backwards).flatMap { Int(rawValue[$0.upperBound...]) }
    }
}

/// How much of a video's content hash its comments' and batches' ids carry.
public enum VideoPrefix {
    public static let length = 8
}
