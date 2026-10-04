import Foundation
import Testing
@testable import VRCommand
import VRWire

private let table = CommandTable.standard

/// A demo folder that exists: the repo's fixture.
private let fixture = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("fixtures/sample", isDirectory: true)
    .standardizedFileURL

@Suite struct AppCommandTests {
    @Test func statusAsksTheRunningApp() throws {
        let app = try FakeApp()
        app.start(in: app.support)
        app.answer = { _ in .done("video-review 0.1.0 is running\n") }

        let result = table.run(["app", "status"], environment: app.environment)

        #expect(result == CommandResult(output: "video-review 0.1.0 is running\n"))
        #expect(app.requests == [.appStatus])
    }

    @Test func statusOfAnAppThatIsNotRunningExitsOne() throws {
        let app = try FakeApp()
        let result = table.run(["app", "status"], environment: app.environment)
        #expect(result.status == 1)
        #expect(app.launches.isEmpty)
    }

    @Test func openLaunchesTheAppWhenItDoesNotRunAndWaitsUntilItAnswers() throws {
        let app = try FakeApp()
        app.answer = { _ in .done("running\n") }

        let result = table.run(["app", "open"], environment: app.environment)

        #expect(result == CommandResult(output: "running\n"))
        #expect(app.launches.count == 1)
        #expect(app.launches.first?.bundleID == AppIdentity.bundleID)
        #expect(app.launches.first?.environment == [:])
        #expect(app.requests == [.appStatus])
    }

    @Test func openOfARunningAppAsksItAndLaunchesNothing() throws {
        let app = try FakeApp()
        app.start(in: app.support)

        let result = table.run(["app", "open"], environment: app.environment)

        #expect(result.status == 0)
        #expect(app.requests == [.appOpen])
        #expect(app.launches.isEmpty)
    }

    @Test func openDemoLaunchesTheAppOnTheDemosOwnSupportFolder() throws {
        let app = try FakeApp()
        let demoSupport = DemoPointer.supportFolder(forDemo: fixture, in: app.support)

        let result = table.run(["app", "open", "--demo", fixture.path], environment: app.environment)

        #expect(result.status == 0)
        #expect(app.launches.first?.environment == [
            "VIDEO_REVIEW_SUPPORT_DIR": demoSupport.path,
            "VIDEO_REVIEW_DEMO_DIR": fixture.path,
        ])
        #expect(DemoPointer.recorded(in: app.support) == DemoPointer(support: demoSupport, folder: fixture))
        // The demo folder itself is never written to.
        #expect(!demoSupport.path.hasPrefix(fixture.path))

        // Later commands reach the demo with nothing to repeat.
        _ = table.run(["app", "status"], environment: app.environment)
        #expect(app.messages.last?.socket == ControlSocket.url(in: demoSupport))
    }

    @Test func openDemoQuitsTheNormalAppFirst() throws {
        let app = try FakeApp()
        app.start(in: app.support)

        let result = table.run(["app", "open", "--demo", fixture.path], environment: app.environment)

        #expect(result.status == 0)
        #expect(!app.isRunning(in: app.support))
        #expect(app.isRunning(in: DemoPointer.supportFolder(forDemo: fixture, in: app.support)))
        #expect(app.requests.contains(.appQuit))
    }

    @Test func openDemoOfTheDemoThatAlreadyRunsAsksItAndLaunchesNothing() throws {
        let app = try FakeApp()
        _ = table.run(["app", "open", "--demo", fixture.path], environment: app.environment)

        let result = table.run(["app", "open", "--demo", fixture.path], environment: app.environment)

        #expect(result.status == 0)
        #expect(app.launches.count == 1)
        #expect(app.requests.last == .appOpen)
        #expect(!app.requests.contains(.appQuit))
    }

    @Test func plainOpenAfterADemoQuitsTheDemoAndBringsTheNormalAppBack() throws {
        let app = try FakeApp()
        _ = table.run(["app", "open", "--demo", fixture.path], environment: app.environment)
        let demoSupport = DemoPointer.supportFolder(forDemo: fixture, in: app.support)

        let result = table.run(["app", "open"], environment: app.environment)

        #expect(result.status == 0)
        #expect(!app.isRunning(in: demoSupport))
        #expect(app.isRunning(in: app.support))
        #expect(DemoPointer.recorded(in: app.support) == nil)
        #expect(app.launches.last?.environment == [:])
    }

    @Test func aLaunchThatFailsExitsOneAndLeavesNoPointer() throws {
        let app = try FakeApp()
        app.launchFailure = AppLaunchFailure("no app with the bundle id x is installed")

        let result = table.run(["app", "open", "--demo", fixture.path], environment: app.environment)

        #expect(result == CommandResult(error: "video-review app open: no app with the bundle id x is installed\n", status: 1))
        #expect(DemoPointer.recorded(in: app.support) == nil)
    }

    @Test func quitAsksTheAppAndWaitsUntilItIsGone() throws {
        let app = try FakeApp()
        app.start(in: app.support)
        app.answer = { _ in .done("video-review quit\n") }

        let result = table.run(["app", "quit"], environment: app.environment)

        #expect(result == CommandResult(output: "video-review quit\n"))
        #expect(!app.isRunning(in: app.support))
    }

    @Test(arguments: [
        (["open", "--demo"], "video-review app open: --demo needs a folder"),
        (["open", "--demo", "/nonexistent/folder"], "video-review app open: no folder at /nonexistent/folder"),
        (["open", "now"], "video-review app open: unexpected `now`"),
        (["quit", "now"], "video-review app quit: unexpected `now`"),
        (["restart"], "video-review app: unknown command `restart`"),
    ])
    func argumentsThatDoNotReadAreTheUsageAndExitTwo(arguments: [String], line: String) {
        guard case .failure(let result) = AppCommand.parse(arguments, workingDirectory: URL(fileURLWithPath: "/")) else {
            Issue.record("\(arguments) read")
            return
        }
        #expect(result.status == 2)
        #expect(result.error.hasPrefix(line + "\nusage: video-review app"))
    }

    @Test func theCommandLaunchesTheAppItShippedIn() {
        let helper = URL(fileURLWithPath: "/Applications/Video Review (proto-3).app/Contents/Helpers/video-review")
        #expect(WorkspaceLauncher.enclosingApp(of: helper)?.path == "/Applications/Video Review (proto-3).app")
        #expect(WorkspaceLauncher.enclosingApp(of: URL(fileURLWithPath: "/repo/.build/release/video-review")) == nil)
        #expect(WorkspaceLauncher.enclosingApp(of: nil) == nil)
    }
}
