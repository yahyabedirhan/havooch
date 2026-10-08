import Foundation
import ReviewLease
import ReviewWire
import Testing

@Suite("The setup requests")
struct SetupRequestTests {
    static let holder = Holder(key: "CLAUDE_CODE_SESSION_ID=abc", name: "Claude Code", place: "/Users/me/shop")

    @Test("setup status, link, install and cancel read back as they were sent", arguments: [
        ControlRequest.setupStatus, .setupLink(), .setupLink(dryRun: true), .setupInstall(),
        .setupInstall(harnesses: ["codex", "pi"], dryRun: true), .setupCancel,
    ], [false, true])
    func roundTrip(request: ControlRequest, json: Bool) throws {
        let message = ControlMessage(request, holder: Self.holder, json: json)
        #expect(try ControlMessage.decode(message.encoded()) == message)
    }

    @Test("setup status is free; link, install and cancel take the lease, and none is held")
    func roles() {
        #expect(ControlRequest.setupStatus.role == .free)
        for request in [ControlRequest.setupLink(), .setupInstall(), .setupCancel] {
            #expect(request.role == .operator)
            #expect(request.holdSeconds == 0)
        }
    }
}
