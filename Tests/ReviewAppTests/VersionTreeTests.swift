import Foundation
@testable import ReviewApp
import ReviewCore
import Testing

/// A project's thread list by version (thread-list V5), as a
/// pure value: General, then the last three versions newest first, the
/// one on screen and the versions picked from "All versions"; the
/// versions with no section and their open threads; and the menu of
/// every version with its search.
@Suite("Thread list by version, as a value")
struct VersionTreeTests {
    static let hash8 = "f92cbb2a"
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// A project of `count` versions, `/Movies/cut1.mp4` first; v2 has a label.
    static func outline(_ count: Int) -> ProjectOutline {
        ProjectOutline(
            slug: "launch-video", title: "Launch video",
            versions: (1...count).map { .init(path: "/Movies/cut\($0).mp4", label: $0 == 2 ? "lower third" : nil) }
        )
    }

    /// Thread `number` on version `version` (nil for General, 0 for a
    /// removed version), with one message of the person's in `state`.
    static func thread(_ number: Int, on version: Int?, _ state: MessageState = .done) -> ReviewThread {
        let message = Message(
            id: MessageID(.message, hash8: hash8, number: number), author: .person, kind: .message,
            text: "Note \(number)", at: now, state: state
        )
        return ReviewThread(
            id: ThreadID(.thread, hash8: hash8, number: number), time: version == nil ? nil : Double(number),
            messages: version == nil ? [] : [message],
            anchor: version.map { VersionAnchor(path: "/Movies/\($0 == 0 ? "gone" : "cut\($0)").mp4") }
        )
    }

    static let threads = [
        thread(0, on: nil),
        thread(1, on: 1, .queued),
        thread(2, on: 2),
        thread(3, on: 5, .working),
        thread(4, on: 6, .queued),
        thread(5, on: 6),
        thread(6, on: 0, .queued),
    ]

    @Test("General first, then the last three versions newest first; the one on screen is marked; nothing is picked")
    func recent() {
        let tree = VersionTree(outline: Self.outline(6), threads: Self.threads, onScreen: 6, picked: [])
        #expect(tree.general.map(\.number) == [0])
        #expect(tree.sections.map(\.kind) == [.version(6), .version(5), .version(4), .removed])
        #expect(tree.sections.map(\.isOnScreen) == [true, false, false, false])
        #expect(tree.sections.map(\.isPicked) == [false, false, false, false])
        #expect(tree.sections[0].threads.map(\.number) == [4, 5])
        #expect(tree.sections[2].threads.isEmpty)
        // A thread whose version left the list stays, in its own section.
        #expect(tree.sections[3].threads.map(\.number) == [6])
        #expect(tree.showing == "Showing v4 to v6")
        #expect(tree.older == [3, 2, 1])
        // v1's queued thread is open; v2's is done.
        #expect(tree.stillOpen.map(\.number) == [1])
    }

    @Test("a version picked from the menu adds its section under the recent ones, the latest pick first, closable")
    func picked() {
        let tree = VersionTree(outline: Self.outline(6), threads: Self.threads, onScreen: 6, picked: [1, 2])
        #expect(tree.sections.map(\.kind) == [.version(6), .version(5), .version(4), .version(1), .version(2), .removed])
        #expect(tree.sections.map(\.isPicked) == [false, false, false, true, true, false])
        #expect(tree.sections[4].label == "lower third")
        #expect(tree.showing == "Showing v4 to v6, v1, v2")
        #expect(tree.older == [3])
        #expect(tree.stillOpen.isEmpty)
    }

    @Test("an older version on screen has a section of its own, marked, and not closable")
    func olderOnScreen() {
        let tree = VersionTree(outline: Self.outline(6), threads: Self.threads, onScreen: 2, picked: [2, 9])
        #expect(tree.sections.map(\.kind) == [.version(6), .version(5), .version(4), .version(2), .removed])
        #expect(tree.sections.map(\.isOnScreen) == [false, false, false, true, false])
        #expect(tree.sections.map(\.isPicked) == [false, false, false, false, false])
        // A picked number outside the list is left out.
        #expect(tree.older == [3, 1])
    }

    @Test("a project of fewer than three versions shows them all; with no removed thread there is no removed section")
    func short() {
        let threads = [Self.thread(0, on: nil), Self.thread(1, on: 1)]
        let tree = VersionTree(outline: Self.outline(2), threads: threads, onScreen: 2, picked: [])
        #expect(tree.sections.map(\.kind) == [.version(2), .version(1)])
        #expect(tree.showing == "Showing v1 to v2")
        #expect(tree.older.isEmpty)
        let one = VersionTree(outline: Self.outline(1), threads: threads, onScreen: 1, picked: [])
        #expect(one.showing == "Showing v1")
    }

    @Test("the menu lists the versions in the list, the older ones with open threads, and every older one, newest first")
    func menu() {
        let tree = VersionTree(outline: Self.outline(6), threads: Self.threads, onScreen: 6, picked: [])
        let menu = AllVersionsMenu(tree: tree, query: "")
        #expect(menu.inList.map(\.number) == [6, 5, 4])
        #expect(menu.stillOpen.map(\.number) == [1])
        #expect(menu.older.map(\.number) == [3, 2, 1])
        #expect(menu.inList[0].isOnScreen)
        #expect(menu.inList[0].threads.map(\.number) == [4, 5])
        #expect(menu.inList[0].open == 1)
        #expect(menu.older[1].label == "lower third")
        #expect(!menu.isEmpty)
    }

    @Test("the menu's search takes a number, with or without v, or words of a label")
    func search() {
        let tree = VersionTree(outline: Self.outline(12), threads: Self.threads, onScreen: 12, picked: [])
        #expect(AllVersionsMenu(tree: tree, query: "v1").older.map(\.number) == [1])
        #expect(AllVersionsMenu(tree: tree, query: "1").inList.map(\.number) == [12, 11, 10])
        #expect(AllVersionsMenu(tree: tree, query: " V2 ").older.map(\.number) == [2])
        #expect(AllVersionsMenu(tree: tree, query: "Lower").older.map(\.number) == [2])
        let none = AllVersionsMenu(tree: tree, query: "music")
        #expect(none.isEmpty)
    }
}
