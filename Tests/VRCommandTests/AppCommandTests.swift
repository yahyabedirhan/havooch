import Foundation
import Testing
import VRCommand
import VRLease
import VRWire

@Suite struct AppCommandTests {
    static let status = "Video Review 0.1.0 is running\n"
    let demo = URL(fileURLWithPath: "/work/.scratch/demo", isDirectory: true)

    /// An app that answers at the sockets named, and stops answering at a
    /// socket once it was asked to quit there. With `afterLaunch`, it
    /// answers there only once `launcher` has launched.
    private func app(
        at sockets: Set<String>, afterLaunch: String? = nil, launcher: RecordingLauncher, lease: ControlLease.Term? = nil
    ) -> FakeTransport {
        let listening = Locked(sockets)
        return FakeTransport { message, socket in
            if socket == afterLaunch, !launcher.launches.current.isEmpty { listening.withValue { _ = $0.insert(socket) } }
            guard listening.current.contains(socket) else { return .failure(.notRunning) }
            switch message.request {
            case .appQuit:
                listening.withValue { _ = $0.remove(socket) }
                return .success(ControlReply(ok: true, output: "quit\n", lease: lease))
            default:
                return .success(.done(Self.status))
            }
        }
    }

    // MARK: - status

    @Test func statusOfAnAppThatIsNotRunningSaysSoAndExitsZero() {
        let harness = CommandHarness()
        #expect(harness.run("app", "status", transport: .nothingListens) == CommandResult(output: "not running\n"))
        #expect(harness.run("app", "status", "--json", transport: .nothingListens) == CommandResult(output: "{\"running\":false}\n"))
    }

    @Test func statusOfARunningAppIsWhatTheAppSays() {
        let harness = CommandHarness()
        let transport = app(at: ["control.sock"], launcher: harness.launcher)
        #expect(harness.run("app", "status", transport: transport) == CommandResult(output: Self.status))
        #expect(transport.sent == ["app.status @ control.sock"])
    }

    // MARK: - open

    @Test func openStartsTheAppOnThePersonsDataAndWaitsUntilItAnswers() {
        let harness = CommandHarness()
        let transport = app(at: [], afterLaunch: "control.sock", launcher: harness.launcher)
        let result = harness.run("app", "open", transport: transport)
        #expect(result == CommandResult(output: Self.status))
        #expect(harness.launcher.launches.current == [.init(bundle: harness.bundle, environment: [:])])
        #expect(transport.sent == ["app.status @ demo.sock", "app.status @ control.sock", "app.open @ control.sock"])
        #expect(DemoPointer.recorded(in: harness.support) == nil)
    }

    @Test func openDemoStartsTheAppOnTheFolderAndPointsLaterCommandsAtIt() throws {
        let harness = CommandHarness()
        let folder = harness.support.appendingPathComponent("demo-data", isDirectory: true)
        let transport = app(at: [], afterLaunch: "demo.sock", launcher: harness.launcher)
        let result = harness.run("app", "open", "--demo", folder.path, transport: transport)
        #expect(result == CommandResult(output: Self.status))
        #expect(harness.launcher.launches.current == [
            .init(bundle: harness.bundle, environment: ["VIDEO_REVIEW_SUPPORT_DIR": folder.path]),
        ])
        #expect(transport.sent.last == "app.open @ demo.sock")
        #expect(DemoPointer.recorded(in: harness.support)?.path == folder.path)
        // The demo folder is made when it's missing.
        var isFolder: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: folder.path, isDirectory: &isFolder) && isFolder.boolValue)
    }

    @Test func aRelativeDemoFolderIsTakenAgainstTheWorkingFolder() throws {
        let harness = CommandHarness()
        try DemoPointer.record(demo, in: harness.support)
        let transport = app(at: ["demo.sock"], launcher: harness.launcher)
        // The demo on /work/.scratch/demo runs: `.scratch/demo` from /work is the same data.
        #expect(harness.run("app", "open", "--demo", ".scratch/demo", transport: transport) == CommandResult(output: Self.status))
        #expect(transport.sent == ["app.status @ demo.sock", "app.open @ demo.sock"])
        #expect(harness.launcher.launches.current.isEmpty)
    }

    @Test func openOfAnAppAlreadyOnThatDataOnlyAsksIt() {
        let harness = CommandHarness()
        let transport = app(at: ["control.sock"], launcher: harness.launcher)
        #expect(harness.run("app", "open", "--json", transport: transport) == CommandResult(output: Self.status))
        #expect(transport.sent == ["app.status @ demo.sock", "app.status @ control.sock", "app.open @ control.sock"])
        #expect(transport.exchanges.current.last?.message.json == true)
        #expect(harness.launcher.launches.current.isEmpty)
    }

    @Test func openOnOtherDataQuitsTheRunningAppFirstAndHandsItsLeaseOver() throws {
        let harness = CommandHarness()
        try DemoPointer.record(demo, in: harness.support)
        let term = ControlLease.Term(
            holder: Holder(key: "process:300@800250000", name: "claude", place: "/work"),
            taken: Date(timeIntervalSince1970: 1_000), ends: Date(timeIntervalSince1970: 1_060)
        )
        let transport = app(at: ["demo.sock"], afterLaunch: "control.sock", launcher: harness.launcher, lease: term)
        let result = harness.run("app", "open", transport: transport)
        #expect(result == CommandResult(output: Self.status))
        #expect(transport.sent == [
            "app.status @ demo.sock", "app.quit @ demo.sock", "app.status @ demo.sock", "app.open @ control.sock",
        ])
        #expect(harness.launcher.launches.current == [.init(bundle: harness.bundle, environment: ControlLease.handover(term))])
        #expect(DemoPointer.recorded(in: harness.support) == nil)
    }

    @Test func openDemoWhileThePersonsAppRunsQuitsItFirst() throws {
        let harness = CommandHarness()
        let folder = harness.support.appendingPathComponent("demo-data", isDirectory: true)
        let transport = app(at: ["control.sock"], afterLaunch: "demo.sock", launcher: harness.launcher)
        let result = harness.run("app", "open", "--demo", folder.path, transport: transport)
        #expect(result == CommandResult(output: Self.status))
        #expect(transport.sent == [
            "app.status @ demo.sock", "app.status @ control.sock", "app.quit @ control.sock", "app.status @ control.sock",
            "app.open @ demo.sock",
        ])
        #expect(harness.launcher.launches.current == [
            .init(bundle: harness.bundle, environment: ["VIDEO_REVIEW_SUPPORT_DIR": folder.path]),
        ])
    }

    @Test func aRefusedQuitLeavesEverythingAsItWas() throws {
        let harness = CommandHarness()
        try DemoPointer.record(demo, in: harness.support)
        let transport = FakeTransport { message, socket in
            guard socket == "demo.sock" else { return .failure(.notRunning) }
            if case .appQuit = message.request { return .success(.refused("video-review is in use by codex")) }
            return .success(.done(Self.status))
        }
        let result = harness.run("app", "open", transport: transport)
        #expect(result == CommandResult(error: "video-review is in use by codex\n", exitCode: 1))
        #expect(harness.launcher.launches.current.isEmpty)
        #expect(DemoPointer.recorded(in: harness.support)?.path == demo.path)
    }

    @Test func aDemoThatDoesNotStartLeavesNoPointerBehind() {
        let harness = CommandHarness(launcher: RecordingLauncher(failure: AppLaunchFailure("no app with the bundle id x is installed")))
        let folder = harness.support.appendingPathComponent("demo-data", isDirectory: true)
        let result = harness.run("app", "open", "--demo", folder.path, transport: .nothingListens)
        #expect(result == CommandResult(error: "video-review app open: no app with the bundle id x is installed\n", exitCode: 1))
        #expect(DemoPointer.recorded(in: harness.support) == nil)
    }

    @Test func anAppThatNeverAnswersAfterItsLaunchIsGivenUpOn() {
        let harness = CommandHarness()
        let result = harness.run("app", "open", transport: .nothingListens)
        #expect(result == CommandResult(error: "video-review didn't answer within 10 seconds of launching\n", exitCode: 1))
        #expect(harness.launcher.launches.current.count == 1)
        #expect(harness.pauses.current == 40)
    }

    // MARK: - quit

    @Test func quitWaitsUntilNothingAnswers() {
        let harness = CommandHarness()
        let transport = app(at: ["control.sock"], launcher: harness.launcher)
        #expect(harness.run("app", "quit", transport: transport) == CommandResult(output: "quit\n"))
        #expect(transport.sent == ["app.quit @ control.sock", "app.status @ control.sock"])
    }

    @Test func quitOfAnAppThatIsNotRunningExitsOne() {
        let harness = CommandHarness()
        let result = harness.run("app", "quit", transport: .nothingListens)
        #expect(result == CommandResult(error: "video-review isn't running; `video-review app open`\n", exitCode: 1))
    }

    @Test func anAppThatSaysItQuitsButStaysIsReported() {
        let harness = CommandHarness()
        let result = harness.run("app", "quit", transport: FakeTransport(reply: .done("quit\n")))
        #expect(result == CommandResult(error: "video-review said it would quit, but it still answers after 10 seconds\n", exitCode: 1))
    }
}
