/// One video as a review knows it: what `state` and the batch payload say
/// about it.
public struct VideoInfo: Codable, Equatable, Sendable {
    /// The file's absolute path, as last seen.
    public var path: String
    /// The hash of the file's content, which names the video wherever the
    /// file is moved or however it's renamed.
    public var contentHash: String
    /// In seconds.
    public var duration: Double
    /// The file's base name.
    public var title: String

    public init(path: String, contentHash: String, duration: Double, title: String) {
        self.path = path
        self.contentHash = contentHash
        self.duration = duration
        self.title = title
    }
}
