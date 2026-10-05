import Foundation
import ReviewLease
import Testing

@Suite("The app's variables and their earlier names")
struct AppVariableTests {
    @Test("a HAVOOCH_ variable is read, else its VIDEO_REVIEW_ name")
    func fallback() {
        #expect(AppVariable.value("HAVOOCH_CONTROL_KEY", in: ["HAVOOCH_CONTROL_KEY": "new", "VIDEO_REVIEW_CONTROL_KEY": "old"]) == "new")
        #expect(AppVariable.value("HAVOOCH_CONTROL_KEY", in: ["VIDEO_REVIEW_CONTROL_KEY": "old"]) == "old")
        #expect(AppVariable.value("HAVOOCH_CONTROL_KEY", in: [:]) == nil)
        #expect(AppVariable.earlierName(of: "HAVOOCH_SUPPORT_DIR") == "VIDEO_REVIEW_SUPPORT_DIR")
        #expect(AppVariable.earlierName(of: "PATH") == nil)
    }

    @Test("the earlier key variable still names the holder")
    func earlierKey() {
        let holder = Holder.find(
            variables: ["VIDEO_REVIEW_CONTROL_KEY": "holder-a"], workingDirectory: URL(fileURLWithPath: "/work"),
            processes: NoProcesses()
        )
        #expect(holder.key == "holder-a")
    }

    @Test("a lease handed over in the earlier variable is kept")
    func earlierHandover() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let term = LeaseTerm(holder: Holder(key: "k", name: "Claude Code", place: "/work"), taken: now, ends: now.addingTimeInterval(60))
        let handover = try #require(ControlLease.handover(term)["HAVOOCH_CONTROL_LEASE"])
        let lease = ControlLease(environment: ["VIDEO_REVIEW_CONTROL_LEASE": handover], at: now.addingTimeInterval(10))
        #expect(lease.current(at: now.addingTimeInterval(10)) == term)
    }
}

/// A process table with no process in it.
private struct NoProcesses: ProcessTable {
    var currentPID: Int32 { 1 }
    func process(_ pid: Int32) -> ProcessRecord? { nil }
}
