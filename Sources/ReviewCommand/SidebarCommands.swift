import ReviewWire

/// `havooch sidebar show [threads | thread <thread> | connect] | hide`: the
/// sidebar and its views. `show` alone shows the sidebar, as the header
/// control does; with a view it shows that view in it, as the person's
/// clicks do.
enum SidebarCommands {
    static let commands: [Command] = [
        Command(
            name: "sidebar show", synopsis: "sidebar show [threads | thread <thread> | connect]",
            summary: "show the sidebar, as the header control does; threads shows the thread list, as Back in a thread view does; thread shows a thread's view (an id, or a number of the open video), as a click on its row does, and the player pauses on its frame; connect shows the Connect view, as the header's connect button does"
        ) { arguments, _ throws(UsageError) in
            guard let view = arguments.words.first else { return .send(.sidebarVisibility(show: true)) }
            switch view {
            case "threads":
                _ = try arguments.exactly(["threads"])
                return .send(.threadList)
            case "thread":
                let words = try arguments.exactly(["thread", "<thread>"])
                return .send(.threadShow(thread: words[1]))
            case "connect":
                _ = try arguments.exactly(["connect"])
                return .send(.connectShow)
            default:
                throw UsageError("no view `\(view)`; write threads, thread <thread> or connect")
            }
        }.onAWindow(),
        Command(name: "sidebar hide", synopsis: "sidebar hide", summary: "hide the sidebar, as the header control does") {
            arguments, _ throws(UsageError) in
            try arguments.none()
            return .send(.sidebarVisibility(show: false))
        }.onAWindow(),
    ]
}
