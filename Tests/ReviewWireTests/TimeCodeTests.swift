import ReviewWire
import Testing

@Suite("Time codes")
struct TimeCodeTests {
    @Test("seconds and mm:ss read as seconds", arguments: [
        ("0", 0.0), ("90", 90), ("12.5", 12.5), ("0:10", 10), ("1:30", 90), ("01:30", 90),
        ("90:00", 5400), ("0:01:30.5", 90.5), ("1:00:00", 3600), ("0:07.25", 7.25),
    ])
    func reads(text: String, seconds: Double) {
        #expect(TimeCode.seconds(text) == seconds)
    }

    @Test("what isn't a time is refused", arguments: [
        "", "abc", "-5", "1:99", "1:60", "1:75:00", "1:2:3:4", ":30", "1:", "1e3", " 10", "1.2.3", ".5", "5.", "1.5:00",
    ])
    func refuses(text: String) {
        #expect(TimeCode.seconds(text) == nil)
    }

    static let tooManyDigits = String(repeating: "9", count: 400)

    @Test("digits too many for a number are no time: nothing reads as infinity", arguments: [
        tooManyDigits, "\(tooManyDigits).5", "\(tooManyDigits):00", "\(tooManyDigits):00:00",
    ])
    func refusesOverflow(text: String) {
        #expect(TimeCode.seconds(text) == nil)
    }

    @Test("many digits after the point are still a time")
    func readsLongFraction() {
        #expect(TimeCode.seconds("1.\(String(repeating: "0", count: 400))") == 1)
    }

    @Test("seconds are written as m:ss", arguments: [
        (0.0, "0:00"), (10, "0:10"), (12.5, "0:12.5"), (21.233, "0:21.233"), (90, "1:30"), (3600, "1:00:00"),
        (3725.25, "1:02:05.25"), (9.9996, "0:10"),
    ])
    func writes(seconds: Double, text: String) {
        #expect(TimeCode.text(seconds) == text)
    }
}
