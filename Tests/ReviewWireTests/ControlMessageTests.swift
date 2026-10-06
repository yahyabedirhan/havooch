import Foundation
import ReviewLease
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
        ControlRequest.appStatus, .state, .appOpen, .appQuit, .appHome, .appDemo,
        .controlTake(waitSeconds: nil), .controlTake(waitSeconds: 30), .controlRelease,
        .screenshot(path: "/tmp/shot.png", appearance: .light, hideAgentIndicator: true),
        .screenshot(path: "/tmp/set.png", appearance: nil, window: .settings), .screenshot(path: "/tmp/about.png", appearance: nil, window: .about),
        .playerOpen(path: "/videos/sample.mp4"), .playerPlay, .playerPause, .playerSeek(seconds: 12.5),
        .screenshot(path: "/tmp/shot.png", appearance: nil), .screenshot(path: "/tmp/shot.png", appearance: .dark),
        .commentAdd(text: "Too fast\nhere", at: nil), .commentAdd(text: "Too fast", at: 12.5),
        .commentAdd(text: "This box", at: 12.5, region: .init(x: 0.25, y: 0.2, w: 0.3, h: 0.25)),
        .commentAdd(text: "This box", at: nil, region: .init(x: 0, y: 0, w: 1, h: 1)),
        .commentAdd(text: "Follow-up", at: nil, thread: "t-f92cbb2a-1"), .commentAdd(text: "In general", at: nil, thread: "0"),
        .commentEdit(id: "m-f92cbb2a-1", text: "Slower"), .commentDelete(id: "m-f92cbb2a-1"),
        .commentOpen(text: ""), .commentOpen(text: "This box", region: .init(x: 0.25, y: 0.2, w: 0.3, h: 0.25)),
        .commentCompose(text: ""), .commentCompose(text: "This box", region: .init(x: 0.25, y: 0.2, w: 0.3, h: 0.25)),
        .commentCompose(text: "Overall", general: true),
        .contextSet(text: "Compare with\nthe old cut"), .contextSet(text: ""),
        .send, .wait(timeoutSeconds: nil), .wait(timeoutSeconds: 0), .wait(timeoutSeconds: 600),
        .ack(sendID: "s-f92cbb2a-1", text: nil), .ack(sendID: "s-f92cbb2a-1", text: "On it"),
        .status(messageID: "m-f92cbb2a-1", state: .working), .status(messageID: "m-f92cbb2a-1", state: .done),
        .status(messageID: "m-f92cbb2a-1", state: .failed),
        .status(messageID: "m-f92cbb2a-1", state: .working, text: "Rendering 0:14 to 0:21"),
        .reply(thread: "t-f92cbb2a-1", text: "Slowed it down"), .reply(thread: "0", text: "All done"),
        .ask(thread: "t-f92cbb2a-1", question: "Which part?", waitSeconds: nil),
        .ask(thread: "1", question: "Which part?", waitSeconds: 0),
        .ask(thread: "t-f92cbb2a-1", question: "Which part?", waitSeconds: 600),
        .ask(thread: "1", question: "Which part?", waitSeconds: nil, choices: ["The intro", "The end"]),
        .threadAnswer(thread: "t-f92cbb2a-1", text: "The intro"),
        .threadChoose(thread: "t-f92cbb2a-1", choice: 2), .threadChoose(thread: "1", choice: 1),
        .threadOpen(thread: "3"), .threadOpen(thread: "t-f92cbb2a-3", frame: .init(x: 0.55, y: 0.1, w: 0.4, h: 0.5)),
        .threadShow(thread: "t-f92cbb2a-1"), .threadShow(thread: "0"), .threadList,
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
        #expect(refusal(fields("screenshot", ["path": "/tmp/shot.png", "window": "inspector"]))
            == .unreadable("the control command `screenshot` has no window `inspector`; it takes `main`, `settings` or `about`"))
        #expect(refusal(fields("control.take", ["waitSeconds": -1]))
            == .unreadable("the control command `control.take` needs a `waitSeconds` from 0 to 3600, not -1"))
        #expect(refusal(fields("control.take", ["waitSeconds": 3601])) != nil)
        #expect(refusal(fields("player.seek", [:])) != nil)
        #expect(refusal(fields("player.seek", ["seconds": -1])) != nil)
        #expect(refusal(fields("comment.add", [:])) == .unreadable("the control command `comment.add` needs its `text`"))
        #expect(refusal(fields("comment.add", ["text": "Too fast", "at": -1])) != nil)
        #expect(refusal(fields("comment.edit", ["text": "Slower"])) == .unreadable("the control command `comment.edit` needs its `id`"))
        #expect(refusal(fields("comment.edit", ["id": "m-f92cbb2a-1"])) == .unreadable("the control command `comment.edit` needs its `text`"))
        #expect(refusal(fields("comment.delete", [:])) == .unreadable("the control command `comment.delete` needs its `id`"))
        #expect(refusal(fields("context.set", [:])) == .unreadable("the control command `context.set` needs its `text`"))
        #expect(refusal(fields("wait", ["timeoutSeconds": -1]))
            == .unreadable("the control command `wait` needs a `timeoutSeconds` from 0 to 86400, not -1"))
        #expect(refusal(fields("wait", ["timeoutSeconds": 86401])) != nil)
        #expect(refusal(fields("ack", [:])) == .unreadable("the control command `ack` needs its `id`"))
        #expect(refusal(fields("status", ["state": "done"])) == .unreadable("the control command `status` needs its `id`"))
        #expect(refusal(fields("status", ["id": "m-f92cbb2a-1"])) == .unreadable("the control command `status` needs its `state`"))
        #expect(refusal(fields("status", ["id": "m-f92cbb2a-1", "state": "acknowledged"]))
            == .unreadable("the control command `status` has no state `acknowledged`; it takes `working`, `done` or `failed`"))
        #expect(refusal(fields("reply", ["thread": "1"])) == .unreadable("the control command `reply` needs its `text`"))
        #expect(refusal(fields("reply", ["text": "Done"])) == .unreadable("the control command `reply` needs its `thread`"))
        #expect(refusal(fields("ask", ["thread": "1"])) == .unreadable("the control command `ask` needs its `text`"))
        #expect(refusal(fields("ask", ["thread": "1", "text": "Which?", "waitSeconds": -1]))
            == .unreadable("the control command `ask` needs a `waitSeconds` from 0 to 86400, not -1"))
        #expect(refusal(fields("ask", ["thread": "1", "text": "Which?", "waitSeconds": 86401])) != nil)
        #expect(refusal(fields("thread.answer", ["text": "a"])) == .unreadable("the control command `thread.answer` needs its `thread`"))
        #expect(refusal(fields("thread.answer", ["thread": "1"])) == .unreadable("the control command `thread.answer` needs its `text`"))
        #expect(refusal(fields("thread.choose", ["thread": "1"])) == .unreadable("the control command `thread.choose` needs its `choice`, 1 or more"))
        #expect(refusal(fields("thread.choose", ["thread": "1", "choice": 0])) != nil)
        #expect(refusal(fields("thread.choose", ["choice": 1])) == .unreadable("the control command `thread.choose` needs its `thread`"))
    }

    @Test("an ask with no choices goes on the wire as it did before choices")
    func askWithoutChoices() throws {
        let plain = String(decoding: ControlMessage(.ask(thread: "1", question: "Which?", waitSeconds: nil), holder: Self.holder).encoded(), as: UTF8.self)
        #expect(!plain.contains("choices"))
        let offered = ControlMessage(.ask(thread: "1", question: "Which?", waitSeconds: nil, choices: ["A", "B"]), holder: Self.holder)
        #expect(String(decoding: offered.encoded(), as: UTF8.self).contains(#""choices":["A","B"]"#))
    }

    @Test("the listener's answers take no lease and are never held", arguments: [
        ControlRequest.ack(sendID: "s-1", text: nil), .status(messageID: "m-1", state: .done), .reply(thread: "1", text: "a"),
    ])
    func listenerAnswer(request: ControlRequest) {
        #expect(request.role == .listener)
        #expect(request.holdSeconds == 0)
    }

    @Test("an ask takes no lease and may be held for its wait, or with no limit without one; thread answer is the operator's")
    func answers() {
        #expect(ControlRequest.ask(thread: "1", question: "a", waitSeconds: 30).role == .listener)
        #expect(ControlRequest.ask(thread: "1", question: "a", waitSeconds: 30).holdSeconds == 30)
        #expect(ControlRequest.ask(thread: "1", question: "a", waitSeconds: nil).holdSeconds == nil)
        #expect(ControlRequest.threadAnswer(thread: "1", text: "a").role == .operator)
        #expect(ControlRequest.threadAnswer(thread: "1", text: "a").holdSeconds == 0)
        #expect(ControlRequest.ask(thread: "1", question: "a", waitSeconds: 30, choices: ["b"]).holdSeconds == 30)
        #expect(ControlRequest.threadChoose(thread: "1", choice: 1).role == .operator)
        #expect(ControlRequest.threadChoose(thread: "1", choice: 1).holdSeconds == 0)
        #expect(ControlRequest.threadShow(thread: "1").role == .operator)
        #expect(ControlRequest.threadList.role == .operator)
    }

    @Test("a listener's wait takes no lease, and may be held for its timeout, or with no limit without one")
    func listener() {
        #expect(ControlRequest.wait(timeoutSeconds: 30).role == .listener)
        #expect(ControlRequest.wait(timeoutSeconds: 30).holdSeconds == 30)
        #expect(ControlRequest.wait(timeoutSeconds: nil).holdSeconds == nil)
        #expect(ControlRequest.send.role == .operator)
        #expect(ControlRequest.send.holdSeconds == 0)
    }

    @Test("reading the app and taking or releasing the lease are free", arguments: [
        ControlRequest.appStatus, .state, .controlTake(waitSeconds: 30), .controlRelease,
    ])
    func freeRole(request: ControlRequest) {
        #expect(request.role == .free)
    }

    @Test("only operator requests take the lease", arguments: [
        ControlRequest.appOpen, .appQuit, .appHome, .appDemo, .playerOpen(path: "/a.mp4"), .playerPlay, .playerPause,
        .playerSeek(seconds: 1), .screenshot(path: "/a.png", appearance: nil),
        .commentAdd(text: "a", at: nil), .commentEdit(id: "m-1", text: "a"), .commentDelete(id: "m-1"),
        .commentOpen(text: "a"), .commentCompose(text: "a"), .contextSet(text: "a"), .threadOpen(thread: "1"),
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

    @Test("the reply to a quit carries the lease term a relaunch hands over")
    func replyCarriesLease() throws {
        let term = LeaseTerm(
            holder: Holder(key: "k", name: "codex", place: "/work"),
            taken: Date(timeIntervalSince1970: 0),
            ends: Date(timeIntervalSince1970: 70.5)
        )
        let reply = ControlReply(ok: true, output: "quit\n", lease: term)

        #expect(try ControlReply.decode(reply.encoded()).lease == term)
    }
}
