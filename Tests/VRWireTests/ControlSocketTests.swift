import Foundation
import Testing
@testable import VRWire

/// A folder of this test's own, removed when the test ends.
private final class Scratch {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("vr-wire-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }
}

@Suite struct AppIdentityTests {
    @Test func aVariantSuffixesTheNameAndTheBundleID() {
        #expect(AppIdentity.name(variant: "proto-3") == "Video Review (proto-3)")
        #expect(AppIdentity.bundleID(variant: "proto-3") == "com.yahyabedirhan.video-review.proto-3")
    }

    @Test func theRealProductHasNoSuffix() {
        #expect(AppIdentity.name(variant: "") == "Video Review")
        #expect(AppIdentity.bundleID(variant: "") == "com.yahyabedirhan.video-review")
    }

    @Test func theSupportFolderIsNamedAfterTheApp() {
        let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
        #expect(AppIdentity.supportFolder(home: home).path == "/Users/me/Library/Application Support/\(AppIdentity.name)")
    }

    @Test func theSupportVariableMovesTheSupportFolder() {
        let moved = AppIdentity.supportFolder(variables: ["VIDEO_REVIEW_SUPPORT_DIR": "/tmp/demo"])
        #expect(moved.path == "/tmp/demo")
    }

    @Test func aRelativeSupportVariableIsIgnored() {
        let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
        let folder = AppIdentity.supportFolder(variables: ["VIDEO_REVIEW_SUPPORT_DIR": "demo"], home: home)
        #expect(folder.path.hasPrefix("/Users/me/Library/Application Support/"))
    }
}

@Suite struct ControlSocketTests {
    @Test func withoutAPointerTheSocketIsTheSupportFoldersOwn() throws {
        let scratch = try Scratch()
        #expect(ControlSocket.locate(support: scratch.folder) == scratch.folder.appendingPathComponent("control.sock"))
    }

    @Test func aPointerToARunningDemoLeadsToTheDemosSocket() throws {
        let scratch = try Scratch()
        let demo = DemoPointer.supportFolder(forDemo: URL(fileURLWithPath: "/repo/fixtures/sample"), in: scratch.folder)
        try FileManager.default.createDirectory(at: demo, withIntermediateDirectories: true)
        try Data().write(to: ControlSocket.url(in: demo))
        try DemoPointer(support: demo, folder: URL(fileURLWithPath: "/repo/fixtures/sample")).record(in: scratch.folder)

        #expect(ControlSocket.locate(support: scratch.folder) == ControlSocket.url(in: demo))
    }

    @Test func aPointerToADemoThatQuitFallsBackToTheNormalSocket() throws {
        let scratch = try Scratch()
        let demo = scratch.folder.appendingPathComponent("d-00000000", isDirectory: true)
        try DemoPointer(support: demo, folder: URL(fileURLWithPath: "/repo/fixtures/sample")).record(in: scratch.folder)

        #expect(ControlSocket.locate(support: scratch.folder) == ControlSocket.url(in: scratch.folder))
    }
}

@Suite struct DemoPointerTests {
    @Test func aPointerReadsBackAsItWasRecorded() throws {
        let scratch = try Scratch()
        let pointer = DemoPointer(
            support: URL(fileURLWithPath: "/support/d-1"), folder: URL(fileURLWithPath: "/repo/fixtures/sample")
        )
        try pointer.record(in: scratch.folder)
        #expect(DemoPointer.recorded(in: scratch.folder) == pointer)

        try DemoPointer.remove(in: scratch.folder)
        #expect(DemoPointer.recorded(in: scratch.folder) == nil)
    }

    @Test func removingWhenThereIsNoPointerDoesNothing() throws {
        let scratch = try Scratch()
        try DemoPointer.remove(in: scratch.folder)
    }

    @Test(arguments: [
        "not json",
        #"{"version":2,"support":"/support/d-1","folder":"/demo"}"#,
        #"{"version":1,"support":"relative","folder":"/demo"}"#,
        #"{"version":1,"support":"/support/d-1"}"#,
    ])
    func aPointerThatDoesNotReadIsNoDemo(contents: String) throws {
        let scratch = try Scratch()
        try Data(contents.utf8).write(to: DemoPointer.url(in: scratch.folder))
        #expect(DemoPointer.recorded(in: scratch.folder) == nil)
    }

    @Test func aDemosSupportFolderIsInsideTheNormalOneNamedByTheDemoFoldersPath() {
        let support = URL(fileURLWithPath: "/Users/me/Library/Application Support/Video Review", isDirectory: true)
        let one = DemoPointer.supportFolder(forDemo: URL(fileURLWithPath: "/repo/fixtures/sample"), in: support)
        let same = DemoPointer.supportFolder(forDemo: URL(fileURLWithPath: "/repo/fixtures/./sample/"), in: support)
        let other = DemoPointer.supportFolder(forDemo: URL(fileURLWithPath: "/repo/fixtures/other"), in: support)

        #expect(one.deletingLastPathComponent().path == support.path)
        #expect(one.lastPathComponent.wholeMatch(of: /d-[0-9a-f]{8}/) != nil)
        #expect(one == same)
        #expect(one != other)
    }
}
