import Foundation
import ReviewWire
import Testing

@Suite("Where the app and its socket are")
struct LocationTests {
    /// A new empty folder, removed when the test ends.
    private func withFolder(_ body: (URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("havooch-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try body(folder)
    }

    @Test("the app is Havooch 0.5.1, with no prototype suffix in its name, bundle id or support folder")
    func identity() {
        #expect(AppIdentity.appName == "Havooch")
        #expect(AppIdentity.bundleID == "com.yahyabedirhan.havooch")
        #expect(SupportFolder.app(environment: [:]).lastPathComponent == "Havooch")
        #expect(Version.app == "0.5.1")
    }

    /// Whether the tests run on the Mac, where the support folder is
    /// Application Support's.
    static var onMac: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    @Test("the support folder is in Application Support", .enabled(if: onMac, "Application Support is a macOS folder"))
    func applicationSupport() {
        #expect(SupportFolder.app(environment: [:]).path.hasSuffix("/Library/Application Support/Havooch"))
    }

    @Test("HAVOOCH_SUPPORT_DIR moves the support folder when it's absolute")
    func override() {
        #expect(SupportFolder.app(environment: ["HAVOOCH_SUPPORT_DIR": "/tmp/demo"]).path == "/tmp/demo")
        #expect(SupportFolder.moved(environment: ["HAVOOCH_SUPPORT_DIR": "demo"]) == nil)
        #expect(SupportFolder.moved(environment: [:]) == nil)
    }

    @Test("a run is the demo only when app open --demo marked its launch beside the moved folder")
    func demoRun() {
        let moved = ["HAVOOCH_SUPPORT_DIR": "/tmp/demo"]
        #expect(SupportFolder.isDemoRun(environment: moved.merging(["HAVOOCH_DEMO_RUN": "1"]) { _, new in new }))
        #expect(!SupportFolder.isDemoRun(environment: moved))
        #expect(!SupportFolder.isDemoRun(environment: ["HAVOOCH_DEMO_RUN": "1"]))
        #expect(!SupportFolder.isDemoRun(environment: [:]))
    }

    @Test("the demo pointer is recorded, read and removed")
    func pointer() throws {
        try withFolder { support in
            #expect(DemoPointer.recorded(in: support) == nil)
            try DemoPointer.record(URL(fileURLWithPath: "/tmp/demo", isDirectory: true), in: support)
            #expect(DemoPointer.recorded(in: support)?.path == "/tmp/demo")
            try DemoPointer.remove(in: support)
            #expect(DemoPointer.recorded(in: support) == nil)
            try DemoPointer.remove(in: support)
        }
    }

    @Test("a pointer that doesn't read, is newer or is relative reads as no demo", arguments: [
        "not json", #"{"support":"/tmp/demo","version":2}"#, #"{"support":"demo","version":1}"#,
    ])
    func unsafePointer(contents: String) throws {
        try withFolder { support in
            try Data(contents.utf8).write(to: DemoPointer.url(in: support))
            #expect(DemoPointer.recorded(in: support) == nil)
        }
    }

    @Test("commands reach the demo's socket only while it's there")
    func locate() throws {
        try withFolder { folder in
            let support = folder.appendingPathComponent("normal", isDirectory: true)
            let demo = folder.appendingPathComponent("demo", isDirectory: true)
            try FileManager.default.createDirectory(at: demo, withIntermediateDirectories: true)
            #expect(ControlSocket.locate(support: support) == ControlSocket.url(in: support))

            // A demo that quit: its pointer is there, its socket isn't.
            try DemoPointer.record(demo, in: support)
            #expect(ControlSocket.locate(support: support) == ControlSocket.url(in: support))

            try Data().write(to: ControlSocket.url(in: demo))
            #expect(ControlSocket.locate(support: support) == ControlSocket.url(in: demo))
        }
    }
}
