import Foundation
import Testing
import VRLease
import VRWire

@Suite struct ControlMessageTests {
    let holder = Holder(key: "CLAUDE_CODE_SESSION_ID=abc", name: "Claude Code", place: "/Users/me/repo")

    static let everyRequest: [ControlRequest] = [
        .appStatus, .state, .controlTake(waitSeconds: nil), .controlTake(waitSeconds: 30), .controlRelease,
        .appOpen, .appQuit,
        .playerOpen(path: "/videos/sample.mp4"), .playerPlay, .playerPause, .playerSeek(seconds: 10.5),
        .commentAdd(text: "the title is small", at: nil, region: nil),
        .commentAdd(text: "this box", at: 4, region: WireRegion(x: 0.1, y: 0.2, w: 0.3, h: 0.2)),
        .commentEdit(id: "7f3a9c21-c1", text: "new text"), .commentDelete(id: "7f3a9c21-c1"),
        .batchSend, .threadAnswer(id: "7f3a9c21-c1", text: "yes"), .contextSet(text: "a note"),
        .screenshot(path: "/tmp/window.png", appearance: nil), .screenshot(path: "/tmp/window.png", appearance: .dark),
        .wait(timeoutSeconds: nil), .wait(timeoutSeconds: 30),
        .ack(id: "7f3a9c21-b1", text: nil), .ack(id: "7f3a9c21-b1", text: "on it"),
        .status(id: "7f3a9c21-c1", state: "working"), .reply(id: "7f3a9c21-c1", text: "fixed"),
        .ask(id: "7f3a9c21-c1", text: "which one?", waitSeconds: nil), .ask(id: "7f3a9c21-c1", text: "which one?", waitSeconds: 60),
    ]

    @Test(arguments: everyRequest)
    func aRequestComesBackAsItWasSent(request: ControlRequest) throws {
        for json in [false, true] {
            let message = ControlMessage(request, holder: holder, json: json)
            #expect(try ControlMessage.decode(message.encoded()) == message)
        }
    }

    @Test func theWireIsOneObjectWithTheCommandsFieldsBesideTheFramingOnes() {
        let message = ControlMessage(.playerSeek(seconds: 10), holder: holder)
        #expect(String(decoding: message.encoded(), as: UTF8.self) == """
            {"command":"player.seek","holder":{"key":"CLAUDE_CODE_SESSION_ID=abc","name":"Claude Code","place":"\\/Users\\/me\\/repo"},"json":false,"seconds":10,"version":1}
            """)
    }

    @Test func aRequestOfAnotherVersionIsRefusedNamingBothVersions() {
        let other = ControlRequest.version + 1
        let data = Data(#"{"command":"player.play","holder":{"key":"k","name":"n","place":"p"},"version":\#(other)}"#.utf8)
        #expect(throws: ControlProtocolError.otherVersion(other)) { try ControlMessage.decode(data) }
        let message = ControlProtocolError.otherVersion(other).message
        #expect(message.contains("the video-review command speaks control version \(other)"))
        #expect(message.contains("the app version \(ControlRequest.version)"))
        #expect(message.contains("Contents/Helpers/video-review"))
    }

    @Test func theVersionIsCheckedBeforeAnythingElse() {
        // Another version's request may have another shape altogether.
        let data = Data(#"{"version":2,"verb":["seek",10]}"#.utf8)
        #expect(throws: ControlProtocolError.otherVersion(2)) { try ControlMessage.decode(data) }
    }

    @Test func whatIsNotARequestIsRefusedInWords() {
        #expect(throws: ControlProtocolError.unreadable("the request isn't a control request")) {
            try ControlMessage.decode(Data("hello".utf8))
        }
        #expect(throws: ControlProtocolError.unreadable("the request isn't a control request")) {
            try ControlMessage.decode(Data(#"{"command":"state"}"#.utf8))
        }
    }

    @Test func aRequestWithoutItsHolderIsRefused() {
        let data = Data(#"{"command":"state","version":1}"#.utf8)
        #expect(throws: ControlProtocolError.unreadable("the control command `state` needs its `holder`")) {
            try ControlMessage.decode(data)
        }
    }

    @Test func anUnknownCommandIsNamed() {
        let data = Data(#"{"command":"player.rewind","holder":{"key":"k","name":"n","place":"p"},"version":1}"#.utf8)
        #expect(throws: ControlProtocolError.unknownCommand("player.rewind")) { try ControlMessage.decode(data) }
        #expect(ControlProtocolError.unknownCommand("player.rewind").message == "the app doesn't know the control command `player.rewind`")
    }

    @Test(arguments: [
        (#""command":"player.seek""#, "the control command `player.seek` needs its `seconds`"),
        (#""command":"player.seek","seconds":-1"#, "the control command `player.seek` needs `seconds` of 0 or more, not -1.0"),
        (#""command":"player.open""#, "the control command `player.open` needs its `path`"),
        (#""command":"player.open","path":"sample.mp4""#, "the control command `player.open` needs an absolute `path`, not `sample.mp4`"),
        (#""command":"screenshot","path":"window.png""#, "the control command `screenshot` needs an absolute `path`, not `window.png`"),
        (
            #""command":"screenshot","path":"/tmp/w.png","appearance":"sepia""#,
            "the control command `screenshot` has no appearance `sepia`; it takes `light` or `dark`"
        ),
        (#""command":"control.take","waitSeconds":4000"#, "the control command `control.take` needs a `waitSeconds` from 0 to 3600, not 4000"),
        (#""command":"wait","timeoutSeconds":-1"#, "the control command `wait` needs a `timeoutSeconds` from 0 to 3600, not -1"),
    ])
    func aRequestMissingWhatItsCommandNeedsIsRefused(fields: String, refusal: String) {
        let data = Data(#"{\#(fields),"holder":{"key":"k","name":"n","place":"p"},"version":1}"#.utf8)
        #expect(throws: ControlProtocolError.unreadable(refusal)) { try ControlMessage.decode(data) }
    }

    @Test func onlyTheOperatorsCommandsNeedTheLease() {
        let leased = Set(Self.everyRequest.filter(\.isLeased).map(\.command))
        #expect(leased == [
            "app.open", "app.quit", "player.open", "player.play", "player.pause", "player.seek",
            "comment.add", "comment.edit", "comment.delete", "batch.send", "thread.answer", "context.set", "screenshot",
        ])
    }
}

@Suite struct ControlReplyTests {
    @Test func aReplyComesBackAsItWasSent() throws {
        let term = ControlLease.Term(
            holder: Holder(key: "k", name: "Claude Code", place: "/repo"),
            taken: Date(timeIntervalSince1970: 1_000), ends: Date(timeIntervalSince1970: 1_060)
        )
        for reply in [ControlReply.done("0:10.000\n"), .done("/tmp/w.png\n", note: "rendered\n"), .refused("no video is open"),
                      ControlReply(ok: true, output: "quit\n", lease: term)] {
            #expect(try ControlReply.decode(reply.encoded()) == reply)
        }
    }

    @Test func theHeartbeatsSpacesBeforeAReplyAreSkipped() throws {
        let reply = ControlReply.done("{}\n")
        #expect(try ControlReply.decode(Data("   ".utf8) + reply.encoded()) == reply)
    }

    @Test func whatIsNotAReplyIsRefused() {
        #expect(throws: ControlProtocolError.unreadable("the app's reply doesn't read")) {
            try ControlReply.decode(Data())
        }
    }
}
