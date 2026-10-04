/// The lease as `app status` and `state` report it: who holds app control,
/// where they run, how long is left and how many wait.
public struct LeaseStatus: Codable, Equatable, Sendable {
    /// The holder's name (`Claude Code`).
    public var holder: String
    /// Where the holder runs: `Herdr pane <id>`, or its working folder.
    public var place: String
    public var secondsLeft: Int
    public var waiting: Int

    public init(holder: String, place: String, secondsLeft: Int, waiting: Int) {
        self.holder = holder
        self.place = place
        self.secondsLeft = secondsLeft
        self.waiting = waiting
    }
}
