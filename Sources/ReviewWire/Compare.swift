/// A side of a comparison of two versions (E11): the left one and the
/// right one. The app and the command share these names.
public enum CompareSide: String, CaseIterable, Codable, Equatable, Sendable {
    case left, right

    /// The side across from this one.
    public var other: CompareSide { self == .left ? .right : .left }
}

/// How two versions are compared (E11, compare-control V4): side by side,
/// flipped one over the other with a key, or wiped with a slider.
public enum CompareLayout: String, CaseIterable, Codable, Equatable, Sendable {
    case sideBySide = "side-by-side"
    case flip
    case slider
}

/// `havooch compare set`: what changes in the comparison, in the popover
/// or on the stage. Each field left nil stays as it is.
public struct CompareChange: Equatable, Sendable {
    /// The version on the left, from 1; the right one's swaps the sides.
    public var left: Int?
    /// The version on the right, from 1; the left one's swaps the sides.
    public var right: Int?
    public var layout: CompareLayout?
    /// The side new messages go to, as a click on it picks it; in Flip
    /// the side showing.
    public var side: CompareSide?
    /// Slider: how much of the picture's width shows the left side, from
    /// 0 to 1.
    public var slider: Double?

    public init(left: Int? = nil, right: Int? = nil, layout: CompareLayout? = nil, side: CompareSide? = nil, slider: Double? = nil) {
        self.left = left
        self.right = right
        self.layout = layout
        self.side = side
        self.slider = slider
    }

    /// Whether it changes nothing.
    public var isEmpty: Bool { self == CompareChange() }
}
