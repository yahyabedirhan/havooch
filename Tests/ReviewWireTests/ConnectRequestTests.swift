import Foundation
import ReviewLease
import ReviewWire
import Testing

@Suite("The connect requests")
struct ConnectRequestTests {
    static let holder = Holder(key: "CLAUDE_CODE_SESSION_ID=abc", name: "Claude Code", place: "/Users/me/shop")

    @Test("connect show, pick, disconnect and forget read back as they were sent", arguments: [
        ControlRequest.connectShow, .connectPick(harness: "codex"), .connectDisconnect, .connectForget,
    ], [false, true])
    func roundTrip(request: ControlRequest, json: Bool) throws {
        let message = ControlMessage(request, holder: Self.holder, json: json)
        #expect(try ControlMessage.decode(message.encoded()) == message)
    }

    @Test("each connect request takes the lease, as the person's click is theirs, and none is held")
    func roles() {
        for request in [ControlRequest.connectShow, .connectPick(harness: "pi"), .connectDisconnect, .connectForget] {
            #expect(request.role == .operator)
            #expect(request.holdSeconds == 0)
        }
    }
}
