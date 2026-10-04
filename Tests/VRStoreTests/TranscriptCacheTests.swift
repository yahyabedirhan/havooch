import Foundation
import Testing
import VRStore
import VRTranscript

/// The speech transcript kept in the video's folder, by content hash.
@Suite struct TranscriptCacheTests {
    static let lines = [
        TimedLine(start: 0.5, end: 3, text: "First sentence."), TimedLine(start: 3.2, end: 6, text: "Second sentence."),
    ]

    @Test func aSavedTranscriptIsLoadedForTheSameVideoUnderAnyNameAndNotForAnother() throws {
        let folder = try ContentHashTests.Folder()
        let video = try folder.file("talk.mp4", Data("the talk".utf8))
        let renamed = try folder.file("renamed.mov", Data("the talk".utf8))
        let other = try folder.file("other.mp4", Data("another video".utf8))
        let layout = SupportLayout(root: folder.url.appendingPathComponent("support", isDirectory: true))
        let cache = TranscriptCache(layout: layout)

        #expect(cache.load(for: video) == nil)
        cache.save(Self.lines, for: video)

        #expect(cache.load(for: video) == Self.lines)
        #expect(cache.load(for: renamed) == Self.lines)
        #expect(cache.load(for: other) == nil)
        let file = layout.transcriptFile(try ContentHash.of(video))
        #expect(file.path.hasSuffix("/videos/\(try ContentHash.of(video))/transcript.json"))
        #expect(
            String(decoding: try Data(contentsOf: file), as: UTF8.self)
                == #"{"lines":[{"end":3,"start":0.5,"text":"First sentence."},{"end":6,"start":3.2,"text":"Second sentence."}],"version":1}"#
        )
    }

    @Test func anEmptyTranscriptIsKeptAsOne() throws {
        let folder = try ContentHashTests.Folder()
        let video = try folder.file("silent.mp4", Data("no speech".utf8))
        let cache = TranscriptCache(layout: SupportLayout(root: folder.url.appendingPathComponent("support", isDirectory: true)))

        cache.save([], for: video)

        #expect(cache.load(for: video) == [])
    }

    @Test func aFileThatDoesNotReadOrIsFromANewerBuildIsMovedAsideAndCountsAsNone() throws {
        let folder = try ContentHashTests.Folder()
        let video = try folder.file("talk.mp4", Data("the talk".utf8))
        let layout = SupportLayout(root: folder.url.appendingPathComponent("support", isDirectory: true))
        let cache = TranscriptCache(layout: layout)
        let file = layout.transcriptFile(try ContentHash.of(video))
        let aside = file.deletingLastPathComponent().appendingPathComponent("transcript.unreadable.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)

        for kept in ["not json", #"{"lines":[],"version":2}"#] {
            try Data(kept.utf8).write(to: file)

            #expect(cache.load(for: video) == nil)
            #expect(!FileManager.default.fileExists(atPath: file.path))
            #expect(String(decoding: try Data(contentsOf: aside), as: UTF8.self) == kept)
        }
    }

    @Test func aVideoThatIsNotThereHasNoTranscriptAndSavingForItDoesNothing() throws {
        let folder = try ContentHashTests.Folder()
        let cache = TranscriptCache(layout: SupportLayout(root: folder.url.appendingPathComponent("support", isDirectory: true)))
        let missing = folder.url.appendingPathComponent("missing.mp4")

        cache.save(Self.lines, for: missing)

        #expect(cache.load(for: missing) == nil)
    }
}
