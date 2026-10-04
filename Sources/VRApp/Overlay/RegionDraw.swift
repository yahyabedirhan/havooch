import CoreGraphics
import VRReview

/// A rectangle being drawn on the frame with the pointer, from the press to
/// the release. A value with no view in it: the overlay feeds it the
/// pointer's places in the view, and `AppModel` acts on what it answers.
///
///     idle ── begin ──▶ pressed ── move past the click distance ──▶ drawing
///     pressed ── end ──▶ idle   (a click)
///     drawing ── end ──▶ idle   (a region, or nothing when no frame is under it)
///     pressed, drawing ── cancel ──▶ cancelled ── end ──▶ idle
///
/// A cancelled draw stays cancelled until the button is let go or goes down
/// somewhere else, so the rest of that drag draws nothing.
struct RegionDraw: Equatable {
    /// A press that moves less than this far, in points, is a click.
    static let clickDistance: CGFloat = 8

    enum Phase: Equatable {
        case idle
        case pressed(at: CGPoint)
        case drawing(from: CGPoint, to: CGPoint)
        /// Given up with Escape; `at` is where its press began.
        case cancelled(at: CGPoint)
    }

    /// What a move did.
    enum Step: Equatable {
        case nothing
        /// The press became a rectangle with this move.
        case began
        case moved
    }

    /// What letting the button go ends in.
    enum Outcome: Equatable {
        /// No press was under way, or it was cancelled.
        case nothing
        case click
        case region(Region)
        /// A rectangle was drawn with none of the frame in it.
        case empty
    }

    private(set) var phase = Phase.idle

    /// Whether a rectangle is being drawn now.
    var isDrawing: Bool {
        if case .drawing = phase { return true }
        return false
    }

    /// The button went down at `point`. Told again of the press it already
    /// follows, or of the one that was cancelled, it changes nothing, so a
    /// drag may name its start with every move.
    mutating func begin(at point: CGPoint) {
        switch phase {
        case .pressed(at: point), .drawing(from: point, to: _), .cancelled(at: point): return
        default: phase = .pressed(at: point)
        }
    }

    /// The pointer moved to `point` with the button down.
    mutating func move(to point: CGPoint) -> Step {
        switch phase {
        case .pressed(let start):
            guard hypot(point.x - start.x, point.y - start.y) >= Self.clickDistance else { return .nothing }
            phase = .drawing(from: start, to: point)
            return .began
        case .drawing(let start, _):
            phase = .drawing(from: start, to: point)
            return .moved
        case .idle, .cancelled:
            return .nothing
        }
    }

    /// The button was let go: what was drawn, in the frame as `geometry`
    /// places it.
    mutating func end(in geometry: FrameGeometry) -> Outcome {
        defer { phase = .idle }
        switch phase {
        case .idle, .cancelled: return .nothing
        case .pressed: return .click
        case .drawing(let start, let end): return geometry.region(from: start, to: end).map(Outcome.region) ?? .empty
        }
    }

    /// Escape: gives up the press or the rectangle. Whether there was one.
    mutating func cancel() -> Bool {
        switch phase {
        case .pressed(let start), .drawing(let start, _):
            phase = .cancelled(at: start)
            return true
        case .idle, .cancelled:
            return false
        }
    }

    /// The rectangle as drawn so far: the part of it on the frame.
    func region(in geometry: FrameGeometry) -> Region? {
        guard case .drawing(let start, let end) = phase else { return nil }
        return geometry.region(from: start, to: end)
    }
}
