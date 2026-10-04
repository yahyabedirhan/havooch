import Foundation
import ReviewWire
import Testing

@Suite("The control protocol")
struct ControlMessageTests {
    static let holder = Holder(key: "CLAUDE_CODE_SESSION_ID=abc", name: "Claude Code", place: "/Users/me/shop")

    /// A message as a client of any build could write it.
    private func raw(_ fields: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: fields)
    }

    private var holderFields: [String: String] {
        ["key": Self.holder.key, "name": Self.holder.name, "place": Self.holder.place]
    }

    private func refusal(_ fields: [String: Any]) -> ControlProtocolError? {
        do throws(ControlProtocolError) {
            _ = try ControlMessage.decode(raw(fields))
            return nil
        } catch {
            return error
        }
    }

    @Test("every request reads back as it was sent", arguments: [
        ControlRequest.appStatus, .state, .appOpen, .appQuit,
        .playerOpen(path: "/videos/sample.mp4"), .playerPlay, .playerPause, .playerSeek(seconds: 12.5),
        .screenshot(path: "/tmp/shot.png", appearance: nil), .screenshot(path: "/tmp/shot.png", appearance: .dark),
    ])
    func roundTrip(request: ControlRequest) throws {
        for json in [false, true] {
            let message = ControlMessage(request, holder: Self.holder, json: json)
            #expect(try ControlMessage.decode(message.encoded()) == message)
        }
    }

    @Test("a request carries its version, its command and its holder")
    func wireShape() throws {
        let data = ControlMessage(.playerSeek(seconds: 10), holder: Self.holder).encoded()
        let fields = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(fields["version"] as? Int == Version.controlProtocol)
        #expect(fields["command"] as? String == "player.seek")
        #expect(fields["seconds"] as? Double == 10)
        #expect(fields["json"] as? Bool == false)
        #expect(fields["holder"] as? [String: String] == holderFields)
    }

    @Test("a request of another version is refused, naming both versions")
    func otherVersion() {
        let other = Version.controlProtocol + 1
        let error = refusal(["version": other, "command": "player.play", "holder": holderFields])
        #expect(error == .otherVersion(other))
        let message = error?.message ?? ""
        #expect(message.contains("version \(other)"))
        #expect(message.contains("version \(Version.controlProtocol)"))
        #expect(message.contains("reinstall"))
    }

    @Test("another version is refused before its other fields are read")
    func otherVersionWithOtherShape() {
        // A later build may shape the holder differently, or drop it.
        let other = Version.controlProtocol + 1
        #expect(refusal(["version": other, "command": 7, "holder": "someone"]) == .otherVersion(other))
        #expect(refusal(["version": other]) == .otherVersion(other))
    }

    @Test("a request that isn't one is refused in words")
    func unreadable() {
        #expect(throws: ControlProtocolError.unreadable("the request isn't a control request")) {
            try ControlMessage.decode(Data("hello".utf8))
        }
        #expect(refusal(["version": Version.controlProtocol, "command": "player.play"])
            == .unreadable("the control command `player.play` needs its `holder`"))
        #expect(refusal(["version": Version.controlProtocol, "command": "player.rewind", "holder": holderFields])
            == .unknownCommand("player.rewind"))
    }

    @Test("a field that's missing or invalid is refused")
    func invalidFields() {
        func fields(_ command: String, _ more: [String: Any]) -> [String: Any] {
            more.merging(["version": Version.controlProtocol, "command": command, "holder": holderFields]) { _, new in new }
        }
        #expect(refusal(fields("player.open", [:])) == .unreadable("the control command `player.open` needs its `path`"))
        #expect(refusal(fields("player.open", ["path": "sample.mp4"]))
            == .unreadable("the control command `player.open` needs an absolute `path`, not `sample.mp4`"))
        #expect(refusal(fields("screenshot", ["path": "shot.png"]))
            == .unreadable("the control command `screenshot` needs an absolute `path`, not `shot.png`"))
        #expect(refusal(fields("screenshot", ["path": "/tmp/shot.png", "appearance": "sepia"]))
            == .unreadable("the control command `screenshot` has no appearance `sepia`; it takes `light` or `dark`"))
        #expect(refusal(fields("player.seek", [:])) != nil)
        #expect(refusal(fields("player.seek", ["seconds": -1])) != nil)
    }

    @Test("only operator requests take the lease")
    func roles() {
        #expect(ControlRequest.appStatus.role == .free)
        #expect(ControlRequest.state.role == .free)
        for request in [ControlRequest.appOpen, .appQuit, .playerOpen(path: "/a.mp4"), .playerPlay, .playerPause,
                        .playerSeek(seconds: 1), .screenshot(path: "/a.png", appearance: nil)] {
            #expect(request.role == .operator)
        }
    }

    @Test("a reply reads back as it was sent")
    func reply() throws {
        let reply = ControlReply.done("0:10\n")
        #expect(try ControlReply.decode(reply.encoded()) == reply)
        #expect(try ControlReply.decode(ControlReply.refused("no video is open").encoded())
            == ControlReply(ok: false, error: "no video is open"))
        #expect(throws: ControlProtocolError.self) { try ControlReply.decode(Data("nothing".utf8)) }
    }
}
