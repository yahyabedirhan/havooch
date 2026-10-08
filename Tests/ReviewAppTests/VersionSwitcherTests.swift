import Foundation
@testable import ReviewApp
import ReviewCore
import ReviewLease
import ReviewStore
import ReviewWire
import Testing

/// The version switcher's words and numbers (E10, version-switcher V5),
/// pure: the last three versions as segments, the field for older ones,
/// the picker's search and its highlight.
@Suite("The version switcher")
struct VersionSwitchTests {
    static func versions(_ count: Int, current: Int?, labels: [Int: String] = [:]) -> VersionSwitch {
        VersionSwitch(
            versions: (1...count).map { VersionSwitch.Entry(number: $0, label: labels[$0], threads: $0 % 3, made: "Oct \($0)") },
            current: current
        )
    }

    @Test("a project of three versions or fewer shows each as a segment, with no field")
    func fewVersions() {
        let three = Self.versions(3, current: 2)
        #expect(three.recent.map(\.number) == [1, 2, 3])
        #expect(!three.hasOlder)
        #expect(three.field == nil)
        #expect(!three.isOld)
        #expect(Self.versions(1, current: 1).recent.map(\.number) == [1])
    }

    @Test("with more versions the last three are segments, and the field says All N while a recent one is on screen")
    func recentOnScreen() {
        let fifty = Self.versions(50, current: 50)
        #expect(fifty.recent.map(\.number) == [48, 49, 50])
        #expect(fifty.hasOlder)
        #expect(!fifty.isOld)
        #expect(fifty.field == "All 50")
    }

    @Test("the field names an older version while it is on screen")
    func oldOnScreen() {
        let fifty = Self.versions(50, current: 12)
        #expect(fifty.isOld)
        #expect(fifty.field == "v12")
        // A removed version on screen selects nothing.
        let removed = Self.versions(50, current: nil)
        #expect(!removed.isOld)
        #expect(removed.field == "All 50")
        #expect(removed.onScreen == nil)
    }

    @Test("the picker lists every version newest first, and typing filters by number or label", arguments: [
        ("", 50, 50), ("1", 11, 19), ("v1", 11, 19), ("V12", 1, 12), ("alt", 1, 12), ("ALT OP", 1, 12), ("  ", 50, 50),
        ("v", 50, 50), ("99", 0, nil), ("cut", 1, 1),
    ] as [(String, Int, Int?)])
    func matches(query: String, count: Int, first: Int?) {
        let fifty = Self.versions(50, current: 50, labels: [12: "alt opening", 1: "first cut"])
        let found = fifty.matches(query)
        #expect(found.count == count)
        #expect(found.first?.number == first)
        #expect(found.map(\.number) == found.map(\.number).sorted(by: >))
    }

    @Test("a version's line under the title is its name with its label, else when it was made")
    func line() {
        #expect(VersionSwitch.Entry(number: 2, label: "tighter intro", threads: 0, made: "today").line == "v2 · tighter intro")
        #expect(VersionSwitch.Entry(number: 3, label: nil, threads: 0, made: "Oct 6").line == "v3 · Oct 6")
        #expect(VersionSwitch.Entry(number: 4, label: nil, threads: 0, made: nil).line == "v4")
    }

    @Test("when a version was made reads today, yesterday, else the month and the day")
    func made() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 12)))
        #expect(VersionSwitch.made(now.addingTimeInterval(-3600), now: now, calendar: calendar) == "today")
        #expect(VersionSwitch.made(now.addingTimeInterval(-86400), now: now, calendar: calendar) == "yesterday")
        #expect(VersionSwitch.made(now.addingTimeInterval(-86400 * 2), now: now, calendar: calendar) == "Oct 6")
        #expect(VersionSwitch.made(now.addingTimeInterval(-86400 * 14), now: now, calendar: calendar) == "Sep 24")
    }

    @Test("the picker highlights the first row, Up and Down move inside the rows, and a filtered-out row gives way to the first")
    func highlight() {
        let matches = Self.versions(5, current: 5).matches("")
        var picker = VersionPicker()
        #expect(picker.highlight(in: matches) == 5)
        picker = picker.moved(by: 1, in: matches)
        #expect(picker.highlight(in: matches) == 4)
        picker = picker.moved(by: 10, in: matches)
        #expect(picker.highlight(in: matches) == 1)
        picker = picker.moved(by: -1, in: matches)
        #expect(picker.highlight(in: matches) == 2)
        picker = picker.moved(by: -10, in: matches)
        #expect(picker.highlight(in: matches) == 5)
        let narrowed = Self.versions(5, current: 5).matches("3")
        #expect(VersionPicker(query: "3", highlighted: 4).highlight(in: narrowed) == 3)
        #expect(VersionPicker().highlight(in: []) == nil)
        #expect(VersionPicker().moved(by: 1, in: []) == VersionPicker())
    }

    @Test("in a project the header says the project's title, and under it the version, then the folder")
    func headerWords() {
        let words = HeaderWords(
            video: URL(fileURLWithPath: "/Users/me/Movies/Launch/cut2.mp4"), isDemo: false,
            project: HeaderWords.Project(title: "Launch video", version: "v2 · tighter intro"), home: "/Users/me"
        )
        #expect(words.isProject)
        #expect(words.title == "Launch video")
        #expect(words.subtitle == "v2 · tighter intro")
        #expect(words.folder == "~/Movies/Launch")
        #expect(words.fullPath == "/Users/me/Movies/Launch")
        let demo = HeaderWords(
            video: URL(fileURLWithPath: "/demo/cut.mp4"), isDemo: true, project: HeaderWords.Project(title: "Launch", version: "v1")
        )
        #expect(demo.folder == "Demo")
        // A plain video has no project words, and no switcher.
        let plain = HeaderWords(video: URL(fileURLWithPath: "/Users/me/Movies/sample.mp4"), isDemo: false, home: "/Users/me")
        #expect(!plain.isProject)
        #expect(plain.folder == nil)
        #expect(plain.title == "sample.mp4")
    }
}

/// The version switcher in a window (E10), through the app model and its
/// control server with no scene and no socket: `version show` keeps the
/// playhead's time, the field names an older version, the picker opens
/// with a search, and a plain video has no switcher.
@Suite("Switching versions", .serialized)
struct VersionSwitcherTests {
    static let operatorHolder = Holder(key: "codex-1", name: "Codex", place: "/Users/me/shop")
    static let sample = MessageTests.fixture.standardizedFileURL
    static let launch = WindowTests.launch.standardizedFileURL

    let support = FileManager.default.temporaryDirectory
        .appendingPathComponent("havooch-tests-\(UUID().uuidString)", isDirectory: true)

    private func cleanUp() {
        try? FileManager.default.removeItem(at: support)
    }

    /// The app on a fresh folder with the lease held, the server in front
    /// of it, and `w1` holding the project `launch-video`: v1 the sample,
    /// v2 the launch video, then `more` copies of the sample, the last on
    /// screen.
    private func run(more: Int = 0) async throws -> (app: AppModel, window: WindowModel, server: ControlServer) {
        let app = AppModel(environment: [SupportFolder.overrideVariable: support.path, MutedRun.variable: "1"], speech: SlowRecognizer())
        let window = app.makeWindow()
        try await window.open(Self.sample)
        let server = ControlServer(
            socket: URL(fileURLWithPath: "/nowhere/control.sock"), app: app, listeners: { app.listeners },
            screenshotter: ControlServerTests.FakeScreenshotter(), quit: {}
        )
        #expect(await ask(.projectNew(slug: "launch-video", path: Self.sample.path, title: "Launch video"), server).ok)
        #expect(await ask(.projectAdd(slug: "launch-video", path: Self.launch.path, label: "tighter intro"), server).ok)
        let cuts = support.appendingPathComponent("cuts", isDirectory: true)
        try FileManager.default.createDirectory(at: cuts, withIntermediateDirectories: true)
        for number in stride(from: 3, through: 2 + more, by: 1) {
            let copy = cuts.appendingPathComponent("cut\(number).mp4")
            try FileManager.default.copyItem(at: Self.sample, to: copy)
            #expect(await ask(.projectAdd(slug: "launch-video", path: copy.path, label: number == 3 ? "alt opening" : nil), server).ok)
        }
        #expect(await ask(.controlTake(waitSeconds: nil), server).ok)
        return (app, window, server)
    }

    private func ask(_ request: ControlRequest, _ server: ControlServer, json: Bool = false) async -> ControlReply {
        await server.replyWritten(to: request.sent(by: Self.operatorHolder, json: json)).reply
    }

    private func object(_ output: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
    }

    @Test("version show puts the version on screen and the playhead keeps its time; state reports the switcher")
    func showKeepsTime() async throws {
        defer { cleanUp() }
        let (app, window, server) = try await run()
        #expect(window.versionNumber == 2)
        try await window.seek(to: 1.5)

        let shown = await ask(.versionShow(number: 1), server)
        #expect(shown.ok)
        #expect(shown.output == "v1 on screen in w1 at 0:01.5\n")
        #expect(window.versionNumber == 1)
        #expect(window.video?.url == Self.sample)
        #expect(abs(window.engine.time - 1.5) < 0.05)
        #expect(!window.engine.isPlaying)

        let state = try object(await ask(.state, server, json: true).output)
        let project = try #require(state["project"] as? [String: Any])
        #expect(project["version"] as? Int == 1)
        let switcher = try #require(project["switcher"] as? [String: Any])
        #expect(switcher["segments"] as? [Int] == [1, 2])
        #expect(switcher["selected"] as? Int == 1)
        #expect(switcher["field"] is NSNull)
        #expect(switcher["picker"] is NSNull)
        #expect(await ask(.state, server).output.contains("switcher: [v1] v2\n"))

        // The version on screen again changes nothing; one outside the list is refused.
        #expect(await ask(.versionShow(number: 1), server).ok)
        #expect(abs(window.engine.time - 1.5) < 0.05)
        #expect(await ask(.versionShow(number: 9), server).error == "the project launch-video has no v9; it has v1 to v2")
        // A project of two versions has no picker.
        #expect(await ask(.versionPick(), server).error
            == "the project has 2 versions, each one a segment; the picker is for a project of more than 3")
        app.listeners.stop()
    }

    @Test("a playing video plays on in the version switched to, and a time past its end stops at its end")
    func playsOnAndClamps() async throws {
        defer { cleanUp() }
        let (app, window, _) = try await run()
        // v2 is the launch video, longer than v1, the sample.
        try await window.switchVersion(to: 1)
        let shorter = window.engine.duration
        try await window.switchVersion(to: 2)
        #expect(window.engine.duration > shorter + 1)
        try await window.seek(to: shorter + 1)
        try await window.switchVersion(to: 1)
        #expect(abs(window.engine.time - shorter) < 0.1)

        try await window.seek(to: 0.5)
        try window.play()
        try await window.switchVersion(to: 2)
        #expect(window.engine.isPlaying)
        #expect(window.engine.time < 1.5)
        try window.pause()
        app.listeners.stop()
    }

    @Test("a switch keeps the sidebar's view, the composer's words and the notices, and drops the drawn region")
    func keepsTheSidebar() async throws {
        defer { cleanUp() }
        let (app, window, _) = try await run()
        _ = try await window.addMessage(text: "Logo too small", at: 1)
        _ = try await window.showThread("1")
        window.composerText = "And the colour"
        _ = try window.compose(text: "And the colour", region: try Region(x: 0.1, y: 0.1, w: 0.2, h: 0.2), general: false)
        #expect(window.composerRegion != nil)

        try await window.switchVersion(to: 1)
        #expect(window.sidebarReport.thread != nil)
        #expect(window.composerText == "And the colour")
        #expect(window.composerRegion == nil)
        app.listeners.stop()
    }

    @Test("the field names an older version on screen, and the picker opens with a search, moves, and closes")
    func fieldAndPicker() async throws {
        defer { cleanUp() }
        let (app, window, server) = try await run(more: 3)
        #expect(window.versionNumber == 5)
        var switcher = try #require(window.versionSwitch)
        #expect(switcher.recent.map(\.number) == [3, 4, 5])
        #expect(switcher.field == "All 5")
        #expect(switcher.entry(3)?.label == "alt opening")
        #expect(switcher.entry(2)?.made != nil)

        let picked = await ask(.versionPick(query: "v"), server)
        #expect(picked.output == "the version picker is open: 5 of 5 versions match `v`, v5 highlighted\n")
        let open = try object(await ask(.versionPick(query: "alt"), server, json: true).output)
        let picker = try #require(((open["project"] as? [String: Any])?["switcher"] as? [String: Any])?["picker"] as? [String: Any])
        #expect(picker["query"] as? String == "alt")
        #expect(picker["matches"] as? [Int] == [3])
        #expect(picker["highlighted"] as? Int == 3)

        // Typing and Up and Down, as the picker's field takes them.
        window.typeVersionQuery("")
        window.moveVersionHighlight(by: 3)
        #expect(window.state().project?.switcher?.picker?.highlighted == 2)
        window.openHighlightedVersion()
        let deadline = ContinuousClock.now + .seconds(10)
        while window.versionNumber != 2, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(window.versionNumber == 2)
        #expect(window.versionPicker == nil)

        // v1 is older than the segments: the field names it.
        #expect(await ask(.versionShow(number: 1), server).ok)
        switcher = try #require(window.versionSwitch)
        #expect(switcher.isOld)
        #expect(switcher.field == "v1")
        #expect(await ask(.state, server).output.contains("switcher: v3 v4 v5, [v1]\n"))
        // The thread list agrees: v1 on screen has its own marked section.
        #expect(window.state().sidebar?.versions?.onScreen == 1)
        #expect(window.state().sidebar?.versions?.sections.contains(1) == true)

        // A thread of another version shown from the list moves the switcher with it.
        try await window.switchVersion(to: 2)
        _ = try await window.addMessage(text: "Logo too small", at: 1)
        #expect(await ask(.versionShow(number: 5), server).ok)
        let onV2 = try #require(window.threads.first { $0.anchor?.path == Self.launch.path })
        _ = try await window.showThread(onV2.id.text)
        #expect(window.versionSwitch?.current == 2)
        #expect(window.state().project?.switcher?.selected == 2)
        #expect(window.state().sidebar?.versions?.onScreen == 2)

        // Escape and version close close the picker.
        _ = try window.openVersionPicker()
        #expect(window.escape())
        #expect(window.versionPicker == nil)
        #expect(await ask(.versionPick(), server).ok)
        let closed = await ask(.versionClose, server)
        #expect(closed.output == "the version picker is closed\n")
        #expect(await ask(.versionClose, server).output == "the version picker wasn't open\n")
        app.listeners.stop()
    }

    @Test("a plain video shows no switcher, and version show and pick are refused on it")
    func plainVideo() async throws {
        defer { cleanUp() }
        let app = AppModel(environment: [SupportFolder.overrideVariable: support.path, MutedRun.variable: "1"], speech: SlowRecognizer())
        let window = app.makeWindow()
        try await window.open(Self.sample)
        let server = ControlServer(
            socket: URL(fileURLWithPath: "/nowhere/control.sock"), app: app, listeners: { app.listeners },
            screenshotter: ControlServerTests.FakeScreenshotter(), quit: {}
        )
        #expect(await ask(.controlTake(waitSeconds: nil), server).ok)
        #expect(window.versionSwitch == nil)
        #expect(window.projectWords == nil)
        #expect(window.state().project == nil)
        let refusal = "this window holds a plain video, which has no versions; `project new` makes it a project"
        #expect(await ask(.versionShow(number: 1), server).error == refusal)
        #expect(await ask(.versionPick(), server).error == refusal)
        app.listeners.stop()
    }
}
