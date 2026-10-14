import ReviewWire

nonisolated struct CompareSession: Equatable {
    enum Phase: String, Equatable {
        case choosing, comparing
    }

    struct SidePicker: Equatable {
        var side: CompareSide
        var picker = VersionPicker()
    }

    var phase: Phase = .choosing
    private(set) var left: Int
    private(set) var right: Int
    var layout: CompareLayout = .sideBySide
    var showing: CompareSide = .left
    private(set) var slider = 0.5
    var picker: SidePicker?

    static func opening(versions count: Int, onScreen: Int?) -> CompareSession? {
        guard count >= 2 else { return nil }
        let current = onScreen.flatMap { (1...count).contains($0) ? $0 : nil } ?? count
        return current == 1 ? CompareSession(left: 1, right: 2) : CompareSession(left: current - 1, right: current)
    }

    private init(left: Int, right: Int) {
        self.left = left
        self.right = right
    }

    func number(_ side: CompareSide) -> Int {
        side == .left ? left : right
    }

    func side(of number: Int) -> CompareSide? {
        if number == left { return .left }
        if number == right { return .right }
        return nil
    }

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

    mutating func swap() {
        (left, right) = (right, left)
    }

    mutating func slide(to fraction: Double) {
        guard fraction.isFinite else { return }
        slider = min(max(fraction, 0), 1)
    }

    static func name(of side: CompareSide, in layout: CompareLayout) -> String {
        switch (layout, side) {
        case (.flip, .left): "A"
        case (.flip, .right): "B"
        case (_, .left): "Left"
        case (_, .right): "Right"
        }
    }

    var action: String { layout == .sideBySide ? "Show side by side" : "Compare" }

    static func words(_ layout: CompareLayout) -> String {
        switch layout {
        case .sideBySide: "Side by side"
        case .flip: "Flip"
        case .slider: "Slider"
        }
    }

    static func symbol(_ layout: CompareLayout) -> String {
        switch layout {
        case .sideBySide: "rectangle.split.2x1"
        case .flip: "rectangle.on.rectangle"
        case .slider: "slider.horizontal.below.rectangle"
        }
    }
}
