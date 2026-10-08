import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// What a path is, as setup reads it.
public enum FileItem: Equatable, Sendable {
    /// Nothing is there.
    case missing
    case file
    case folder
    /// A symbolic link, with its destination as written in it.
    case link(to: String)
    /// Something stops Havooch from looking: a folder it may not read.
    case unreadable
}

/// The file system as setup reads and changes it: the seam the tests fake.
/// Paths are absolute.
public protocol SetupFileSystem: Sendable {
    /// What is at `path`, a link read as a link (`lstat`).
    func item(at path: String) -> FileItem
    /// What is at `path` once every link on the way is followed (`stat`):
    /// never `.link`.
    func target(at path: String) -> FileItem
    /// Makes the folder at `path` with its parents, as `mkdir -p`.
    func makeFolder(at path: String) throws
    /// Makes a symbolic link at `path` that points to `destination`.
    func makeLink(at path: String, to destination: String) throws
    /// Removes the link or the file at `path`.
    func remove(at path: String) throws
}

/// The Mac's file system.
public struct LocalFileSystem: SetupFileSystem {
    public init() {}

    public func item(at path: String) -> FileItem {
        var info = stat()
        guard lstat(path, &info) == 0 else { return Self.failure(errno) }
        if info.st_mode & mode_t(S_IFMT) == mode_t(S_IFLNK) {
            guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: path) else { return .unreadable }
            return .link(to: destination)
        }
        return Self.kind(info)
    }

    public func target(at path: String) -> FileItem {
        var info = stat()
        guard stat(path, &info) == 0 else { return Self.failure(errno) }
        return Self.kind(info)
    }

    public func makeFolder(at path: String) throws {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    public func makeLink(at path: String, to destination: String) throws {
        try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: destination)
    }

    public func remove(at path: String) throws {
        try FileManager.default.removeItem(atPath: path)
    }

    private static func kind(_ info: stat) -> FileItem {
        info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) ? .folder : .file
    }

    /// A path that isn't there is missing; any other failure (no
    /// permission, a loop of links) means Havooch can't know.
    private static func failure(_ code: Int32) -> FileItem {
        code == ENOENT || code == ENOTDIR ? .missing : .unreadable
    }
}
