import Foundation

/// The queue as one send took it: the comments that were queued then, in
/// time order, with the transcript lines around each as they existed at
/// the send.
public struct Batch: Codable, Equatable, Identifiable, Sendable {
    public var id: BatchID
    public var sentAt: Date
    public var comments: [CommentID]
    /// The messages about the batch as a whole.
    public var thread: [ThreadMessage]
    /// Captured at the send, so a later delivery needs neither the video
    /// open nor a transcriber running.
    public var transcripts: [CommentID: [BatchPayload.Line]]

    public init(
        id: BatchID, sentAt: Date, comments: [CommentID], thread: [ThreadMessage] = [],
        transcripts: [CommentID: [BatchPayload.Line]] = [:]
    ) {
        self.id = id
        self.sentAt = sentAt
        self.comments = comments
        self.thread = thread
        self.transcripts = transcripts
    }
}
