import Foundation
import ReviewLease
import ReviewWire
import Testing

@Suite("The tour requests")
struct TourRequestTests {
    static let holder = Holder(key: "CLAUDE_CODE_SESSION_ID=abc", name: "Claude Code", place: "/Users/me/shop")
    static let requests = [ControlRequest.tourShow, .tourNext, .tourSkip, .tourClose]

    @Test("tour show, next, skip and close read back as they were sent", arguments: requests, [false, true])
    func roundTrip(request: ControlRequest, json: Bool) throws {
        let message = ControlMessage(request, holder: Self.holder, json: json)
        #expect(try ControlMessage.decode(message.encoded()) == message)
    }

    @Test("each tour request takes the lease, as the person's click is theirs, and none is held")
    func roles() {
        for request in Self.requests {
            #expect(request.role == .operator)
            #expect(request.holdSeconds == 0)
        }
    }
}
