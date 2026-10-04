import Foundation
import Testing
@testable import VRCommand
import VRWire

private let table = CommandTable.standard

@Suite struct CommandTableTests {
    @Test func aCommandSendsItsRequestAndPrintsTheAppsOutput() throws {
        let app = try FakeApp()
        app.start(in: app.support)
        app.answer = { _ in .done("at 0:10.000\n") }

        let result = table.run(["player", "seek", "0:10"], environment: app.environment)

        #expect(result == CommandResult(output: "at 0:10.000\n"))
        #expect(app.requests == [.playerSeek(seconds: 10)])
    }

    @Test func jsonIsAskedOfTheAppWhereverTheFlagStands() throws {
        let app = try FakeApp()
        app.start(in: app.support)

        _ = table.run(["state", "--json"], environment: app.environment)
        _ = table.run(["--json", "player", "pause"], environment: app.environment)
        _ = table.run(["player", "play"], environment: app.environment)

        #expect(app.messages.map(\.json) == [true, true, false])
        #expect(app.requests == [.state, .playerPause, .playerPlay])
    }

    @Test func aRefusalIsOneLineOnStandardErrorAndExitOne() throws {
        let app = try FakeApp()
        app.start(in: app.support)
        app.answer = { _ in .refused("no video is open; `video-review player open <path>`") }

        let result = table.run(["player", "play"], environment: app.environment)

        #expect(result == CommandResult(error: "no video is open; `video-review player open <path>`\n", status: 1))
    }

    @Test func aCommandToAnAppThatIsNotRunningExitsOne() throws {
        let app = try FakeApp()

        let result = table.run(["state", "--json"], environment: app.environment)

        #expect(result == CommandResult(error: "video-review isn't running; `video-review app open`\n", status: 1))
    }

    @Test func aNoteFromTheAppGoesToStandardErrorWithExitZero() throws {
        let app = try FakeApp()
        app.start(in: app.support)
        app.answer = { _ in .done("/tmp/a.png\n", note: "captured by rendering: why\n") }

        let result = table.run(["screenshot", "/tmp/a.png"], environment: app.environment)

        #expect(result == CommandResult(output: "/tmp/a.png\n", error: "captured by rendering: why\n"))
    }

    @Test func noArgumentsIsTheUsageAndExitTwo() throws {
        let app = try FakeApp()
        let result = table.run([], environment: app.environment)
        #expect(result.status == 2)
        #expect(result.error.contains("usage: video-review <command>"))
        #expect(result.output.isEmpty)
    }

    @Test func helpIsTheUsageOnStandardOutput() throws {
        let app = try FakeApp()
        let result = table.run(["--help"], environment: app.environment)
        #expect(result.status == 0)
        for word in ["app", "state", "player", "screenshot"] {
            #expect(result.output.contains("  \(word) "))
        }
    }

    @Test func anUnknownCommandIsNamedAndExitsTwo() throws {
        let app = try FakeApp()
        let result = table.run(["rewind"], environment: app.environment)
        #expect(result.status == 2)
        #expect(result.error.hasPrefix("video-review: unknown command `rewind`\n"))
    }

    @Test func theVersionNamesTheVariant() throws {
        let app = try FakeApp()
        #expect(table.run(["--version"], environment: app.environment).output == "video-review \(AppIdentity.versionText)\n")
    }

    @Test func aCommandsHelpNeedsNoApp() throws {
        let app = try FakeApp()
        for command in ["app", "state", "player", "screenshot"] {
            let result = table.run([command, "--help"], environment: app.environment)
            #expect(result.status == 0)
            #expect(result.output.hasPrefix("usage: video-review \(command)"))
        }
        #expect(app.requests.isEmpty)
    }
}

@Suite struct ArgumentsTests {
    @Test(arguments: [
        ("10", 10.0), ("10.5", 10.5), ("0", 0), ("0:10", 10), ("1:02.5", 62.5), ("00:10", 10),
        ("1:00:00", 3600), ("1:02:03.25", 3723.25), ("90", 90), ("2:00", 120),
    ])
    func aTimeReadsAsSecondsOrClockTime(text: String, seconds: Double) {
        #expect(Arguments.time(text) == seconds)
    }

    @Test(arguments: ["", "abc", "-5", "1:60", "1:75", "1.5:00", "1:2:3:4", ":10", "10:", "1e3", "nan", "+5", "1:-2"])
    func whatIsNotATimeDoesNotRead(text: String) {
        #expect(Arguments.time(text) == nil)
    }
}

@Suite struct PlayerCommandTests {
    private let folder = URL(fileURLWithPath: "/Users/me/repo", isDirectory: true)

    @Test func aRelativePathIsMadeAbsoluteAgainstTheWorkingFolder() throws {
        #expect(try PlayerCommand.parse(["open", "fixtures/sample/sample.mp4"], workingDirectory: folder).get()
            == .playerOpen(path: "/Users/me/repo/fixtures/sample/sample.mp4"))
        #expect(try PlayerCommand.parse(["open", "/tmp/a.mov"], workingDirectory: folder).get() == .playerOpen(path: "/tmp/a.mov"))
        #expect(try PlayerCommand.parse(["open", "../a.mov"], workingDirectory: folder).get() == .playerOpen(path: "/Users/me/a.mov"))
    }

    @Test func playPauseAndSeekRead() throws {
        #expect(try PlayerCommand.parse(["play"], workingDirectory: folder).get() == .playerPlay)
        #expect(try PlayerCommand.parse(["pause"], workingDirectory: folder).get() == .playerPause)
        #expect(try PlayerCommand.parse(["seek", "0:10"], workingDirectory: folder).get() == .playerSeek(seconds: 10))
    }

    @Test(arguments: [
        (["seek"], "video-review player seek: missing <time>"),
        (["seek", "soon"], "video-review player seek: `soon` isn't a time; use seconds, mm:ss or h:mm:ss"),
        (["seek", "1", "2"], "video-review player seek: unexpected `2`"),
        (["open"], "video-review player open: missing <path>"),
        (["play", "now"], "video-review player play: unexpected `now`"),
        (["rewind"], "video-review player: unknown command `rewind`"),
    ])
    func argumentsThatDoNotReadAreTheUsageAndExitTwo(arguments: [String], line: String) {
        guard case .failure(let result) = PlayerCommand.parse(arguments, workingDirectory: folder) else {
            Issue.record("\(arguments) read")
            return
        }
        #expect(result.status == 2)
        #expect(result.error.hasPrefix(line + "\nusage: video-review player"))
    }
}

@Suite struct ScreenshotCommandTests {
    @Test func aPathAndAnAppearanceRead() throws {
        #expect(try ScreenshotCommand.parse(["/tmp/a.png"]).get() == .screenshot(path: "/tmp/a.png", appearance: nil))
        #expect(try ScreenshotCommand.parse(["/tmp/a.png", "--appearance", "dark"]).get()
            == .screenshot(path: "/tmp/a.png", appearance: .dark))
        #expect(try ScreenshotCommand.parse(["--appearance", "light", "/tmp/a.PNG"]).get()
            == .screenshot(path: "/tmp/a.PNG", appearance: .light))
    }

    @Test(arguments: [
        ([], "video-review screenshot: missing <abs.png>"),
        (["shot.png"], "video-review screenshot: `shot.png` isn't an absolute path"),
        (["/tmp/a.jpg"], "video-review screenshot: `/tmp/a.jpg` isn't a .png file"),
        (["/tmp/a.png", "--appearance"], "video-review screenshot: --appearance needs light or dark"),
        (["/tmp/a.png", "--appearance", "sepia"], "video-review screenshot: no appearance `sepia`; it's light or dark"),
        (["/tmp/a.png", "--big"], "video-review screenshot: unknown option `--big`"),
        (["/tmp/a.png", "/tmp/b.png"], "video-review screenshot: unexpected `/tmp/b.png`"),
    ])
    func argumentsThatDoNotReadAreTheUsageAndExitTwo(arguments: [String], line: String) {
        guard case .failure(let result) = ScreenshotCommand.parse(arguments) else {
            Issue.record("\(arguments) read")
            return
        }
        #expect(result.status == 2)
        #expect(result.error.hasPrefix(line + "\nusage: video-review screenshot"))
    }
}
