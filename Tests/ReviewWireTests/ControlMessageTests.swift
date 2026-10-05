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
        .controlTake(waitSeconds: nil), .controlTake(waitSeconds: 30), .controlRelease,
        .screenshot(path: "/tmp/shot.png", appearance: .light, withBanner: true),
        .playerOpen(path: "/videos/sample.mp4"), .playerPlay, .playerPause, .playerSeek(seconds: 12.5),
        .screenshot(path: "/tmp/shot.png", appearance: nil), .screenshot(path: "/tmp/shot.png", appearance: .dark),
        .commentAdd(text: "Too fast\nhere", at: nil), .commentAdd(text: "Too fast", at: 12.5),
        .commentAdd(text: "This box", at: 12.5, region: .init(x: 0.25, y: 0.2, w: 0.3, h: 0.25)),
        .commentAdd(text: "This box", at: nil, region: .init(x: 0, y: 0, w: 1, h: 1)),
        .commentEdit(id: "c-7f3a9c2e", text: "Slower"), .commentDelete(id: "c-7f3a9c2e"),
        .contextSet(text: "Compare with\nthe old cut"), .contextSet(text: ""),
        .batchSend, .wait(timeoutSeconds: nil), .wait(timeoutSeconds: 0), .wait(timeoutSeconds: 600),
        .ack(batchID: "b-5d0c2a91", text: nil), .ack(batchID: "b-5d0c2a91", text: "On it"),
        .status(commentID: "c-7f3a9c2e", state: .working), .status(commentID: "c-7f3a9c2e", state: .done),
        .status(commentID: "c-7f3a9c2e", state: .failed),
        .reply(id: "c-7f3a9c2e", text: "Slowed it down"), .reply(id: "b-5d0c2a91", text: "All done"),
        .ask(commentID: "c-7f3a9c2e", question: "Which part?", waitSeconds: nil),
        .ask(commentID: "c-7f3a9c2e", question: "Which part?", waitSeconds: 0),
        .ask(commentID: "c-7f3a9c2e", question: "Which part?", waitSeconds: 600),
        .threadAnswer(commentID: "c-7f3a9c2e", text: "The intro"),
    ], [false, true])
    func roundTrip(request: ControlRequest, json: Bool) throws {
        let message = ControlMessage(request, holder: Self.holder, json: json)
        #expect(try ControlMessage.decode(message.encoded()) == message)
    }

    @Test("a region is four numbers with commas between them, and anything else isn't one")
    func rectangle() {
        #expect(ControlRequest.Rectangle("0.25,0.2,0.3,0.25") == .init(x: 0.25, y: 0.2, w: 0.3, h: 0.25))
        #expect(ControlRequest.Rectangle("0, 0, 1, 1") == .init(x: 0, y: 0, w: 1, h: 1))
        // Numbers outside the frame still read: the app refuses them in words.
        #expect(ControlRequest.Rectangle("0.9,0.2,0.3,0.25") != nil)
    }

    @Test("what isn't four finite numbers with commas between them isn't a region", arguments: [
        "", "0.25,0.2,0.3", "0.25,0.2,0.3,0.25,1", "a,b,c,d", "0.25,,0.3,0.25", "0.25 0.2 0.3 0.25", "nan,0,1,1", "inf,0,1,1",
    ])
    func notARectangle(text: String) {
        #expect(ControlRequest.Rectangle(text) == nil)
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
        #expect(refusal(fields("control.take", ["waitSeconds": -1]))
            == .unreadable("the control command `control.take` needs a `waitSeconds` from 0 to 3600, not -1"))
        #expect(refusal(fields("control.take", ["waitSeconds": 3601])) != nil)
        #expect(refusal(fields("player.seek", [:])) != nil)
        #expect(refusal(fields("player.seek", ["seconds": -1])) != nil)
        #expect(refusal(fields("comment.add", [:])) == .unreadable("the control command `comment.add` needs its `text`"))
        #expect(refusal(fields("comment.add", ["text": "Too fast", "at": -1])) != nil)
        #expect(refusal(fields("comment.edit", ["text": "Slower"])) == .unreadable("the control command `comment.edit` needs its `id`"))
        #expect(refusal(fields("comment.edit", ["id": "c-7f3a9c2e"])) == .unreadable("the control command `comment.edit` needs its `text`"))
        #expect(refusal(fields("comment.delete", [:])) == .unreadable("the control command `comment.delete` needs its `id`"))
        #expect(refusal(fields("context.set", [:])) == .unreadable("the control command `context.set` needs its `text`"))
        #expect(refusal(fields("wait", ["timeoutSeconds": -1]))
            == .unreadable("the control command `wait` needs a `timeoutSeconds` from 0 to 86400, not -1"))
        #expect(refusal(fields("wait", ["timeoutSeconds": 86401])) != nil)
        #expect(refusal(fields("ack", [:])) == .unreadable("the control command `ack` needs its `id`"))
        #expect(refusal(fields("status", ["state": "done"])) == .unreadable("the control command `status` needs its `id`"))
        #expect(refusal(fields("status", ["id": "c-7f3a9c2e"])) == .unreadable("the control command `status` needs its `state`"))
        #expect(refusal(fields("status", ["id": "c-7f3a9c2e", "state": "acknowledged"]))
            == .unreadable("the control command `status` has no state `acknowledged`; it takes `working`, `done` or `failed`"))
        #expect(refusal(fields("reply", ["id": "c-7f3a9c2e"])) == .unreadable("the control command `reply` needs its `text`"))
        #expect(refusal(fields("reply", ["text": "Done"])) == .unreadable("the control command `reply` needs its `id`"))
        #expect(refusal(fields("ask", ["id": "c-7f3a9c2e"])) == .unreadable("the control command `ask` needs its `text`"))
        #expect(refusal(fields("ask", ["id": "c-7f3a9c2e", "text": "Which?", "waitSeconds": -1]))
            == .unreadable("the control command `ask` needs a `waitSeconds` from 0 to 86400, not -1"))
        #expect(refusal(fields("ask", ["id": "c-7f3a9c2e", "text": "Which?", "waitSeconds": 86401])) != nil)
        #expect(refusal(fields("thread.answer", ["id": "c-7f3a9c2e"])) == .unreadable("the control command `thread.answer` needs its `text`"))
    }

    @Test("the listener's answers take no lease and are never held", arguments: [
        ControlRequest.ack(batchID: "b-1", text: nil), .status(commentID: "c-1", state: .done), .reply(id: "c-1", text: "a"),
    ])
    func listenerAnswer(request: ControlRequest) {
        #expect(request.role == .listener)
        #expect(request.holdSeconds == 0)
    }

    @Test("an ask takes no lease and may be held for its wait, or with no limit without one; thread answer is the operator's")
    func answers() {
        #expect(ControlRequest.ask(commentID: "c-1", question: "a", waitSeconds: 30).role == .listener)
        #expect(ControlRequest.ask(commentID: "c-1", question: "a", waitSeconds: 30).holdSeconds == 30)
        #expect(ControlRequest.ask(commentID: "c-1", question: "a", waitSeconds: nil).holdSeconds == nil)
        #expect(ControlRequest.threadAnswer(commentID: "c-1", text: "a").role == .operator)
        #expect(ControlRequest.threadAnswer(commentID: "c-1", text: "a").holdSeconds == 0)
    }

    @Test("a listener's wait takes no lease, and may be held for its timeout, or with no limit without one")
    func listener() {
        #expect(ControlRequest.wait(timeoutSeconds: 30).role == .listener)
        #expect(ControlRequest.wait(timeoutSeconds: 30).holdSeconds == 30)
        #expect(ControlRequest.wait(timeoutSeconds: nil).holdSeconds == nil)
        #expect(ControlRequest.batchSend.role == .operator)
        #expect(ControlRequest.batchSend.holdSeconds == 0)
    }

    @Test("reading the app and taking or releasing the lease are free", arguments: [
        ControlRequest.appStatus, .state, .controlTake(waitSeconds: 30), .controlRelease,
    ])
    func freeRole(request: ControlRequest) {
        #expect(request.role == .free)
    }

    @Test("only operator requests take the lease", arguments: [
        ControlRequest.appOpen, .appQuit, .playerOpen(path: "/a.mp4"), .playerPlay, .playerPause,
        .playerSeek(seconds: 1), .screenshot(path: "/a.png", appearance: nil),
        .commentAdd(text: "a", at: nil), .commentEdit(id: "c-1", text: "a"), .commentDelete(id: "c-1"),
        .contextSet(text: "a"),
    ])
    func operatorRole(request: ControlRequest) {
        #expect(request.role == .operator)
    }

    @Test("a take that waits in line may be held for its wait; no other request is held")
    func holdSeconds() {
        #expect(ControlRequest.controlTake(waitSeconds: 30).holdSeconds == 30)
        #expect(ControlRequest.controlTake(waitSeconds: nil).holdSeconds == 0)
        #expect(ControlRequest.playerPlay.holdSeconds == 0)
    }

    @Test("a reply reads back as it was sent")
    func reply() throws {
        let reply = ControlReply.done("0:10\n")
        #expect(try ControlReply.decode(reply.encoded()) == reply)
        #expect(try ControlReply.decode(ControlReply.refused("no video is open").encoded())
            == ControlReply(ok: false, error: "no video is open"))
        #expect(throws: ControlProtocolError.self) { try ControlReply.decode(Data("nothing".utf8)) }
        // A wait that ran out says so, and only it does.
        #expect(try ControlReply.decode(ControlReply.ranOut.encoded()) == ControlReply(ok: false, timedOut: true))
        #expect(!String(decoding: reply.encoded(), as: UTF8.self).contains("timedOut"))
    }
}
