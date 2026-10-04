import Foundation
import Testing
@testable import VRApp
import VRLease
import VRReview
import VRWire

private let listener = Holder(key: "listener-1", name: "Claude Code", place: "/Users/me/shop")
private let restarted = Holder(key: "listener-2", name: "Claude Code", place: "/Users/me/shop")
private let stranger = Holder(key: "other", name: "codex", place: "/Users/me/blog")

/// A folder of its own with a copy of the fixture video as `talk.mp4`, for
/// the context files a test writes beside it.
private final class Folder {
    let url = URL(fileURLWithPath: "/tmp", isDirectory: true)
        .appendingPathComponent("vr-\(UUID().uuidString.prefix(8))", isDirectory: true)
    var video: URL { url.appendingPathComponent("talk.mp4") }

    init() throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixtureVideo, to: video)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func write(_ text: String, to name: String) throws {
        try Data(text.utf8).write(to: url.appendingPathComponent(name))
    }

    func remove(_ name: String) throws {
        try FileManager.default.removeItem(at: url.appendingPathComponent(name))
    }
}

/// A rig with the folder's video open.
@MainActor
private func opened(_ folder: Folder) async -> BatchRig {
    let rig = BatchRig()
    #expect(await rig.send(.playerOpen(path: folder.video.path)).ok)
    return rig
}

/// The `context` of the next batch: one more comment queued and sent, and
/// the payload a `wait` of `holder` gets for it.
@MainActor
private func nextContext(_ rig: BatchRig, by holder: Holder = listener) async throws -> String? {
    #expect(await rig.send(.commentAdd(text: "look here", at: 1, region: nil)).ok)
    #expect(await rig.send(.batchSend).ok)
    let answer = await rig.wait(by: holder)
    #expect(answer.reply.ok, "\(answer.reply.error)")
    return try JSONDecoder().decode(BatchPayload.self, from: Data(answer.reply.output.utf8)).context
}

@Suite struct ContextSidecarTests {
    @Test func theFileNamedAfterTheVideoWinsOverTheFoldersContextFile() throws {
        let folder = try Folder()
        #expect(ContextSidecar.find(beside: folder.video) == nil)

        try folder.write("about the folder\n", to: "context.md")
        #expect(ContextSidecar.find(beside: folder.video)
            == ContextSidecar(url: folder.url.appendingPathComponent("context.md"), text: "about the folder\n"))

        try folder.write("about the talk\n", to: "talk.context.md")
        #expect(ContextSidecar.find(beside: folder.video)
            == ContextSidecar(url: folder.url.appendingPathComponent("talk.context.md"), text: "about the talk\n"))

        // Another video's file isn't this one's.
        try folder.remove("talk.context.md")
        try folder.write("about the demo\n", to: "demo.context.md")
        #expect(ContextSidecar.find(beside: folder.video)?.url.lastPathComponent == "context.md")
    }

    @Test func anEmptyFileNamedAfterTheVideoStillWins() throws {
        let folder = try Folder()
        try folder.write("about the folder\n", to: "context.md")
        try folder.write("", to: "talk.context.md")

        #expect(ContextSidecar.find(beside: folder.video)?.url.lastPathComponent == "talk.context.md")
    }

    @Test func aFolderNamedLikeAContextFileIsNotOne() throws {
        let folder = try Folder()
        try FileManager.default.createDirectory(at: folder.url.appendingPathComponent("talk.context.md"), withIntermediateDirectories: true)
        try folder.write("about the folder\n", to: "context.md")

        #expect(ContextSidecar.find(beside: folder.video)?.url.lastPathComponent == "context.md")
    }

    @Test func theTextIsTheSidecarThenTheNoteUnderItsHeading() {
        #expect(ContextSidecar.text(sidecar: "# Talk\n\nAbout the shop.\n\n", note: "") == "# Talk\n\nAbout the shop.\n")
        #expect(ContextSidecar.text(sidecar: "# Talk\n", note: "Mind the pacing.")
            == "# Talk\n\n## Reviewer's note\n\nMind the pacing.\n")
        #expect(ContextSidecar.text(sidecar: nil, note: "Mind the pacing.\n") == "## Reviewer's note\n\nMind the pacing.\n")
        #expect(ContextSidecar.text(sidecar: nil, note: "") == nil)
        #expect(ContextSidecar.text(sidecar: " \n", note: " ") == nil)
    }
}

@MainActor
@Suite struct ContextTests {
    @Test func theFirstBatchOfAListenerSessionHasTheContextAndTheNextHasNone() async throws {
        let folder = try Folder()
        try folder.write("# Talk\n\nAbout the shop.\n", to: "talk.context.md")
        let rig = await opened(folder)

        #expect(try await nextContext(rig) == "# Talk\n\nAbout the shop.\n")
        #expect(try await nextContext(rig) == nil)
        #expect(try await nextContext(rig) == nil)
    }

    @Test func theSecondPayloadSaysNullForTheContext() async throws {
        let folder = try Folder()
        try folder.write("about the talk\n", to: "context.md")
        let rig = await opened(folder)
        _ = try await nextContext(rig)

        _ = await rig.send(.commentAdd(text: "and here", at: 2, region: nil))
        _ = await rig.send(.batchSend)
        let output = await rig.wait().reply.output

        let object = try #require(try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        #expect(object["context"] is NSNull)
    }

    @Test func aChangeToTheFileOnDiskSendsTheContextAgain() async throws {
        let folder = try Folder()
        try folder.write("about the talk\n", to: "context.md")
        let rig = await opened(folder)
        #expect(try await nextContext(rig) == "about the talk\n")
        #expect(try await nextContext(rig) == nil)

        try folder.write("about the new talk\n", to: "context.md")
        #expect(try await nextContext(rig) == "about the new talk\n")
        #expect(try await nextContext(rig) == nil)

        // A file named after the video takes over from the folder's.
        try folder.write("only this talk\n", to: "talk.context.md")
        #expect(try await nextContext(rig) == "only this talk\n")
        #expect(try await nextContext(rig) == nil)
    }

    @Test func aChangeToTheNoteSendsTheContextAgain() async throws {
        let folder = try Folder()
        try folder.write("about the talk\n", to: "context.md")
        let rig = await opened(folder)
        #expect(try await nextContext(rig) == "about the talk\n")

        #expect(await rig.send(.contextSet(text: "  Mind the pacing.\n")) == .done("context note set\n"))
        #expect(try await nextContext(rig) == "about the talk\n\n## Reviewer's note\n\nMind the pacing.\n")
        #expect(try await nextContext(rig) == nil)

        // The same note again changes nothing.
        _ = await rig.send(.contextSet(text: "Mind the pacing."))
        #expect(try await nextContext(rig) == nil)

        #expect(await rig.send(.contextSet(text: "")) == .done("context note cleared\n"))
        #expect(try await nextContext(rig) == "about the talk\n")
    }

    @Test func aNewListenerSessionGetsTheContextAgain() async throws {
        let folder = try Folder()
        try folder.write("about the talk\n", to: "context.md")
        let rig = await opened(folder)
        #expect(try await nextContext(rig) == "about the talk\n")
        #expect(try await nextContext(rig) == nil)

        #expect(try await nextContext(rig, by: restarted) == "about the talk\n")
        #expect(try await nextContext(rig, by: restarted) == nil)
    }

    @Test func theNoteAloneIsAContextAndAVideoWithNeitherHasNone() async throws {
        let rig = await opened(try Folder())
        #expect(try await nextContext(rig) == nil)

        _ = await rig.send(.contextSet(text: "Mind the pacing."))
        #expect(try await nextContext(rig) == "## Reviewer's note\n\nMind the pacing.\n")
    }

    @Test func aNoteWrittenInTheWindowReachesTheNextBatch() async throws {
        let rig = await opened(try Folder())

        rig.model.noteByPerson("Mind the pacing.")

        #expect(rig.model.note == "Mind the pacing.")
        #expect(try await nextContext(rig) == "## Reviewer's note\n\nMind the pacing.\n")
    }

    @Test func theFixtureVideosContextGoesWithItsFirstBatch() async throws {
        let rig = await BatchRig().opened()
        let sidecar = fixtureVideo.deletingLastPathComponent().appendingPathComponent("sample.context.md")

        let context = try #require(try await nextContext(rig))

        #expect(context == (try String(contentsOf: sidecar, encoding: .utf8)))
        #expect(context.hasPrefix("# Context: sample\n"))
    }

    @Test func aVideosNoteIsItsOwnAndIsThereWhenTheVideoIsOpenedAgain() async throws {
        let folder = try Folder()
        let rig = await opened(folder)
        _ = await rig.send(.contextSet(text: "Mind the pacing."))

        // A video is its bytes: another one is the same film with an empty
        // box at its end.
        let other = try Folder()
        try FileManager.default.removeItem(at: other.video)
        var bytes = try Data(contentsOf: fixtureVideo)
        bytes.append(contentsOf: [0, 0, 0, 8, 0x66, 0x72, 0x65, 0x65])
        try bytes.write(to: other.video)
        #expect(await rig.send(.playerOpen(path: other.video.path)).ok)
        #expect(rig.model.note == "")

        #expect(await rig.send(.playerOpen(path: folder.video.path)).ok)
        #expect(rig.model.note == "Mind the pacing.")
    }

    @Test func contextSetAsJSONIsTheNoteAsItWasKept() async throws {
        let rig = await opened(try Folder())

        let reply = await rig.send(.contextSet(text: " two\nlines \n"), json: true)

        #expect(reply == .done(#"{"note":"two\nlines"}"# + "\n"))
    }

    @Test func contextSetWithNoVideoOpenIsRefused() async {
        let rig = BatchRig()

        #expect(await rig.send(.contextSet(text: "Mind the pacing."))
            == .refused("no video is open; `video-review player open <path>`"))
    }

    @Test func contextSetFromAnotherAgentThanTheLeasesHolderIsRefused() async throws {
        let rig = await opened(try Folder())

        let reply = await rig.send(.contextSet(text: "Mind the pacing."), by: stranger)

        #expect(!reply.ok)
        #expect(reply.error.hasPrefix("video-review is in use by Claude Code"))
        #expect(rig.model.note == "")
    }

    @Test func stateNamesTheSidecarAndTheNote() async throws {
        let folder = try Folder()
        let rig = await opened(folder)
        var context = try #require(try await rig.state()["context"] as? [String: Any])
        #expect(Set(context.keys) == ["sidecarPath", "note"])
        #expect(context["sidecarPath"] is NSNull)
        #expect(context["note"] as? String == "")

        try folder.write("about the talk\n", to: "context.md")
        _ = await rig.send(.contextSet(text: "Mind the pacing."))
        context = try #require(try await rig.state()["context"] as? [String: Any])
        #expect(context["sidecarPath"] as? String == folder.url.appendingPathComponent("context.md").path)
        #expect(context["note"] as? String == "Mind the pacing.")
    }

    @Test func stateHasNoContextWithNoVideo() async throws {
        #expect(try await BatchRig().state()["context"] is NSNull)
    }

    @Test func theButtonSaysWhatTheAgentGets() {
        #expect(!ContextButton.hasContext(sidecar: false, note: ""))
        #expect(ContextButton.hasContext(sidecar: true, note: ""))
        #expect(ContextButton.hasContext(sidecar: false, note: "Mind the pacing."))
        #expect(ContextButton.help(sidecar: "talk.context.md", note: "") == "Context for the agent: talk.context.md")
        #expect(ContextButton.help(sidecar: "context.md", note: "x") == "Context for the agent: context.md and your note")
        #expect(ContextButton.help(sidecar: nil, note: "x") == "Context for the agent: your note")
        #expect(ContextButton.help(sidecar: nil, note: "").hasPrefix("No context for the agent yet."))
    }
}
