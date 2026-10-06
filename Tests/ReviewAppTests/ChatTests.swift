import Foundation
@testable import ReviewApp
import ReviewCore
import Testing

/// The conversation as a chat (L40), apart from how it looks: who wrote
/// each message and with which logo, where a run of the agent's messages
/// starts and ends, what VoiceOver reads, and which actions a message's
/// menu has.
@Suite("The conversation as a chat")
struct ChatTests {
    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func message(
        _ number: Int, _ author: Message.Author, _ kind: Message.Kind = .message, state: MessageState? = nil,
        region: Region? = nil, session: String? = nil
    ) -> Message {
        Message(
            id: ItemID("m-f92cbb2a-\(number)")!, author: author, kind: kind, text: "Words \(number)", at: Self.now,
            region: region, state: state, sessionName: session
        )
    }

    @Test("an agent's message keeps the name and logo of the session that wrote it; one kept with no name takes the listener's")
    func writer() {
        let codex = MessageWriter(message(1, .agent, session: "Codex CLI"), listener: "Claude Code")
        #expect(codex.name == "Codex CLI")
        #expect(codex.agent == .codex)
        let old = MessageWriter(message(2, .agent), listener: "Claude Code")
        #expect(old.name == "Claude Code")
        #expect(old.agent == .claude)
        let unknown = MessageWriter(message(3, .agent, .question, session: "pipeline"), listener: "Claude Code")
        #expect(unknown.name == "pipeline")
        #expect(unknown.agent == nil)
        let person = MessageWriter(message(4, .person, state: .sent), listener: "Claude Code")
        #expect(person.name == "You")
        #expect(person.agent == nil)
    }

    @Test("a row's preview names the session that wrote the agent's last message, and shows its logo")
    func rowWriter() {
        let id = ItemID("t-f92cbb2a-1")!
        let codex = ThreadSummary(ReviewThread(id: id, time: 5, messages: [message(1, .agent, session: "Codex CLI")]), agent: "Claude Code")
        #expect(codex.preview == "Codex CLI: Words 1")
        #expect(codex.writerAgent == .codex)
        let old = ThreadSummary(ReviewThread(id: id, time: 5, messages: [message(2, .agent, .question)]), agent: "Claude Code")
        #expect(old.text == "Unread, #1, 0:05, waiting for your answer, Claude Code asks: Words 2")
        #expect(old.writerAgent == .claude)
        let person = ThreadSummary(ReviewThread(id: id, time: 5, messages: [message(3, .person, state: .queued)]), agent: "Claude Code")
        #expect(person.writerAgent == nil)
    }

    @Test("the agent's name shows at the start of each run of its messages, and its avatar at the end")
    func runs() {
        let messages = [
            message(1, .person, state: .sent), message(2, .agent), message(3, .agent), message(4, .agent, .question),
            message(5, .person, .answer), message(6, .agent),
        ]
        let places = messages.indices.map { ChatRun(of: $0, in: messages) }
        #expect(places.map(\.startsRun) == [false, true, false, false, false, true])
        #expect(places.map(\.endsRun) == [false, false, false, true, false, true])
    }

    @Test("VoiceOver reads each message with its writer, its kind and its state")
    func spoken() throws {
        let box = try Region(x: 0.1, y: 0.1, w: 0.2, h: 0.2)
        #expect(MessageVoice.text(message(1, .person, state: .queued, region: box), writer: "You", isOpenQuestion: false)
            == "You, message, Queued, on a region: Words 1")
        #expect(MessageVoice.text(message(2, .person, state: .done), writer: "You", isOpenQuestion: false)
            == "You, message, Done: Words 2")
        #expect(MessageVoice.text(message(3, .agent, session: "Codex"), writer: "Codex", isOpenQuestion: false)
            == "Codex, reply: Words 3")
        #expect(MessageVoice.text(message(4, .agent, .question), writer: "Codex", isOpenQuestion: true)
            == "Codex, question, waiting for your answer: Words 4")
        #expect(MessageVoice.text(message(5, .agent, .question), writer: "Codex", isOpenQuestion: false)
            == "Codex, question, answered: Words 5")
        #expect(MessageVoice.text(message(6, .person, .answer), writer: "You", isOpenQuestion: false)
            == "You, answer, sent at once: Words 6")
    }

    @Test("a queued message can be edited, deleted and copied; any other message only copied")
    func messageActions() {
        #expect(MessageAction.all(for: message(1, .person, state: .queued)) == [.edit, .delete, .copy])
        for state in MessageState.allCases where state != .queued {
            #expect(MessageAction.all(for: message(2, .person, state: state)) == [.copy])
        }
        #expect(MessageAction.all(for: message(3, .person, .answer)) == [.copy])
        #expect(MessageAction.all(for: message(4, .agent)) == [.copy])
        #expect(MessageAction.all(for: message(5, .agent, .question)) == [.copy])
    }
}
