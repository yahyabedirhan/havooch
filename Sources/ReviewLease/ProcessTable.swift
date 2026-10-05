#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
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

/// The system's process table: through `sysctl` on macOS, `/proc` on Linux.
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
        // `pid (name) state parent …`, the start in clock ticks after boot
        // as the 22nd field. The name may hold spaces and parentheses, so
        // the fields are read after its last `)`.
        guard let stat = try? String(contentsOfFile: "/proc/\(pid)/stat", encoding: .utf8),
              let open = stat.firstIndex(of: "("), let close = stat.lastIndex(of: ")")
        else { return nil }
        let fields = stat[stat.index(after: close)...].split(separator: " ")
        guard fields.count > 19, let parent = Int32(fields[1]), let ticks = Double(fields[19]),
              let boot = Self.bootTime
        else { return nil }
        return ProcessRecord(
            pid: pid,
            parent: parent,
            started: Date(timeIntervalSince1970: boot + ticks / Double(sysconf(Int32(_SC_CLK_TCK)))),
            name: String(stat[stat.index(after: open)..<close])
        )
    }

    /// When the system started, in seconds since 1970: `btime` in `/proc/stat`.
    private static var bootTime: TimeInterval? {
        guard let stat = try? String(contentsOfFile: "/proc/stat", encoding: .utf8) else { return nil }
        let line = stat.split(separator: "\n").first { $0.hasPrefix("btime ") }
        return line.flatMap { TimeInterval($0.dropFirst("btime ".count)) }
    }
    #endif
}
