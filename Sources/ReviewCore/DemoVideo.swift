/// The demo video bundled in the app (`fixtures/launch/havooch-demo.mp4`,
/// copied into `Contents/Resources/Demo/` by `make bundle`), known by its
/// content wherever the file is: a send on it is marked `video.demo`, and
/// the `havooch-mate` skill reads its demo reference only then.
public enum DemoVideo {
    /// The SHA-256 of the bundled demo video. A test checks it against the
    /// fixture, so a new demo video changes it here too.
    public static let contentHash = "240636ae00688e7d163a74d37047e7b9cbf7b75ac04a1aa35cee5b51288ecd64"
}
