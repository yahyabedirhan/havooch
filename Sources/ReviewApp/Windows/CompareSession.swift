import ReviewWire

/// A comparison of two versions of a project (E11, compare-control V4),
/// as words and numbers: which version is on each side, the layout, the
/// side Flip shows, the slider's place and the side picker open in the
/// popover. Pure, so the rules are tested without a window or a player:
/// it opens on the previous version and the one on screen, and picking
/// the version on the other side swaps the sides, so a version is never
/// compared with itself.
nonisolated struct CompareSession: Equatable {
    /// The popover is open and the person chooses, or the window compares.
    enum Phase: String, Equatable {
        case choosing, comparing
    }

    /// One side's version picker in the popover: its side, and its search
    /// and highlight as the switcher's picker has them.
    struct SidePicker: Equatable {
        var side: CompareSide
        var picker = VersionPicker()
    }

    var phase: Phase = .choosing
    /// The version on the left, from 1.
    private(set) var left: Int
    /// The version on the right, from 1; never the left one.
    private(set) var right: Int
    var layout: CompareLayout = .sideBySide
    /// Flip: the side showing. Flip starts on the left, A.
    var showing: CompareSide = .left
    /// Slider: how much of the picture's width shows the left side.
    private(set) var slider = 0.5
    /// The side picker open in the popover; nil while none is.
    var picker: SidePicker?

    /// The comparison the Compare button opens on a project of `count`
    /// versions with `onScreen` on screen: the previous version on the
    /// left and the one on screen on the right. With v1 on screen, v1 and
    /// v2; with a removed version on screen, the last two. Nil for a
    /// project of fewer than two versions, which has nothing to compare.
    static func opening(versions count: Int, onScreen: Int?) -> CompareSession? {
        guard count >= 2 else { return nil }
        let current = onScreen.flatMap { (1...count).contains($0) ? $0 : nil } ?? count
        return current == 1 ? CompareSession(left: 1, right: 2) : CompareSession(left: current - 1, right: current)
    }

    private init(left: Int, right: Int) {
        self.left = left
        self.right = right
    }

    /// The version on `side`.
    func number(_ side: CompareSide) -> Int {
        side == .left ? left : right
    }

    /// The side `number` is on; nil for a version on neither.
    func side(of number: Int) -> CompareSide? {
        if number == left { return .left }
        if number == right { return .right }
        return nil
    }

    /// `side` shows the version `number`. The version on the other side
    /// swaps the sides. The open picker closes.
    mutating func pick(_ number: Int, for side: CompareSide) {
        picker = nil
        if number == self.number(side.other) {
            swap()
        } else if side == .left {
            left = number
        } else {
            right = number
        }
    }

    /// Left and right exchange their versions; the slider keeps its place.
    mutating func swap() {
        (left, right) = (right, left)
    }

    /// The slider at `fraction` of the width, kept from 0 to 1.
    mutating func slide(to fraction: Double) {
        guard fraction.isFinite else { return }
        slider = min(max(fraction, 0), 1)
    }

    /// The name a side goes by in `layout`: `A` and `B` in Flip, else
    /// `Left` and `Right`.
    static func name(of side: CompareSide, in layout: CompareLayout) -> String {
        switch (layout, side) {
        case (.flip, .left): "A"
        case (.flip, .right): "B"
        case (_, .left): "Left"
        case (_, .right): "Right"
        }
    }

    /// The popover's action: `Show side by side`, else `Compare`.
    var action: String { layout == .sideBySide ? "Show side by side" : "Compare" }

    /// The layout as the person reads it: `Side by side`, `Flip`, `Slider`.
    static func words(_ layout: CompareLayout) -> String {
        switch layout {
        case .sideBySide: "Side by side"
        case .flip: "Flip"
        case .slider: "Slider"
        }
    }

    /// The SF Symbol of `layout`, as compare-control V4 draws it.
    static func symbol(_ layout: CompareLayout) -> String {
        switch layout {
        case .sideBySide: "rectangle.split.2x1"
        case .flip: "rectangle.on.rectangle"
        case .slider: "slider.horizontal.below.rectangle"
        }
    }
}
