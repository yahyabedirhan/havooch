import Foundation
@testable import ReviewApp
import ReviewStore
import ReviewWire
import Testing

/// The player's window: the app keeps its model while the window is
/// closed, and opening a video shows it. No window and no socket; the
/// launch is in `PersistenceTests`.
@Suite("The player's window", .serialized)
struct WindowTests {
    let support = FileManager.default.temporaryDirectory
        .appendingPathComponent("havooch-tests-\(UUID().uuidString)", isDirectory: true)

    private var environment: [String: String] { [SupportFolder.overrideVariable: support.path] }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: support)
    }

    private func eventually(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("closing the window pauses the video and keeps it open at its playhead")
    func closePauses() async throws {
        defer { cleanUp() }
        let model = AppModel(environment: environment)
        try await model.open(MessageTests.fixture)
        try await model.seek(to: 2)
        try model.play()
        await eventually { model.engine.isPlaying }
        #expect(model.engine.isPlaying)

        model.windowClosed()
        await eventually { !model.engine.isPlaying }
        #expect(!model.engine.isPlaying)
        // The model stays as it was, for the Dock icon to show again.
        #expect(model.video?.url == MessageTests.fixture.standardizedFileURL)
        #expect(model.engine.time >= 2)
    }

    @Test("closing the window with no video open does nothing")
    func closeWithNoVideo() {
        defer { cleanUp() }
        let model = AppModel(environment: environment)
        model.windowClosed()
        #expect(model.video == nil)
        #expect(model.problem == nil)
    }

    @Test("opening a video shows the window, so a control command's open is seen; a refused open doesn't")
    func openShowsWindow() async throws {
        defer { cleanUp() }
        let model = AppModel(environment: environment)
        var shown = 0
        model.showWindow = { shown += 1 }
        await #expect(throws: AppRefusal.self) { try await model.open(URL(fileURLWithPath: "/nowhere/missing.mp4")) }
        #expect(shown == 0)
        try await model.open(MessageTests.fixture)
        #expect(shown == 1)
    }
}
