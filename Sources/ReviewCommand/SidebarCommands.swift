import ReviewWire

/// The visibility control in the player's header, through app control.
enum SidebarCommands {
    static let commands: [Command] = [
        Command(name: "sidebar show", synopsis: "sidebar show", summary: "show the sidebar, as the header control does") {
            arguments, _ throws(UsageError) in
            try arguments.none()
            return .send(.sidebarVisibility(show: true))
        }.onAWindow(),
        Command(name: "sidebar hide", synopsis: "sidebar hide", summary: "hide the sidebar, as the header control does") {
            arguments, _ throws(UsageError) in
            try arguments.none()
            return .send(.sidebarVisibility(show: false))
        }.onAWindow(),
    ]
}
