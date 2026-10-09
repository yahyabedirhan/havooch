import Foundation
import ReviewWire

/// `havooch tour show | next | skip | close`: the operator can use the
/// same tour actions as the person uses with "Finish setup" and the tour
/// panel. Write an Example is `comment compose`.
enum TourCommands {
    static let commands: [Command] = [
        Command(
            name: "tour show", synopsis: "tour show",
            summary: "show the setup tour over the stage, as Finish setup does, at the step it was left on"
        ) { arguments, _ throws(UsageError) in
            try arguments.none()
            return .send(.tourShow)
        },
        Command(
            name: "tour next", synopsis: "tour next",
            summary: "go to the tour's next step, as Next or Later does; after the last step the tour ends, as Finish does"
        ) { arguments, _ throws(UsageError) in
            try arguments.none()
            return .send(.tourNext)
        },
        Command(
            name: "tour skip", synopsis: "tour skip",
            summary: "end the tour, as Skip Tour does; it starts from the first step next time"
        ) { arguments, _ throws(UsageError) in
            try arguments.none()
            return .send(.tourSkip)
        },
        Command(
            name: "tour close", synopsis: "tour close",
            summary: "close the tour's panel, as its close button does; it keeps its step"
        ) { arguments, _ throws(UsageError) in
            try arguments.none()
            return .send(.tourClose)
        },
    ]
}
