import Foundation
@testable import ReviewApp

extension ControlServer {
    func replyWritten(to request: Data, connection: UUID? = nil) async -> Answer {
        let answer = await reply(to: request, connection: connection)
        written(answer)
        return answer
    }
}
