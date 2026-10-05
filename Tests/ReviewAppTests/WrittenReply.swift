import Foundation
@testable import ReviewApp

extension ControlServer {
    /// Answers `request` as the socket does when it wrote the reply to its
    /// client: a send the reply carries is taken from then on. A test that
    /// calls `reply(to:)` alone leaves such a send in flight, as a reply
    /// still being written.
    func replyWritten(to request: Data, connection: UUID? = nil) async -> Answer {
        let answer = await reply(to: request, connection: connection)
        written(answer)
        return answer
    }
}
