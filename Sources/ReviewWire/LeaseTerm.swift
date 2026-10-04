import Foundation

/// A lease held: who holds it, since when and until when. It's data: the
/// reply to `app quit` carries it so a relaunch can hand it over, and the
/// lease's rules (`ControlLease`, in `ReviewLease`) build on it.
public struct LeaseTerm: Codable, Equatable, Sendable {
    public var holder: Holder
    public var taken: Date
    public var ends: Date

    public init(holder: Holder, taken: Date, ends: Date) {
        self.holder = holder
        self.taken = taken
        self.ends = ends
    }
}
