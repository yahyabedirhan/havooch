import ReviewCore

extension AppModel {
    /// The message still in the popover: view state only, never kept. It
    /// has a frame time, and no id and no keyframe until it's queued.
    struct Draft: Equatable {
        var time: Double
        var text: String
        /// The rectangle the person drew; nil for the whole frame.
        var region: Region?
    }

    /// Why the popover closes, which decides what happens to its words
    /// (D 1.4, D 2.3). A popover with no words only closes, whatever the
    /// reason, and its region goes with it.
    enum PopoverClose: Equatable {
        /// A click anywhere but the popover: the words are queued.
        case clickOutside
        /// The × or Escape: the words are dropped.
        case discard
        /// A seek, a scrub, play, a timeline click, a frame step, another
        /// video: the words are queued at the popover's own frame and
        /// region, not at the new moment.
        case momentChanged
    }

    /// One thread on the frame on screen: its region outlines and its
    /// number badge (D 2.6).
    struct FrameMark: Equatable {
        var thread: ThreadID
        var number: Int
        var state: MessageState
        /// The thread's regions, in the order they were written; empty for
        /// a thread on the whole frame.
        var regions: [Region]
    }
}
