import Foundation
import ReviewStore
import ReviewTranscript
import Testing

@Suite("The kept transcript")
struct TranscriptFilesTests {
    @Test("a transcript is kept as transcript.json in the video's folder and reads back the same")
    func roundTrip() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let files = TranscriptFiles(support: scratch.folder)
        let transcript = Transcript(
            source: .speech, lines: [TranscriptLine(start: 0.2, end: 5.1, text: "This is Video Review.")], complete: true
        )
        #expect(files.load("abc") == nil)

        files.save(transcript, contentHash: "abc")

        #expect(files.file(of: "abc").path == scratch.folder.path + "/videos/abc/transcript.json")
        #expect(files.load("abc") == transcript)
        #expect(files.load("other") == nil)
    }

    @Test("a file that isn't a transcript reads as none")
    func unreadable() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let files = TranscriptFiles(support: scratch.folder)
        try FileManager.default.createDirectory(at: files.file(of: "abc").deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{".utf8).write(to: files.file(of: "abc"))
        #expect(files.load("abc") == nil)
    }
}
