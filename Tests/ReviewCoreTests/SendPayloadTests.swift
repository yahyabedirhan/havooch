import Foundation
import ReviewCore
import Testing

/// The send as `wait` prints it: grouped by thread, with the transcript the
/// send cut, the conversation so far and the messages of this send.
@Suite("The send payload")
struct SendPayloadTests {
    static var box: Region { try! Region(x: 0.1, y: 0.1, w: 0.2, h: 0.2) }
    static var images: SendPayload.Images { SendPayload.Images(keyframe: { "/k/\($0.id).png" }, crop: { "/c/\($0.id).png" }) }

    /// The lines a transcript source gives a thread now: one line named
    /// after `word` at the thread's time.
    static func lines(_ word: String) -> (ReviewThread) -> [SendPayload.Line] {
        { thread in [SendPayload.Line(start: thread.time ?? 0, end: (thread.time ?? 0) + 1, text: "\(word) \(thread.number)")] }
    }

    /// #1 at 10 s with a moment and a region message, #2 at 15 s with a
    /// region message, and one message on General, sent as `s-1`.
    private func firstSend() throws -> (Review, Send) {
        var review = newReview()
        try review.write(text: "The title is cut off", at: 10, now: now)
        try review.write(text: "This box is too dark", at: 10, region: Self.box, now: now)
        try review.write(text: "Too fast here", at: 15, region: Self.box, now: now)
        try review.write(text: "Overall fine", at: nil, now: now)
        let sent = try review.send(at: now, transcript: Self.lines("then"))
        return (review, sent)
    }

    private func object(_ text: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    @Test("a first send groups its messages by thread, General first, each with its keyframe, crops, kept transcript and an empty history")
    func firstSendByThread() throws {
        let (review, sent) = try firstSend()
        let payload = SendPayload.assemble(review: review, send: sent, context: "About the sample", images: Self.images)

        #expect(payload.send.id == send(1))
        #expect(payload.video.title == "sample.mp4")
        #expect(payload.context == "About the sample")
        #expect(payload.threads.map(\.id) == [thread(0), thread(1), thread(2)])

        let general = payload.threads[0]
        #expect(general.number == 0 && general.time == nil && general.keyframePath == nil)
        #expect(general.transcript.isEmpty)
        #expect(general.messages.map(\.id) == [message(4)])

        let first = payload.threads[1]
        #expect(first.number == 1 && first.time == 10)
        #expect(first.keyframePath == "/k/t-f92cbb2a-1.png")
        #expect(first.transcript == [SendPayload.Line(start: 10, end: 11, text: "then 1")])
        #expect(first.history.isEmpty)
        #expect(first.messages.map(\.id) == [message(1), message(2)])
        #expect(first.messages[0].region == nil && first.messages[0].cropPath == nil)
        #expect(first.messages[1].region == Self.box && first.messages[1].cropPath == "/c/m-f92cbb2a-2.png")
        #expect(payload.threads[2].transcript == [SendPayload.Line(start: 15, end: 16, text: "then 2")])
    }

    @Test("the JSON has the spec's keys, and a key with no value is null, never left out")
    func jsonShape() throws {
        let (review, sent) = try firstSend()
        let json = try object(SendPayload.assemble(review: review, send: sent, context: nil, images: Self.images).json)

        #expect(Set(json.keys) == ["send", "video", "project", "context", "threads"])
        #expect(json["context"] is NSNull)
        // A plain video has no project, and its threads no version.
        #expect(json["project"] is NSNull)
        #expect(Set(try #require(json["send"] as? [String: Any]).keys) == ["id", "sentAt"])
        #expect(Set(try #require(json["video"] as? [String: Any]).keys) == ["path", "contentHash", "duration", "title", "demo"])
        #expect(try #require(json["video"] as? [String: Any])["demo"] as? Bool == false)
        let threads = try #require(json["threads"] as? [[String: Any]])
        #expect(Set(threads[0].keys) == ["id", "number", "time", "keyframePath", "version", "transcript", "history", "messages"])
        #expect(threads.allSatisfy { $0["version"] is NSNull })
        #expect(threads[0]["time"] is NSNull && threads[0]["keyframePath"] is NSNull)
        let messages = try #require(threads[1]["messages"] as? [[String: Any]])
        #expect(Set(messages[0].keys) == ["id", "text", "region", "cropPath"])
        #expect(messages[0]["region"] is NSNull && messages[0]["cropPath"] is NSNull)
    }

    @Test("a send on the bundled demo video, known by its content, is marked demo; any other video isn't")
    func demoVideo() throws {
        var demo = Review(video: VideoInfo(
            contentHash: DemoVideo.contentHash, title: "havooch-demo.mp4", duration: 42, path: "/Applications/Havooch.app/Contents/Resources/Demo/havooch-demo.mp4"
        ))
        try demo.write(text: "Make the title bigger", at: 3, now: now)
        let sent = try demo.send(at: now, transcript: Self.lines("then"))
        #expect(SendPayload.assemble(review: demo, send: sent, context: nil, images: Self.images).video.demo)

        let (review, other) = try firstSend()
        #expect(!SendPayload.assemble(review: review, send: other, context: nil, images: Self.images).video.demo)
    }

    @Test("a follow-up carries the conversation so far in history: person and agent messages in order, never a queued one")
    func followUpHistory() throws {
        let (first, sent) = try firstSend()
        var review = first
        try review.acknowledge(sent.id, text: "On it", now: now)                       // m-5 on General
        try review.ask(on: thread(1), question: "Which box?", now: now)                // m-6
        try review.answer(thread(1), text: "The left one", now: now)                   // m-7
        try review.reply(on: thread(1), text: "Fixed in 4e1c2aa", now: now)            // m-8
        for id in [1, 2, 3, 4] { try review.setState(message(id), .done) }
        try review.write(text: "Now make it lighter still", at: nil, to: thread(1), now: now) // m-9
        let followUp = try review.send(at: now, transcript: Self.lines("now"))
        try review.write(text: "Not sent yet", at: nil, to: thread(1), now: now)        // m-10, queued

        let payload = SendPayload.assemble(review: review, send: followUp, context: nil, images: Self.images)

        #expect(payload.threads.map(\.id) == [thread(1)])
        let entry = payload.threads[0]
        #expect(entry.messages.map(\.id) == [message(9)])
        #expect(entry.history.map(\.id) == [message(1), message(2), message(6), message(7), message(8)])
        #expect(entry.history.map(\.author) == [.person, .person, .agent, .person, .agent])
        #expect(entry.history.map(\.kind) == [.message, .message, .question, .answer, .message])
        #expect(entry.history[1].region == Self.box && entry.history[1].cropPath == "/c/m-f92cbb2a-2.png")
        #expect(entry.history[2].cropPath == nil)
        // The window is cut again for the new send.
        #expect(entry.transcript == [SendPayload.Line(start: 10, end: 11, text: "now 1")])
        #expect(payload.context == nil)
    }

    @Test("a send delivered again carries only its unfinished messages; the finished ones are history, and a finished thread is left out")
    func redelivery() throws {
        let (first, sent) = try firstSend()
        var review = first
        try review.setState(message(1), .done)
        try review.setState(message(3), .failed)
        try review.setState(message(4), .done)
        try review.reply(on: thread(1), text: "Fixed the title", now: now)             // m-5

        let payload = SendPayload.assemble(review: review, send: sent, context: nil, images: Self.images)

        #expect(payload.threads.map(\.id) == [thread(1)])
        #expect(payload.threads[0].messages.map(\.id) == [message(2)])
        #expect(payload.threads[0].history.map(\.id) == [message(1), message(5)])
        // The lines the send kept, not new ones.
        #expect(payload.threads[0].transcript == [SendPayload.Line(start: 10, end: 11, text: "then 1")])
    }

    @Test("the send cuts each frame thread's transcript once, keeps it, and reads it back from the review's file")
    func transcriptKept() throws {
        var review = newReview()
        try review.write(text: "A", at: 10, now: now)
        try review.write(text: "B", at: nil, now: now)
        var asked: [Int] = []
        let sent = try review.send(at: now) { thread in
            asked.append(thread.number)
            return Self.lines("then")(thread)
        }
        // General has no window.
        #expect(asked == [1])
        #expect(sent.transcripts == [thread(1): [SendPayload.Line(start: 10, end: 11, text: "then 1")]])

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(review)
        #expect(String(decoding: data, as: UTF8.self).contains(#""transcripts":{"t-f92cbb2a-1":"#))
        let read = try JSONDecoder().decode(Review.self, from: data)
        #expect(read.send(send(1))?.transcripts == sent.transcripts)
    }

    @Test("a send kept with no transcripts reads as one with no lines")
    func sendWithoutTranscripts() throws {
        let read = try JSONDecoder().decode(Send.self, from: Data("""
        { "id": "s-f92cbb2a-1", "sentAt": 0, "messageIDs": ["m-f92cbb2a-1"] }
        """.utf8))
        #expect(read.transcripts.isEmpty)
        #expect(read.messageIDs == [message(1)])
    }
}
