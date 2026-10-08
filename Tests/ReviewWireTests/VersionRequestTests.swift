import Foundation
import ReviewLease
import ReviewWire
import Testing

@Suite("The version requests")
struct VersionRequestTests {
    static let holder = Holder(key: "CLAUDE_CODE_SESSION_ID=abc", name: "Claude Code", place: "/Users/me/shop")
    static let requests = [ControlRequest.versionShow(number: 12), .versionPick(), .versionPick(query: "alt"), .versionClose]

    @Test("version show, pick and close read back as they were sent", arguments: requests, [false, true])
    func roundTrip(request: ControlRequest, json: Bool) throws {
        let message = ControlMessage(request, holder: Self.holder, json: json, window: "w2")
        #expect(try ControlMessage.decode(message.encoded()) == message)
    }

    @Test("each version request takes the lease, as the person's click is theirs, and none is held")
    func roles() {
        for request in Self.requests {
            #expect(request.role == .operator)
            #expect(request.holdSeconds == 0)
        }
    }

    @Test("version show with no number, or one below 1, is refused", arguments: [nil, 0, -3] as [Int?])
    func badNumber(number: Int?) throws {
        var fields: [String: Any] = [
            "version": Version.controlProtocol, "command": "version.show",
            "holder": ["key": "k", "name": "Claude Code", "place": "/tmp"],
        ]
        if let number { fields["number"] = number }
        let data = try JSONSerialization.data(withJSONObject: fields)
        #expect(throws: ControlProtocolError.self) { try ControlMessage.decode(data) }
    }
}
