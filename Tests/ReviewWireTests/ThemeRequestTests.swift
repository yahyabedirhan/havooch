import Foundation
import ReviewLease
import ReviewWire
import Testing

@Suite("The theme requests")
struct ThemeRequestTests {
    static let holder = Holder(key: "CLAUDE_CODE_SESSION_ID=abc", name: "Claude Code", place: "/Users/me/shop")

    @Test("theme list and theme set read back as they were sent", arguments: [
        ControlRequest.themeList, .themeSet(name: "Dimmed"), .themeSet(name: "system"),
    ], [false, true])
    func roundTrip(request: ControlRequest, json: Bool) throws {
        let message = ControlMessage(request, holder: Self.holder, json: json)
        #expect(try ControlMessage.decode(message.encoded()) == message)
    }

    @Test("listing the themes is free; setting one takes the lease and isn't held")
    func roles() {
        #expect(ControlRequest.themeList.role == .free)
        #expect(ControlRequest.themeSet(name: "Dimmed").role == .operator)
        #expect(ControlRequest.themeSet(name: "Dimmed").holdSeconds == 0)
    }

    @Test("theme set without a name is refused in words")
    func needsName() throws {
        let fields: [String: Any] = [
            "version": Version.controlProtocol, "command": "theme.set",
            "holder": ["key": Self.holder.key, "name": Self.holder.name, "place": Self.holder.place],
        ]
        let data = try JSONSerialization.data(withJSONObject: fields)
        #expect(throws: ControlProtocolError.unreadable("the control command `theme.set` needs its `name`")) {
            try ControlMessage.decode(data)
        }
    }
}
