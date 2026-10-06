import Foundation
import ReviewWire
import Testing
@testable import ReviewApp

@Suite("The header's words")
struct HeaderTests {
    @Test("the title is the file name with its extension, and the subtitle its folder with the home as ~")
    func titleAndFolder() {
        let words = HeaderWords(video: URL(fileURLWithPath: "/Users/me/Movies/sample.mp4"), isDemo: false, home: "/Users/me")
        #expect(words.title == "sample.mp4")
        #expect(words.subtitle == "~/Movies")
        #expect(words.fullPath == "/Users/me/Movies")
    }

    @Test("a long folder is shortened in the middle, and the full path stays for the hover")
    func longFolder() throws {
        let folder = "/Volumes/Archive/Clients/Northwind/2026/Launch film/Review round 3/Exports"
        let words = HeaderWords(video: URL(fileURLWithPath: folder + "/cut.mov"), isDemo: false, home: "/Users/me")
        let subtitle = try #require(words.subtitle)
        #expect(subtitle.count == HeaderWords.subtitleLimit)
        #expect(subtitle.hasPrefix("/Volumes/Archive"))
        #expect(subtitle.hasSuffix("round 3/Exports"))
        #expect(subtitle.contains("…"))
        #expect(words.fullPath == folder)
    }

    @Test("demo mode says Demo, and no video shows the app's name")
    func demoAndEmpty() {
        let demo = HeaderWords(video: URL(fileURLWithPath: "/Applications/Havooch.app/Contents/Resources/Demo/sample.mp4"), isDemo: true)
        #expect(demo.title == "sample.mp4")
        #expect(demo.subtitle == "Demo")

        let empty = HeaderWords(video: nil, isDemo: false)
        #expect(empty.title == AppIdentity.appName)
        #expect(empty.subtitle == nil)
        #expect(HeaderWords(video: nil, isDemo: true).subtitle == "Demo")
    }

    @Test("shortening keeps short text, and the home folder alone is ~")
    func shortening() {
        #expect(HeaderWords.shortened("~/Movies", to: 56) == "~/Movies")
        #expect(HeaderWords.shortened("abcdefghij", to: 5) == "ab…ij")
        #expect(HeaderWords.tilde("/Users/me", home: "/Users/me") == "~")
        #expect(HeaderWords.tilde("/Users/meg/x", home: "/Users/me") == "/Users/meg/x")
    }

    @Test("a demo started from the empty screen runs on a folder of its own under the temporary folder")
    func demoFolder() {
        let folder = DemoRun.folder(temporary: URL(fileURLWithPath: "/tmp/me", isDirectory: true))
        #expect(folder.path == "/tmp/me/\(AppIdentity.appName) Demo")
    }
}
