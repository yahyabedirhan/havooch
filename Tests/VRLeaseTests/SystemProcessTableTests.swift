import Foundation
import Testing
@testable import VRLease

/// The system's process table, read for real: through `sysctl` on macOS and
/// `/proc` on Linux.
struct SystemProcessTableTests {
    let table = SystemProcessTable()

    @Test func theTestsOwnProcessIsInTheTableWithItsParentAndAStartInThePast() throws {
        let record = try #require(table.process(table.currentPID))
        #expect(record.pid == table.currentPID)
        #expect(record.parent > 0)
        #expect(!record.name.isEmpty)
        #expect(record.started < Date())
        #expect(record.started > Date(timeIntervalSinceNow: -86_400 * 365))
    }

    @Test func theParentIsInTheTableToo() throws {
        let record = try #require(table.process(table.currentPID))
        #expect(table.process(record.parent) != nil)
    }

    @Test func aPidNobodyHasHasNoRecord() {
        #expect(table.process(Int32.max) == nil)
    }
}
