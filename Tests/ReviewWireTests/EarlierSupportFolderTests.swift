import Foundation
import ReviewWire
import Testing

/// Every test works in a temporary Application Support folder: none of
/// them reads or writes the person's own.
@Suite("Moving the data of the app's earlier name")
struct EarlierSupportFolderTests {
    private let files = FileManager.default

    /// A new temporary Application Support folder, removed when the test ends.
    private func withApplicationSupport(_ body: (URL) throws -> Void) throws {
        let folder = files.temporaryDirectory.appendingPathComponent("havooch-tests-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: folder) }
        try body(folder)
    }

    /// The earlier folder in `applicationSupport` with the files a person
    /// who used the earlier app has, and its stale socket and demo pointer.
    private func earlierData(in applicationSupport: URL) throws -> URL {
        let earlier = applicationSupport.appendingPathComponent("Video Review", isDirectory: true)
        let review = earlier.appendingPathComponent("videos/abc123", isDirectory: true)
        try files.createDirectory(at: review, withIntermediateDirectories: true)
        try files.createDirectory(at: earlier.appendingPathComponent("Themes", isDirectory: true), withIntermediateDirectories: true)
        try Data(#"{"threads":[]}"#.utf8).write(to: review.appendingPathComponent("review.json"))
        try Data(#"{"name":"Mine"}"#.utf8).write(to: earlier.appendingPathComponent("Themes/Mine.json"))
        try Data(#"{"theme":"Dracula"}"#.utf8).write(to: earlier.appendingPathComponent("settings.json"))
        try Data("[]".utf8).write(to: earlier.appendingPathComponent("outbox.json"))
        try Data("{}".utf8).write(to: earlier.appendingPathComponent("recent.json"))
        try Data().write(to: earlier.appendingPathComponent("control.sock"))
        try Data(#"{"support":"/tmp/old-demo","version":1}"#.utf8).write(to: earlier.appendingPathComponent("demo.json"))
        return earlier
    }

    private func text(_ url: URL) throws -> String {
        String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    @Test("a first launch moves every review, theme and setting, and removes the earlier folder")
    func movesEverything() throws {
        try withApplicationSupport { applicationSupport in
            let earlier = try earlierData(in: applicationSupport)
            let outcome = EarlierSupportFolder.move(environment: [:], applicationSupport: applicationSupport, earlierAppRuns: false)
            #expect(outcome == .moved(moved: ["Themes", "outbox.json", "recent.json", "settings.json", "videos"], kept: []))
            let support = applicationSupport.appendingPathComponent("Havooch", isDirectory: true)
            #expect(try text(support.appendingPathComponent("videos/abc123/review.json")) == #"{"threads":[]}"#)
            #expect(try text(support.appendingPathComponent("Themes/Mine.json")) == #"{"name":"Mine"}"#)
            #expect(try text(support.appendingPathComponent("settings.json")) == #"{"theme":"Dracula"}"#)
            #expect(!files.fileExists(atPath: support.appendingPathComponent("control.sock").path))
            #expect(!files.fileExists(atPath: support.appendingPathComponent("demo.json").path))
            #expect(!files.fileExists(atPath: earlier.path))
        }
    }

    @Test("the next launch finds nothing to do")
    func once() throws {
        try withApplicationSupport { applicationSupport in
            _ = try earlierData(in: applicationSupport)
            _ = EarlierSupportFolder.move(environment: [:], applicationSupport: applicationSupport, earlierAppRuns: false)
            #expect(EarlierSupportFolder.move(environment: [:], applicationSupport: applicationSupport, earlierAppRuns: false) == .nothingToDo)
        }
    }

    @Test("a demo run or a moved support folder never touches the earlier folder", arguments: [
        ["HAVOOCH_SUPPORT_DIR": "/tmp/havooch-demo"], ["VIDEO_REVIEW_SUPPORT_DIR": "/tmp/havooch-demo"],
    ])
    func overridden(environment: [String: String]) throws {
        try withApplicationSupport { applicationSupport in
            let earlier = try earlierData(in: applicationSupport)
            let before = try files.contentsOfDirectory(atPath: earlier.path).sorted()
            #expect(EarlierSupportFolder.move(environment: environment, applicationSupport: applicationSupport, earlierAppRuns: false) == .nothingToDo)
            #expect(try files.contentsOfDirectory(atPath: earlier.path).sorted() == before)
            #expect(!files.fileExists(atPath: applicationSupport.appendingPathComponent("Havooch").path))
        }
    }

    @Test("while the earlier app runs, nothing moves")
    func earlierAppRuns() throws {
        try withApplicationSupport { applicationSupport in
            let earlier = try earlierData(in: applicationSupport)
            let before = try files.contentsOfDirectory(atPath: earlier.path).sorted()
            #expect(EarlierSupportFolder.move(environment: [:], applicationSupport: applicationSupport, earlierAppRuns: true) == .earlierAppRuns)
            #expect(try files.contentsOfDirectory(atPath: earlier.path).sorted() == before)
            #expect(!files.fileExists(atPath: applicationSupport.appendingPathComponent("Havooch").path))
        }
    }

    @Test("with no earlier folder there's nothing to do, and no support folder is made")
    func noEarlierFolder() throws {
        try withApplicationSupport { applicationSupport in
            #expect(EarlierSupportFolder.move(environment: [:], applicationSupport: applicationSupport, earlierAppRuns: false) == .nothingToDo)
            let made = try files.contentsOfDirectory(atPath: applicationSupport.path)
            #expect(made.isEmpty)
        }
    }

    @Test("what the support folder already has is never overwritten, and the earlier folder keeps it")
    func neverOverwrites() throws {
        try withApplicationSupport { applicationSupport in
            let earlier = try earlierData(in: applicationSupport)
            let support = applicationSupport.appendingPathComponent("Havooch", isDirectory: true)
            try files.createDirectory(at: support, withIntermediateDirectories: true)
            try Data(#"{"theme":"Tokyo Night"}"#.utf8).write(to: support.appendingPathComponent("settings.json"))
            // `havooch app open --demo` before the first launch leaves only its pointer.
            try Data(#"{"support":"/tmp/new-demo","version":1}"#.utf8).write(to: support.appendingPathComponent("demo.json"))
            let outcome = EarlierSupportFolder.move(environment: [:], applicationSupport: applicationSupport, earlierAppRuns: false)
            #expect(outcome == .moved(moved: ["Themes", "outbox.json", "recent.json", "videos"], kept: ["settings.json"]))
            #expect(try text(support.appendingPathComponent("settings.json")) == #"{"theme":"Tokyo Night"}"#)
            #expect(try text(earlier.appendingPathComponent("settings.json")) == #"{"theme":"Dracula"}"#)
            #expect(try text(support.appendingPathComponent("demo.json")) == #"{"support":"/tmp/new-demo","version":1}"#)
            #expect(files.fileExists(atPath: support.appendingPathComponent("videos/abc123/review.json").path))
        }
    }
}
