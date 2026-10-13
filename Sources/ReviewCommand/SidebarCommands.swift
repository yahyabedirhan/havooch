import ReviewWire

/// `havooch sidebar show [threads | thread <thread> | connect] | hide`: the
/// sidebar and its views. `show` alone shows the sidebar, as the header
/// control does; with a view it shows that view in it, as the person's
/// clicks do.
enum SidebarCommands {
    static let group = CommandGroup(
        name: "sidebar", summary: "show the sidebar's views", section: .drive, commands: [
            Command(
                name: "sidebar show", arguments: "[threads | thread <thread> | connect]",
                summary: "show the sidebar, or one of its views",
                description: "Alone, it shows the sidebar, as the header control does. threads shows the thread list, as Back "
                    + "in a thread view does. thread shows a thread's view, as a click on its row does, and the player pauses "
                    + "on its frame; the thread is its id, or its number in the open video. connect shows the Connect view, "
                    + "as the header's connect button does.",
                examples: ["", "threads", "thread 2", "connect"], role: .operator
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
            },
            Command(
                name: "sidebar hide", summary: "hide the sidebar",
                description: "As the header control does.", examples: [""], role: .operator
            ) { arguments, _ throws(UsageError) in
                try arguments.none()
                return .send(.sidebarVisibility(show: false))
            },
        ].map { $0.onAWindow() }
    )
}
