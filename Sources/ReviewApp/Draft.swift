import ReviewCore

extension WindowModel {
    struct Draft: Equatable {
        var time: Double
        var text: String
        var region: Region?
    }

    enum PopoverClose: Equatable {
        case clickOutside
        case discard
        case momentChanged
    }

    struct FrameMark: Equatable {
        var thread: ThreadID
        var number: Int
        var state: MessageState
        var regions: [Region]
    }
}
