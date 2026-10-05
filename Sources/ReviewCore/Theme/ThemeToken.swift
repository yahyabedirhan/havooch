/// Every colour the app draws, by what it means, never by its hue. A view
/// asks for a token; the active theme says which colour it is. A theme file
/// names a token by its raw value.
///
/// A new token is one case here and its value in each default theme file
/// (`Packaging/Themes/`); the test of the shipped themes fails until both
/// defaults have it.
public enum ThemeToken: String, CaseIterable, Codable, Sendable {
    // Surfaces: the whole window is one surface; hairlines and space, not
    // background colours, separate its parts.

    /// The one surface of the window: the header, the stage, the player
    /// bar, the sidebar and its footer.
    case window
    /// The bars beside the video in its frame.
    case letterbox
    /// A popover or a notice floating over the video.
    case popover
    /// The thin edge of a popover, so it stays apart from a video of the
    /// same colour.
    case popoverBorder
    /// A text field.
    case field
    /// A part set apart on a surface: the lease's details in a popover,
    /// the sidebar row of the thread on the stage.
    case well
    /// The timeline's track.
    case track
    /// The timeline's playhead knob.
    case knob
    /// The shadow under a floating surface.
    case shadow
    /// A symbol button or a sidebar row under the pointer.
    case controlHover
    /// A symbol button being pressed.
    case controlPressed

    // Text.

    case textPrimary
    case textSecondary
    case textTertiary
    /// Text and glyphs drawn on a filled accent or state colour.
    case textOnAccent

    // Accent.

    /// The app's accent: the scrubber, a selection, a focused field, Send.
    case accent
    /// The agent-control icon while an agent holds the lease.
    case control
    /// A hairline between two parts of the one surface: the stage and the
    /// sidebar, the threads and the footer.
    case separator

    // Messages.

    /// The person's avatar.
    case person
    /// The agent's avatar and its notices.
    case agent
    /// An open question: on its pin, its message and its notice.
    case question
    case bubblePerson
    case bubbleAgent
    case bubbleQuestion

    // The frame.

    case regionOutline
    /// The frame outside a region.
    case regionDim
    case badge
    case badgeText
    case sizeLabel

    // Message states, on pins, rows and badges.

    case stateQueued
    case stateSent
    case stateAcknowledged
    case stateWorking
    case stateDone
    case stateFailed

    // The listener's presence, in the footer.

    case presenceListening
    case presenceWorking
    case presenceAbsent

    // Notices.

    case notice
    case noticeText
}
