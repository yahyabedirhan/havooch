import Foundation
import Testing
import VRLease
import VRWire

private let holder = Holder(key: "CLAUDE_CODE_SESSION_ID=abc", name: "Claude Code", place: "/Users/me/repo")

/// A request as raw JSON, the way another build's command would send it.
private func raw(_ fields: String) -> Data {
    Data("{\(fields)}".utf8)
}

private let holderJSON = #""holder":{"key":"k","name":"Claude Code","place":"/Users/me/repo"}"#

@Suite struct ControlMessageTests {
    @Test(arguments: [
        ControlRequest.appStatus,
        .state,
        .controlTake(waitSeconds: nil),
        .controlTake(waitSeconds: 0),
        .controlTake(waitSeconds: 30),
        .controlRelease,
        .appOpen,
        .appQuit,
        .playerOpen(path: "/Users/me/sample.mp4"),
        .playerPlay,
        .playerPause,
        .playerSeek(seconds: 10),
        .playerSeek(seconds: 62.5),
        .screenshot(path: "/tmp/shot.png", appearance: nil),
        .screenshot(path: "/tmp/shot.png", appearance: .light),
        .screenshot(path: "/tmp/shot.png", appearance: .dark),
    ])
    func everyRequestReadsBackAsItWasSent(request: ControlRequest) throws {
        for json in [false, true] {
            let message = ControlMessage(request, holder: holder, json: json)
            #expect(try ControlMessage.decode(message.encoded()) == message)
        }
    }

    @Test func aMessageIsOneFlatJSONObjectWithSortedKeys() {
        let message = ControlMessage(.playerSeek(seconds: 10), holder: holder)
        #expect(String(decoding: message.encoded(), as: UTF8.self) ==
            #"{"command":"player.seek","holder":{"key":"CLAUDE_CODE_SESSION_ID=abc","name":"Claude Code","place":"\/Users\/me\/repo"},"json":false,"time":10,"version":1}"#)
    }

    @Test func aRequestOfAnotherVersionIsRefusedNamingBothVersions() {
        let other = raw(#""command":"app.status","version":2,\#(holderJSON)"#)
        #expect(throws: ControlProtocolError.otherVersion(2)) { try ControlMessage.decode(other) }
        let message = ControlProtocolError.otherVersion(2).message
        #expect(message.contains("control version 2"))
        #expect(message.contains("the app version \(ControlRequest.version)"))
        #expect(message.contains("reinstall"))
    }

    @Test func anotherVersionIsRefusedBeforeItsFieldsAreRead() {
        // A newer build's command this build doesn't know, and no holder:
        // the version is what the refusal names.
        let other = raw(#""command":"future.command","version":7"#)
        #expect(throws: ControlProtocolError.otherVersion(7)) { try ControlMessage.decode(other) }
    }

    @Test func aRequestWithoutAVersionIsRefused() {
        #expect(throws: ControlProtocolError.unreadable("the request isn't a control request")) {
            try ControlMessage.decode(raw(#""command":"state",\#(holderJSON)"#))
        }
    }

    @Test func aRequestWithoutAHolderIsRefused() {
        #expect(throws: ControlProtocolError.unreadable("the control command `state` needs its `holder`")) {
            try ControlMessage.decode(raw(#""command":"state","version":1"#))
        }
    }

    @Test func anUnknownCommandIsRefusedByName() {
        #expect(throws: ControlProtocolError.unknownCommand("player.rewind")) {
            try ControlMessage.decode(raw(#""command":"player.rewind","version":1,\#(holderJSON)"#))
        }
        #expect(ControlProtocolError.unknownCommand("player.rewind").message == "the app doesn't know the control command `player.rewind`")
    }

    @Test func whatIsNotJSONIsRefused() {
        #expect(throws: ControlProtocolError.unreadable("the request isn't a control request")) {
            try ControlMessage.decode(Data("hello".utf8))
        }
    }

    @Test func aCommandMissingItsFieldIsRefused() {
        #expect(throws: ControlProtocolError.unreadable("the control command `player.seek` needs its `time`")) {
            try ControlMessage.decode(raw(#""command":"player.seek","version":1,\#(holderJSON)"#))
        }
        #expect(throws: ControlProtocolError.unreadable("the control command `player.open` needs its `path`")) {
            try ControlMessage.decode(raw(#""command":"player.open","version":1,\#(holderJSON)"#))
        }
    }

    @Test func aRelativePathIsRefused() {
        #expect(throws: ControlProtocolError.unreadable("the control command `screenshot` needs an absolute `path`, not `shot.png`")) {
            try ControlMessage.decode(raw(#""command":"screenshot","path":"shot.png","version":1,\#(holderJSON)"#))
        }
    }

    @Test func aNegativeTimeIsRefused() {
        #expect(throws: ControlProtocolError.self) {
            try ControlMessage.decode(raw(#""command":"player.seek","time":-1,"version":1,\#(holderJSON)"#))
        }
    }

    @Test func anUnknownAppearanceIsRefused() {
        #expect(throws: ControlProtocolError.self) {
            try ControlMessage.decode(raw(#""command":"screenshot","path":"/tmp/a.png","appearance":"sepia","version":1,\#(holderJSON)"#))
        }
    }

    @Test func aTakeNamesItsWaitOnlyWhenItHasOne() {
        let waiting = String(decoding: ControlMessage(.controlTake(waitSeconds: 30), holder: holder).encoded(), as: UTF8.self)
        #expect(waiting.hasPrefix(#"{"command":"control.take","holder":"#))
        #expect(waiting.hasSuffix(#""json":false,"version":1,"waitSeconds":30}"#))
        let plain = String(decoding: ControlMessage(.controlTake(waitSeconds: nil), holder: holder).encoded(), as: UTF8.self)
        #expect(!plain.contains("waitSeconds"))
    }

    @Test(arguments: [-1, 3601, Int.max])
    func aWaitOutsideZeroToAnHourIsRefused(seconds: Int) {
        #expect(throws: ControlProtocolError.unreadable(
            "the control command `control.take` needs a `waitSeconds` from 0 to 3600, not \(seconds)"
        )) {
            try ControlMessage.decode(raw(#""command":"control.take","waitSeconds":\#(seconds),"version":1,\#(holderJSON)"#))
        }
    }

    @Test func onlyATakeThatWaitsHoldsItsConnectionLonger() {
        #expect(ControlRequest.controlTake(waitSeconds: 30).wait == 30)
        #expect(ControlRequest.controlTake(waitSeconds: nil).wait == 0)
        #expect(ControlRequest.controlRelease.wait == 0)
        #expect(ControlRequest.playerPlay.wait == 0)
    }

    @Test func onlyRequestsThatDriveTheAppNeedTheLease() {
        for request: ControlRequest in [.appStatus, .state, .controlTake(waitSeconds: nil), .controlTake(waitSeconds: 5), .controlRelease] {
            #expect(request.role == .free)
        }
        for request: ControlRequest in [
            .appOpen, .appQuit, .playerOpen(path: "/a.mp4"), .playerPlay, .playerPause,
            .playerSeek(seconds: 1), .screenshot(path: "/a.png", appearance: nil),
        ] {
            #expect(request.role == .operator)
        }
    }
}

@Suite struct ControlReplyTests {
    @Test func aReplyReadsBackAsItWasSent() throws {
        let term = ControlLease.Term(holder: holder, taken: Date(timeIntervalSince1970: 0), ends: Date(timeIntervalSince1970: 60))
        for reply in [
            ControlReply.done("at 0:10.000\n"),
            .done("/tmp/a.png\n", note: "captured by rendering: why\n"),
            .refused("no video is open"),
            ControlReply(ok: true, output: "video-review quit\n", lease: term),
        ] {
            #expect(try ControlReply.decode(reply.encoded()) == reply)
        }
    }

    @Test func aLeaseInAReplyHasItsTimesAsSecondsSince1970() {
        let term = ControlLease.Term(holder: holder, taken: Date(timeIntervalSince1970: 10), ends: Date(timeIntervalSince1970: 70))
        let reply = String(decoding: ControlReply(ok: true, lease: term).encoded(), as: UTF8.self)
        #expect(reply.contains(#""lease":{"ends":70,"holder":"#))
        #expect(reply.contains(#""taken":10}"#))
    }

    @Test func aReplyWithoutALeaseLeavesItOut() {
        #expect(String(decoding: ControlReply.refused("no").encoded(), as: UTF8.self) == #"{"error":"no","ok":false,"output":""}"#)
    }

    @Test func whatIsNotAReplyDoesNotRead() {
        #expect(throws: ControlProtocolError.unreadable("the app's reply doesn't read")) {
            try ControlReply.decode(Data())
        }
    }
}
