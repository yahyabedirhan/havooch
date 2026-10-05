#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation

/// One process as the process table has it.
public struct ProcessRecord: Equatable, Sendable {
    public var pid: Int32
    public var parent: Int32
    /// When it started: with the pid, it names the process even once the
    /// pid is reused.
    public var started: Date
    /// Its command's name (`zsh`, a login shell's `-zsh`, `claude`).
    public var name: String

    public init(pid: Int32, parent: Int32, started: Date, name: String) {
        self.pid = pid
        self.parent = parent
        self.started = started
        self.name = name
    }
}

/// The processes `Holder.find` walks up through: macOS's process table in
/// production, a fake in tests.
public protocol ProcessTable: Sendable {
    /// This process: the `video-review` command.
    var currentPID: Int32 { get }
    /// The process `pid`, or nil when there's none (or it can't be read).
    func process(_ pid: Int32) -> ProcessRecord?
}

/// The system's process table: through `sysctl` on macOS, and through
/// `/proc` on Linux, where the package's agent side is built and tested too.
public struct SystemProcessTable: ProcessTable {
    public init() {}

    public var currentPID: Int32 { getpid() }

    #if canImport(Darwin)
    public func process(_ pid: Int32) -> ProcessRecord? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        // A pid nobody has is no error: the answer is just empty.
        guard sysctl(&name, u_int(name.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        let command = withUnsafeBytes(of: info.kp_proc.p_comm) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        return ProcessRecord(
            pid: pid,
            parent: info.kp_eproc.e_ppid,
            started: Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000),
            name: command
        )
    }
    #else
    public func process(_ pid: Int32) -> ProcessRecord? {
        // A pid nobody has is no error: the answer is just empty.
        guard let stat = try? String(contentsOfFile: "/proc/\(pid)/stat", encoding: .utf8),
              let record = Self.record(stat: stat, pid: pid, bootTime: Self.bootTime())
        else { return nil }
        return record
    }

    /// The record in a line of `/proc/<pid>/stat`: `pid (name) state ppid …`,
    /// with the start time in clock ticks after boot as its 22nd field. The
    /// name sits in parentheses and may hold spaces and parentheses itself,
    /// so the fields are read after its last `)`.
    static func record(stat: String, pid: Int32, bootTime: TimeInterval) -> ProcessRecord? {
        guard let open = stat.firstIndex(of: "("), let close = stat.lastIndex(of: ")") else { return nil }
        let name = String(stat[stat.index(after: open)..<close])
        // Field 3 (state) is the first after the name; the parent is field 4, the start field 22.
        let fields = stat[stat.index(after: close)...].split(separator: " ")
        guard fields.count > 19, let parent = Int32(fields[1]), let ticks = Double(fields[19]) else { return nil }
        let started = bootTime + ticks / Double(sysconf(Int32(_SC_CLK_TCK)))
        return ProcessRecord(pid: pid, parent: parent, started: Date(timeIntervalSince1970: started), name: name)
    }

    /// When the machine started, from the `btime` line of `/proc/stat`.
    private static func bootTime() -> TimeInterval {
        let stat = (try? String(contentsOfFile: "/proc/stat", encoding: .utf8)) ?? ""
        let line = stat.split(separator: "\n").first { $0.hasPrefix("btime ") }
        return line.flatMap { TimeInterval($0.dropFirst("btime ".count)) } ?? 0
    }
    #endif
}
