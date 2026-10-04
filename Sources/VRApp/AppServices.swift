import AppKit
import Foundation
import VRWire

/// The composition root: reads the environment, builds every part of the app
/// once and wires them together.
@MainActor
final class AppServices {
    static let shared = AppServices(variables: ProcessInfo.processInfo.environment)

    /// The support folder: the normal one, or a demo run's own.
    let support: URL
    let player: PlayerController
    let model: ReviewModel
    let server: ControlServer
    private let shortcuts: Shortcuts

    init(variables: [String: String]) {
        support = AppIdentity.supportFolder(variables: variables)
        let demoFolder = variables[AppIdentity.demoVariable].flatMap {
            $0.hasPrefix("/") ? URL(fileURLWithPath: $0, isDirectory: true) : nil
        }
        let player = PlayerController()
        let model = ReviewModel(player: player, demoFolder: demoFolder)
        let screenshotter = Screenshotter { NSApp.windows.first { $0.isVisible && $0.canBecomeMain } }
        self.player = player
        self.model = model
        server = ControlServer(
            socket: ControlSocket.url(in: support),
            model: model,
            desk: OperatorDesk(model: model) { await screenshotter.capture(to: $0, appearance: $1) },
            quit: { NSApp.terminate(nil) }
        )
        shortcuts = Shortcuts(model: model)
    }

    /// Starts listening for commands and for the player's keys. An app that
    /// can't listen still works for a person, and says why on standard error.
    func start() {
        do throws(ControlServer.Failure) {
            try server.start()
        } catch {
            FileHandle.standardError.write(Data("video-review: no app control: \(error.description)\n".utf8))
        }
        shortcuts.install()
    }

    /// Stops listening and removes the socket.
    func stop() {
        server.stop()
        shortcuts.remove()
    }
}
