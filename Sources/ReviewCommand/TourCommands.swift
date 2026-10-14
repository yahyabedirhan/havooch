import Foundation
import ReviewWire

enum TourCommands {
    static let group = CommandGroup(
        name: "tour", summary: "step through the setup tour", section: .drive, commands: [
            Command(
                name: "tour open", summary: "show the setup tour over the stage",
                description: "As Finish setup does, at the step it was left on.", examples: [""], role: .operator
            ) { arguments, _ throws(UsageError) in
                try arguments.none()
                return .send(.tourShow)
            },
            Command(
                name: "tour next", summary: "go to the tour's next step",
                description: "As Next or Later does. After the last step the tour ends, as Finish does.",
                examples: [""], role: .operator
            ) { arguments, _ throws(UsageError) in
                try arguments.none()
                return .send(.tourNext)
            },
            Command(
                name: "tour skip", summary: "end the tour",
                description: "As Skip Tour does. It starts from the first step next time.", examples: [""], role: .operator
            ) { arguments, _ throws(UsageError) in
                try arguments.none()
                return .send(.tourSkip)
            },
            Command(
                name: "tour close", summary: "close the tour's panel",
                description: "As its close button does. The tour keeps its step.", examples: [""], role: .operator
            ) { arguments, _ throws(UsageError) in
                try arguments.none()
                return .send(.tourClose)
            },
        ].map { $0.onAWindow() }
    )
}
