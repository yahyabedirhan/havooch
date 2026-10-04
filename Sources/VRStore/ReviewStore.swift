import Foundation
import VRReview

/// What the app remembers about itself between two runs.
public struct AppState: Codable, Equatable, Sendable {
    /// The video that was open: the file it was opened from, the hash that
    /// names its history, and where the playhead stood when the app quit.
    public struct LastVideo: Codable, Equatable, Sendable {
        public var path: String
        public var contentHash: String
        public var time: Double

        public init(path: String, contentHash: String, time: Double) {
            self.path = path
            self.contentHash = contentHash
            self.time = time
        }
    }

    public var lastVideo: LastVideo?

    public init(lastVideo: LastVideo? = nil) {
        self.lastVideo = lastVideo
    }
}

/// The reviews, the listener ledger and the app's own state as files under
/// one support folder. Each is one JSON file with a `version`, written
/// whole; one that doesn't read is moved aside and counts as none.
public struct ReviewStore: Sendable {
    private struct ReviewFile: StoredFile {
        static let current = 1
        var version = ReviewFile.current
        var review: Review
    }

    private struct LedgerFile: StoredFile {
        static let current = 1
        var version = LedgerFile.current
        var ledger: ListenerLedger
    }

    private struct AppFile: StoredFile {
        static let current = 1
        var version = AppFile.current
        var lastVideo: AppState.LastVideo?
    }

    public let layout: SupportLayout

    public init(layout: SupportLayout) {
        self.layout = layout
    }

    // MARK: - Reviews

    /// The review kept for the video `hash` names; nil when there is none.
    /// A file that names another video than its folder doesn't read.
    public func loadReview(_ hash: String) -> Review? {
        ReviewFile.read(at: layout.reviewFile(hash)) { $0.review.video.contentHash == hash }?.review
    }

    /// Every review under the support folder, in the order of their hashes.
    public func loadReviews() -> [Review] {
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: layout.videosFolder.path)) ?? []
        return folders.sorted().compactMap(loadReview)
    }

    /// Keeps `review` in its video's folder.
    public func save(_ review: Review) throws {
        try ReviewFile(review: review).write(to: layout.reviewFile(review.video.contentHash))
    }

    // MARK: - The listener ledger

    /// The ledger as it was last kept; an empty one when there is none.
    public func loadLedger() -> ListenerLedger {
        LedgerFile.read(at: layout.listenerFile)?.ledger ?? ListenerLedger()
    }

    public func save(_ ledger: ListenerLedger) throws {
        try LedgerFile(ledger: ledger).write(to: layout.listenerFile)
    }

    // MARK: - The app's own state

    /// What the app last kept about itself; nothing when there is none.
    public func loadAppState() -> AppState {
        AppState(lastVideo: AppFile.read(at: layout.appFile)?.lastVideo)
    }

    public func save(_ state: AppState) throws {
        try AppFile(lastVideo: state.lastVideo).write(to: layout.appFile)
    }
}
