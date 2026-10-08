import Foundation
import ReviewLease
import ReviewWire
import Testing

@Suite("The compare requests")
struct CompareRequestTests {
    static let holder = Holder(key: "CLAUDE_CODE_SESSION_ID=abc", name: "Claude Code", place: "/Users/me/shop")
    static let requests: [ControlRequest] = [
        .compareOpen, .comparePick(side: .left), .comparePick(side: .right, query: "alt"),
        .compareSet(CompareChange(left: 1)), .compareSet(CompareChange(right: 12, layout: .flip)),
        .compareSet(CompareChange(side: .left, slider: 0.25)), .compareSet(CompareChange(layout: .slider)),
        .compareSwap, .compareStart, .compareExit,
    ]

    @Test("compare open, pick, set, swap, start and exit read back as they were sent", arguments: requests, [false, true])
    func roundTrip(request: ControlRequest, json: Bool) throws {
        let message = ControlMessage(request, holder: Self.holder, json: json, window: "w2")
        #expect(try ControlMessage.decode(message.encoded()) == message)
    }

    @Test("each compare request takes the lease, as the person's click is theirs, and none is held")
    func roles() {
        for request in Self.requests {
            #expect(request.role == .operator)
            #expect(request.holdSeconds == 0)
        }
    }

    @Test("a compare request with a side, a layout, a version or a slider the app can't read is refused", arguments: [
        #""command": "compare.pick""#, #""command": "compare.pick", "side": "middle""#,
        #""command": "compare.set""#, #""command": "compare.set", "left": 0"#, #""command": "compare.set", "layout": "grid""#,
        #""command": "compare.set", "side": "up""#, #""command": "compare.set", "slider": 1.5"#,
    ])
    func unreadable(fields: String) throws {
        let json = #"{"version": \#(Version.controlProtocol), "holder": {"key": "k", "name": "Claude Code", "place": "/tmp"}, "#
            + fields + "}"
        #expect(throws: ControlProtocolError.self) { try ControlMessage.decode(Data(json.utf8)) }
    }

    @Test("a side's other side, and the layouts' names on the wire")
    func names() {
        #expect(CompareSide.left.other == .right)
        #expect(CompareSide.right.other == .left)
        #expect(CompareLayout.allCases.map(\.rawValue) == ["side-by-side", "flip", "slider"])
        #expect(CompareChange().isEmpty)
        #expect(!CompareChange(slider: 0).isEmpty)
    }
}
