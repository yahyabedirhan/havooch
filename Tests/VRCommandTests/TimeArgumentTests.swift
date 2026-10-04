import Testing
@testable import VRCommand

@Suite struct TimeArgumentTests {
    @Test(arguments: [
        ("10", 10.0), ("10.5", 10.5), ("0", 0), ("90", 90), (".5", 0.5),
        ("0:10", 10), ("1:02", 62), ("12:00", 720), ("0:10.25", 10.25), ("75:00", 4500),
        ("1:02:03", 3723), ("0:00:00", 0),
    ])
    func aTimeReadsAsSeconds(text: String, seconds: Double) {
        #expect(TimeArgument.seconds(text) == seconds)
    }

    @Test(arguments: ["", "abc", "-5", "+5", "1e3", "1:60", "1:2:3:4", ":10", "10:", "1::2", "1:75:00", "0x10", "1.2.3", ".", "1.5:00"])
    func whatIsNotATimeIsRefused(text: String) {
        #expect(TimeArgument.seconds(text) == nil)
    }
}
