import Foundation
import Testing
import VRWire

@Suite struct DemoPointerTests {
    /// A support folder of the test's own, removed when the test ends.
    final class Folder {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vr-wire-\(UUID().uuidString)", isDirectory: true)
        deinit { try? FileManager.default.removeItem(at: url) }
    }

    let folder = Folder()
    var support: URL { folder.url }
    let demo = URL(fileURLWithPath: "/Users/me/repo/.scratch/demo", isDirectory: true)

    @Test func thePointerNamesTheDemoFolderUntilItIsRemoved() throws {
        #expect(DemoPointer.recorded(in: support) == nil)
        try DemoPointer.record(demo, in: support)
        #expect(DemoPointer.recorded(in: support)?.path == demo.path)
        try DemoPointer.remove(in: support)
        #expect(DemoPointer.recorded(in: support) == nil)
        // Nothing to remove is no error.
        try DemoPointer.remove(in: support)
    }

    @Test(arguments: [
        "not json",
        #"{"support":"relative/demo","version":1}"#,
        #"{"support":"/abs/demo","version":2}"#,
    ])
    func aPointerThatDoesNotReadIsNoDemo(contents: String) throws {
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: DemoPointer.url(in: support))
        #expect(DemoPointer.recorded(in: support) == nil)
    }

    @Test func theCommandAsksTheDemosSocketOnlyWhileThePointerAndTheSocketAreThere() throws {
        let real = ControlSocket.real(in: support)
        let demoSocket = ControlSocket.demo(in: support)
        #expect(real.lastPathComponent == "control.sock")
        #expect(demoSocket.lastPathComponent == "demo.sock")

        #expect(ControlSocket.locate(support: support) == real)
        try DemoPointer.record(demo, in: support)
        // The demo isn't running (or quit): the person's app is still found.
        #expect(ControlSocket.locate(support: support) == real)
        try Data().write(to: demoSocket)
        #expect(ControlSocket.locate(support: support) == demoSocket)
        try DemoPointer.remove(in: support)
        #expect(ControlSocket.locate(support: support) == real)
    }

    @Test func aDemoRunKeepsItsDataInTheFolderItIsGiven() {
        #expect(SupportFolder.current(environment: [SupportFolder.overrideVariable: "/abs/demo"]).path == "/abs/demo")
        #expect(SupportFolder.current(environment: [SupportFolder.overrideVariable: "relative"]) == SupportFolder.real())
        #expect(SupportFolder.current(environment: [:]) == SupportFolder.real())
        #expect(SupportFolder.real().lastPathComponent == Identity.supportFolderName)
    }

    @Test func theBuildsNamesFollowItsVariant() {
        #expect(Identity.appName == (Identity.variant.isEmpty ? "Video Review" : "Video Review (\(Identity.variant))"))
        #expect(Identity.bundleID.hasPrefix("com.yahyabedirhan.video-review"))
        #expect(Identity.variant.isEmpty || Identity.bundleID.hasSuffix(".\(Identity.variant)"))
    }
}
