/// Every colour the app draws, by what it means, never by its hue. A view
/// asks for a token; the active theme says which colour it is. A theme file
/// names a token by its raw value.
///
/// A new token is one case here and its value in each default theme file
/// (`Packaging/Themes/`); the test of the shipped themes fails until both
/// defaults have it.
public enum ThemeToken: String, CaseIterable, Codable, Sendable {
    // Surfaces: the UI is segmented by these backgrounds, not by borders.

    /// The window behind everything.
    case window
    /// The area around the video.
    case stage
    /// The bars beside the video in its frame.
    case letterbox
    /// The player bar under the stage: transport and timeline.
    case bar
    /// The sidebar of threads.
    case sidebar
    /// A band that heads a part of the sidebar.
    case sidebarSection
    /// A sidebar row under the pointer.
    case sidebarRowHover
    /// The selected sidebar row.
    case sidebarRowSelected
    /// The header above the stage.
    case header
    /// A popover or a notice floating over the video.
    case popover
    /// The thin edge of a popover, so it stays apart from a video of the
    /// same colour.
    case popoverBorder
    /// A text field.
    case field
    /// A part set apart inside a popover, such as the lease's details.
    case well
    /// The timeline's track.
    case track
    /// The timeline's playhead knob.
    case knob
    /// The shadow under a floating surface.
    case shadow
    /// A symbol button under the pointer.
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
    /// A hairline between two parts that share a background.
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
