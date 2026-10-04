/// Whether a listener is there for a batch: waiting for one (`listening`),
/// busy with one it took (`working`), or not there (`absent`). It is
/// derived (`ListenerLedger.presence`), never stored.
public enum Presence: String, Codable, Sendable {
    case listening, working, absent
}
