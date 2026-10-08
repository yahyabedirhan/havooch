import Foundation
@testable import ReviewApp
import ReviewCore
import ReviewLease
import ReviewWire
import Testing

/// A project's thread list by version (decision E9, thread-list V5),
/// through the app model and its control server: `state` reports the
/// sections, the older versions and their open threads; `thread versions`
/// opens "All versions" with its search; `thread version <n>` adds an older
/// version's section and `--remove` takes it out; a plain video's list
/// stays by group.
@Suite("Thread list by version", .serialized)
struct VersionListTests {
    static let claude = Holder(key: "claude-1", name: "Claude Code", place: "/Users/me/shop")

    let support = FileManager.default.temporaryDirectory
        .appendingPathComponent("havooch-tests-\(UUID().uuidString)", isDirectory: true)

    private func cleanUp() {
        try? FileManager.default.removeItem(at: support)
    }

    /// The sample open in `w1` with a message queued at 0:02, made the
    /// project `launch-video`, then three more versions added: copies of
    /// the sample, so v4 is on screen and v1 has an open thread.
    private func project() async throws -> (window: WindowModel, server: ControlServer) {
        let app = AppModel(environment: [SupportFolder.overrideVariable: support.path], speech: SlowRecognizer())
        let window = app.makeWindow()
        try await window.open(ProjectTests.cut1)
        _ = try await window.addMessage(text: "Too fast here", at: 2)
        let server = ControlServer(
            socket: URL(fileURLWithPath: "/nowhere/control.sock"), app: app, listeners: { app.listeners },
            screenshotter: ControlServerTests.FakeScreenshotter(), quit: {}
        )
        #expect(await ask(.projectNew(slug: "launch-video", path: ProjectTests.cut1.path), server).ok)
        let cuts = support.appendingPathComponent("cuts", isDirectory: true)
        try FileManager.default.createDirectory(at: cuts, withIntermediateDirectories: true)
        for number in 2...4 {
            let copy = cuts.appendingPathComponent("cut\(number).mp4")
            try FileManager.default.copyItem(at: ProjectTests.cut1, to: copy)
            #expect(await ask(.projectAdd(slug: "launch-video", path: copy.path, label: number == 2 ? "lower third" : nil), server).ok)
        }
        return (window, server)
    }

    private func ask(_ request: ControlRequest, _ server: ControlServer, json: Bool = false) async -> ControlReply {
        await server.replyWritten(to: request.sent(by: Self.claude, json: json)).reply
    }

    /// `sidebar.versions` of `state --json`.
    private func versions(_ server: ControlServer) async throws -> [String: Any] {
        let output = await ask(.state, server, json: true).output
        let state = try #require(try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        let sidebar = try #require(state["sidebar"] as? [String: Any])
        return try #require(sidebar["versions"] as? [String: Any])
    }

    @Test("the list shows the last three versions, v4 on screen; v1 is older, with its open thread in the footer")
    func sections() async throws {
        defer { cleanUp() }
        let (window, server) = try await project()
        let versions = try await versions(server)
        #expect(versions["sections"] as? [Int] == [4, 3, 2])
        #expect(versions["onScreen"] as? Int == 4)
        #expect(versions["picked"] as? [Int] == [])
        #expect(versions["older"] as? [Int] == [1])
        #expect(versions["showing"] as? String == "Showing v2 to v4")
        #expect(versions["removedSection"] as? Bool == false)
        let thread = try #require(window.threads.first { $0.number == 1 })
        #expect(versions["stillOpen"] as? [String] == [thread.id.text])
        #expect(versions["menu"] is NSNull)
        let tree = try #require(window.versionTree)
        #expect(tree.general.map(\.number) == [0])
        #expect(tree.sections[2].label == "lower third")
        #expect(ThreadListSummary.line(threads: window.threads, queued: window.queuedCount, versions: 4)
            == "2 threads · 4 versions · 1 queued")
        window.app.listeners.stop()
    }

    @Test("All versions opens with its search, groups the older versions with open threads, and closes")
    func menu() async throws {
        defer { cleanUp() }
        let (window, server) = try await project()
        let opened = await ask(.threadVersionsOpen(search: "v1"), server)
        #expect(opened.ok)
        #expect(opened.output == "All versions is open\n")
        var menu = try #require(try await versions(server)["menu"] as? [String: Any])
        #expect(menu["search"] as? String == "v1")
        #expect(menu["inList"] as? [Int] == [])
        #expect(menu["stillOpen"] as? [Int] == [1])
        #expect(menu["older"] as? [Int] == [1])

        // The search keeps its words when it opens again with none.
        #expect(await ask(.threadVersionsOpen(search: nil), server).ok)
        #expect(window.versionMenu == "v1")
        #expect(await ask(.threadVersionsOpen(search: ""), server).ok)
        menu = try #require(try await versions(server)["menu"] as? [String: Any])
        #expect(menu["inList"] as? [Int] == [4, 3, 2])

        #expect(await ask(.threadVersionsClose, server).ok)
        #expect(try await versions(server)["menu"] is NSNull)

        // Escape closes it too.
        #expect(await ask(.threadVersionsOpen(search: nil), server).ok)
        #expect(window.escape())
        #expect(window.versionMenu == nil)
        window.app.listeners.stop()
    }

    @Test("picking an older version adds its section, closes the menu and scrolls to it; --remove takes it out")
    func pick() async throws {
        defer { cleanUp() }
        let (window, server) = try await project()
        #expect(await ask(.threadVersionsOpen(search: nil), server).ok)
        let picked = await ask(.threadVersion(number: 1, remove: false), server)
        #expect(picked.ok)
        #expect(picked.output == "the thread list shows v1\n")
        var versions = try await versions(server)
        #expect(versions["sections"] as? [Int] == [4, 3, 2, 1])
        #expect(versions["picked"] as? [Int] == [1])
        #expect(versions["older"] as? [Int] == [])
        #expect(versions["stillOpen"] as? [String] == [])
        #expect(versions["showing"] as? String == "Showing v2 to v4, v1")
        #expect(versions["menu"] is NSNull)
        #expect(window.versionJump?.number == 1)
        // v1's thread keeps its state in its section.
        let section = try #require(window.versionTree?.sections.last)
        #expect(section.threads.map(\.number) == [1])
        #expect(section.threads.first?.state == .queued)

        // A recent version only scrolls: it has its section already.
        #expect(await ask(.threadVersion(number: 3, remove: false), server).ok)
        #expect(window.pickedVersions == [1])
        #expect(window.versionJump?.number == 3)

        // Only a picked version leaves the list.
        let recent = await ask(.threadVersion(number: 3, remove: true), server)
        #expect(recent.error.contains("v3 isn't picked from All versions"))
        let outside = await ask(.threadVersion(number: 9, remove: false), server)
        #expect(outside.error.contains("the project has no v9; it has v1 to v4"))
        let removed = await ask(.threadVersion(number: 1, remove: true), server)
        #expect(removed.ok)
        #expect(removed.output == "v1 left the thread list\n")
        versions = try await self.versions(server)
        #expect(versions["sections"] as? [Int] == [4, 3, 2])
        #expect(versions["older"] as? [Int] == [1])
        window.app.listeners.stop()
    }

    @Test("an old thread stays usable: showing it puts its version on screen, marked in its own section")
    func oldThread() async throws {
        defer { cleanUp() }
        let (window, server) = try await project()
        let thread = try #require(window.threads.first { $0.number == 1 })
        #expect(await ask(.threadShow(thread: thread.id.text), server).ok)
        #expect(window.versionNumber == 1)
        let versions = try await versions(server)
        #expect(versions["sections"] as? [Int] == [4, 3, 2, 1])
        #expect(versions["onScreen"] as? Int == 1)
        #expect(versions["picked"] as? [Int] == [])
        // A version on screen has no close button.
        let removed = await ask(.threadVersion(number: 1, remove: true), server)
        #expect(!removed.ok)
        window.app.listeners.stop()
    }

    @Test("a plain video's list stays by group: no versions in state, and the version commands are refused")
    func plainVideo() async throws {
        defer { cleanUp() }
        let app = AppModel(environment: [SupportFolder.overrideVariable: support.path], speech: SlowRecognizer())
        let window = app.makeWindow()
        try await window.open(ProjectTests.cut1)
        let server = ControlServer(
            socket: URL(fileURLWithPath: "/nowhere/control.sock"), app: app, listeners: { app.listeners },
            screenshotter: ControlServerTests.FakeScreenshotter(), quit: {}
        )
        #expect(window.versionTree == nil)
        let output = await ask(.state, server, json: true).output
        let state = try #require(try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        #expect((state["sidebar"] as? [String: Any])?["versions"] is NSNull)
        let refused = await ask(.threadVersionsOpen(search: nil), server)
        #expect(refused.error.contains("the thread list shows versions only in a project"))
        #expect(!(await ask(.threadVersion(number: 1, remove: false), server)).ok)
        app.listeners.stop()
    }
}
