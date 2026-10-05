import Foundation

/// One comment on a video: text at a time, on the whole frame or on a
/// region of it. Its keyframe and its crop are files named after its id, so
/// the comment holds no path.
public struct Comment: Codable, Equatable, Sendable, Identifiable {
    public let id: ItemID
    /// The moment in the video, in seconds.
    public let time: TimeInterval
    public internal(set) var text: String
    public internal(set) var state: CommentState
    /// The part of the frame the comment points at; nil for the whole frame.
    public let region: Region?
    /// The batch the comment was sent in; nil while it's queued.
    public internal(set) var batchID: ItemID?
    /// What the agent said on the comment and what the person answered, in
    /// the order written.
    public internal(set) var thread: [ThreadMessage] = []

    /// The agent's question that waits for the person's answer; nil when
    /// there's none. A comment has one at most.
    public var openQuestion: ThreadMessage? { thread.openQuestion }
}

extension Comment {
    /// A comment written before it had a thread reads with an empty one.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ItemID.self, forKey: .id)
        time = try container.decode(TimeInterval.self, forKey: .time)
        text = try container.decode(String.self, forKey: .text)
        state = try container.decode(CommentState.self, forKey: .state)
        region = try container.decodeIfPresent(Region.self, forKey: .region)
        batchID = try container.decodeIfPresent(ItemID.self, forKey: .batchID)
        thread = try container.decodeIfPresent([ThreadMessage].self, forKey: .thread) ?? []
    }
}

/// A rectangle on the video's frame, in normalized coordinates: 0 to 1 from
/// the top-left corner of the displayed frame, whatever the size the video
/// is shown at. A `Region` is always inside the frame and has an area.
public struct Region: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let w: Double
    public let h: Double

    /// Refuses a value outside 0 to 1, a rectangle that leaves the frame
    /// and a width or height of 0.
    public init(x: Double, y: Double, w: Double, h: Double) throws(ReviewRefusal) {
        let values = [x, y, w, h]
        guard values.allSatisfy({ $0.isFinite && (0...1).contains($0) }), w > 0, h > 0,
              x + w <= 1 + Self.slack, y + h <= 1 + Self.slack
        else { throw .badRegion(x: x, y: y, w: w, h: h) }
        (self.x, self.y, self.w, self.h) = (x, y, w, h)
    }

    /// What a sum of two decimal fractions may be over 1 by: 0.7 + 0.3
    /// isn't exactly 1 in binary.
    private static let slack = 1e-9

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let values = try [CodingKeys.x, .y, .w, .h].map { try container.decode(Double.self, forKey: $0) }
        do {
            try self.init(x: values[0], y: values[1], w: values[2], h: values[3])
        } catch {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: error.line))
        }
    }

    /// The region as `comment add --region` takes it: `0.25,0.2,0.3,0.25`.
    public var text: String {
        [x, y, w, h].map { "\($0)" }.joined(separator: ",")
    }

    /// The region's pixels in a picture `width` by `height`: whole pixels,
    /// at least one each way, inside the picture.
    public func pixels(width: Int, height: Int) -> (x: Int, y: Int, width: Int, height: Int) {
        func span(_ start: Double, _ length: Double, _ size: Int) -> (Int, Int) {
            let first = min(max(Int((start * Double(size)).rounded()), 0), max(size - 1, 0))
            let end = min(max(Int(((start + length) * Double(size)).rounded()), first + 1), max(size, first + 1))
            return (first, end - first)
        }
        let (left, wide) = span(x, w, width)
        let (top, high) = span(y, h, height)
        return (left, top, wide, high)
    }
}
