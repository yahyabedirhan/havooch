import Foundation
import ReviewLease
import ReviewWire
import Testing

@Suite("The first-run requests")
struct FirstRunRequestTests {
    static let holder = Holder(key: "CLAUDE_CODE_SESSION_ID=abc", name: "Claude Code", place: "/Users/me/shop")
    static let requests: [ControlRequest] = [
        .firstRunShow(), .firstRunShow(step: "connect"), .firstRunNext, .firstRunBack, .firstRunPick(harness: "codex"),
        .firstRunDemo, .firstRunSkip, .screenshot(path: "/tmp/first-run.png", appearance: .dark, window: .firstRun),
    ]

    @Test("each first-run request reads back as it was sent", arguments: requests, [false, true])
    func roundTrip(request: ControlRequest, json: Bool) throws {
        let message = ControlMessage(request, holder: Self.holder, json: json)
        #expect(try ControlMessage.decode(message.encoded()) == message)
    }

    @Test("each first-run request takes the lease, as the person's click is theirs, and none is held")
    func roles() {
        for request in Self.requests {
            #expect(request.role == .operator)
            #expect(request.holdSeconds == 0)
        }
    }
}
