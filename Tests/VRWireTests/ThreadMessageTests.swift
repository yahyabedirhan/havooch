import Foundation
import Testing
import VRLease
import VRWire

private let holder = Holder(key: "CLAUDE_CODE_SESSION_ID=abc", name: "Claude Code", place: "/Users/me/repo")
private let holderJSON = #""holder":{"key":"k","name":"Claude Code","place":"/Users/me/repo"}"#

private func raw(_ fields: String) -> Data {
    Data("{\(fields)}".utf8)
}

private func wire(_ request: ControlRequest) -> String {
    String(decoding: ControlMessage(request, holder: holder).encoded(), as: UTF8.self)
}

/// The listener's answers and the operator's `thread answer` on the wire.
@Suite struct ThreadRequestTests {
    @Test(arguments: [
        ControlRequest.ack(batchID: "b1", text: nil),
        .ack(batchID: "b1", text: "on it"),
        .status(commentID: "c1", state: "working"),
        .status(commentID: "c1", state: "done"),
        .status(commentID: "c1", state: "failed"),
        .reply(id: "c1", text: "fixed in abc123"),
        .reply(id: "b1", text: "two\nlines, \"quoted\""),
        .ask(commentID: "c1", question: "which part?", waitSeconds: nil),
        .ask(commentID: "c1", question: "which part?", waitSeconds: 0),
        .ask(commentID: "c1", question: "which part?", waitSeconds: 600),
    ])
    func everyListenerRequestReadsBackAsItWasSentAndNeedsNoLease(request: ControlRequest) throws {
        for json in [false, true] {
            let message = ControlMessage(request, holder: holder, json: json)
            #expect(try ControlMessage.decode(message.encoded()) == message)
        }
        #expect(request.role == .listener)
    }

    @Test func threadAnswerReadsBackAndNeedsTheLease() throws {
        let request = ControlRequest.threadAnswer(commentID: "c1", text: "the intro")
        let message = ControlMessage(request, holder: holder, json: true)

        #expect(try ControlMessage.decode(message.encoded()) == message)
        #expect(request.role == .operator)
        #expect(!request.isLongPoll)
    }

    @Test func theCommandsAreNamedByTheirWordsOnTheWire() {
        #expect(wire(.ack(batchID: "b1", text: "on it")).hasPrefix(#"{"command":"ack","holder":"#))
        #expect(wire(.ack(batchID: "b1", text: "on it")).hasSuffix(#""id":"b1","json":false,"text":"on it","version":1}"#))
        #expect(!wire(.ack(batchID: "b1", text: nil)).contains(#""text""#))
        #expect(wire(.status(commentID: "c1", state: "done")).hasSuffix(#""id":"c1","json":false,"state":"done","version":1}"#))
        #expect(wire(.reply(id: "c1", text: "ok")).hasPrefix(#"{"command":"reply","#))
        #expect(wire(.threadAnswer(commentID: "c1", text: "ok")).hasPrefix(#"{"command":"thread.answer","#))
        let ask = wire(.ask(commentID: "c1", question: "why?", waitSeconds: 30))
        #expect(ask.hasPrefix(#"{"command":"ask","#))
        #expect(ask.hasSuffix(#""id":"c1","json":false,"text":"why?","version":1,"waitSeconds":30}"#))
        #expect(!wire(.ask(commentID: "c1", question: "why?", waitSeconds: nil)).contains("waitSeconds"))
    }

    @Test func anAskIsALongPollAndTheOtherAnswersAreNot() {
        #expect(ControlRequest.ask(commentID: "c1", question: "why?", waitSeconds: nil).isLongPoll)
        #expect(ControlRequest.ask(commentID: "c1", question: "why?", waitSeconds: 5).isLongPoll)
        for request: ControlRequest in [
            .ack(batchID: "b1", text: nil), .status(commentID: "c1", state: "done"), .reply(id: "c1", text: "ok"),
        ] {
            #expect(!request.isLongPoll)
            #expect(request.hold == 0)
        }
    }

    @Test(arguments: [
        (#""command":"ack""#, "the control command `ack` needs its `id`"),
        (#""command":"status","state":"done""#, "the control command `status` needs its `id`"),
        (#""command":"status","id":"c1""#, "the control command `status` needs its `state`"),
        (#""command":"status","id":"c1","state":"sent""#,
         "the control command `status` has no state `sent`; it takes `working`, `done` or `failed`"),
        (#""command":"reply","text":"x""#, "the control command `reply` needs its `id`"),
        (#""command":"reply","id":"c1""#, "the control command `reply` needs its `text`"),
        (#""command":"ask","text":"x""#, "the control command `ask` needs its `id`"),
        (#""command":"ask","id":"c1""#, "the control command `ask` needs its `text`"),
        (#""command":"ask","id":"c1","text":"x","waitSeconds":-1"#,
         "the control command `ask` needs a `waitSeconds` from 0 to 86400, not -1"),
        (#""command":"ask","id":"c1","text":"x","waitSeconds":86401"#,
         "the control command `ask` needs a `waitSeconds` from 0 to 86400, not 86401"),
        (#""command":"thread.answer","text":"x""#, "the control command `thread.answer` needs its `id`"),
        (#""command":"thread.answer","id":"c1""#, "the control command `thread.answer` needs its `text`"),
    ])
    func aRequestThatDoesNotReadIsRefused(fields: String, why: String) {
        #expect(throws: ControlProtocolError.unreadable(why)) {
            try ControlMessage.decode(raw(#"\#(fields),"version":1,\#(holderJSON)"#))
        }
    }
}
