import Foundation
@testable import ReviewApp
import ReviewCore
import Testing

@Suite("The player bar")
struct PlayerBarTests {
    private static func message(_ number: Int, region: Region? = nil, state: MessageState = .queued) -> Message {
        Message(
            id: ItemID(.message, hash8: "f92cbb2a", number: number), author: .person, kind: .message, text: "note",
            at: Date(timeIntervalSince1970: 0), region: region, state: state
        )
    }

    private static func thread(_ number: Int, at time: Double, _ messages: [Message]) -> ReviewThread {
        ReviewThread(id: ItemID(.thread, hash8: "f92cbb2a", number: number), time: time, messages: messages)
    }

    @Test("a thread with any region has a rounded square pin, one without has a circle")
    func shape() throws {
        let region = try Region(x: 0.1, y: 0.1, w: 0.2, h: 0.2)
        #expect(!ThreadPin.Look(Self.thread(1, at: 4, [Self.message(1)])).isSquare)
        #expect(ThreadPin.Look(Self.thread(2, at: 4, [Self.message(2), Self.message(3, region: region)])).isSquare)
    }

    @Test("hover shows the number, the time, the regions and the state")
    func help() throws {
        let region = try Region(x: 0.1, y: 0.1, w: 0.2, h: 0.2)
        let two = Self.thread(3, at: 12.48, [
            Self.message(1, region: region, state: .working), Self.message(2, region: region, state: .working),
        ])
        #expect(ThreadPin.Look(two).help == "#3 · 0:12 · 2 regions · Working")
        let one = Self.thread(4, at: 75, [Self.message(3, region: region, state: .done), Self.message(4, state: .done)])
        #expect(ThreadPin.Look(one).help == "#4 · 1:15 · 1 region · Done")
        #expect(ThreadPin.Look(Self.thread(5, at: 0.5, [Self.message(5)])).help == "#5 · 0:00 · no region · Queued")
    }

    @Test("the pin's state is the thread's: its latest open person message")
    func state() {
        let thread = Self.thread(1, at: 4, [Self.message(1, state: .done), Self.message(2, state: .sent)])
        #expect(ThreadPin.Look(thread).state == .sent)
    }

    @Test("the speed menu reads 0.5×, 1×, 1.25×, 1.5×, 2×")
    func speeds() {
        let english = Locale(identifier: "en_US")
        #expect(PlayerEngine.speeds.map { PlayerBar.label($0, locale: english) } == ["0.5×", "1×", "1.25×", "1.5×", "2×"])
    }

    @Test("the time labels take round steps and leave the last label its room")
    func ticks() {
        #expect(Timeline.ticks(in: 21, width: 600) == [0, 5, 10, 15, 20])
        #expect(Timeline.ticks(in: 21, width: 580) == [0, 5, 10, 15])
        #expect(Timeline.ticks(in: 0, width: 600).isEmpty)
    }
}
