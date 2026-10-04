import Foundation
import Testing
import VRLease
import VRWire

private let holder = Holder(key: "CLAUDE_CODE_SESSION_ID=abc", name: "Claude Code", place: "/Users/me/repo")
private let holderJSON = #""holder":{"key":"k","name":"Claude Code","place":"/Users/me/repo"}"#

private func raw(_ fields: String) -> Data {
    Data("{\(fields)}".utf8)
}

@Suite struct CommentMessageTests {
    @Test(arguments: [
        ControlRequest.commentAdd(text: "too fast", at: nil, region: nil),
        .commentAdd(text: "two\nlines, \"quoted\"", at: 10.5, region: nil),
        .commentAdd(text: "this corner", at: 10, region: ControlRequest.WireRegion(x: 0.5, y: 0, w: 0.5, h: 0.25)),
        .commentAdd(text: "this corner", at: nil, region: ControlRequest.WireRegion(x: 0, y: 0, w: 1, h: 1)),
        .commentEdit(id: "c1", text: "slower here"),
        .commentDelete(id: "c1"),
        .contextSet(text: "Mind the pacing.\nIt's a draft."),
        .contextSet(text: ""),
    ])
    func everyCommentRequestReadsBackAsItWasSent(request: ControlRequest) throws {
        for json in [false, true] {
            let message = ControlMessage(request, holder: holder, json: json)
            #expect(try ControlMessage.decode(message.encoded()) == message)
        }
        // A comment changes the review: it needs the lease.
        #expect(request.role == .operator)
    }

    @Test func aCommentIsNamedByTheCommandsWordsOnTheWire() {
        let message = ControlMessage(.commentAdd(text: "too fast", at: 10, region: nil), holder: holder)
        #expect(String(decoding: message.encoded(), as: UTF8.self) ==
            #"{"command":"comment.add","holder":{"key":"CLAUDE_CODE_SESSION_ID=abc","name":"Claude Code","place":"\/Users\/me\/repo"},"json":false,"text":"too fast","time":10,"version":1}"#)
    }

    @Test func aRegionGoesOverTheWireAsItsFourParts() {
        let region = ControlRequest.WireRegion(x: 0.5, y: 0, w: 0.25, h: 0.5)
        let message = ControlMessage(.commentAdd(text: "here", at: nil, region: region), holder: holder)
        #expect(String(decoding: message.encoded(), as: UTF8.self).contains(#""region":{"h":0.5,"w":0.25,"x":0.5,"y":0},"#))
    }

    @Test func aRegionThatIsNotFourNumbersIsRefused() {
        #expect(throws: ControlProtocolError.unreadable("the request isn't a control request")) {
            try ControlMessage.decode(raw(#""command":"comment.add","text":"x","region":{"x":0.1,"y":0.2},"version":1,\#(holderJSON)"#))
        }
    }

    @Test(arguments: [
        (#""command":"comment.add""#, "the control command `comment.add` needs its `text`"),
        (#""command":"comment.add","text":"x","time":-1"#, "the control command `comment.add` needs a `time` of 0 or more, not -1.0"),
        (#""command":"comment.edit","text":"x""#, "the control command `comment.edit` needs its `id`"),
        (#""command":"comment.edit","id":"c1""#, "the control command `comment.edit` needs its `text`"),
        (#""command":"comment.delete""#, "the control command `comment.delete` needs its `id`"),
        (#""command":"context.set""#, "the control command `context.set` needs its `text`"),
    ])
    func aCommentRequestMissingItsFieldIsRefused(fields: String, why: String) {
        #expect(throws: ControlProtocolError.unreadable(why)) {
            try ControlMessage.decode(raw(#"\#(fields),"version":1,\#(holderJSON)"#))
        }
    }
}
