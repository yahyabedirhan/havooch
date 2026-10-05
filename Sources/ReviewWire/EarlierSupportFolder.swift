import Foundation

/// The support folder the app had before it was renamed Havooch
/// (docs/adr/0002): `~/Library/Application Support/Video Review/`. A launch
/// on the person's own data moves what's in it to the support folder, so
/// whoever updates keeps every review, theme and setting.
///
/// The move runs only for the real support folder: never when
/// `HAVOOCH_SUPPORT_DIR` (or its earlier name) moves it, which every demo
/// run and every test does. It never runs while the earlier app runs, which
/// still writes there. It moves each top-level item that the support folder
/// doesn't already have, and never overwrites one. The earlier app's socket
/// and demo pointer stay behind: they only meant something while it ran.
/// Once nothing else is left, the earlier folder is removed, so later
/// launches find nothing to do.
public enum EarlierSupportFolder {
    /// The folder's name under `~/Library/Application Support/`.
    public static let name = "Video Review"

    /// The earlier app's bundle id: the move waits while it runs.
    public static let bundleID = "com.yahyabedirhan.video-review"

    /// What's never moved: the earlier app's socket and demo pointer.
    static let leftBehind: Set<String> = [ControlSocket.fileName, DemoPointer.fileName]

    /// What a launch did about the earlier folder.
    public enum Outcome: Equatable, Sendable {
        /// The support folder is moved elsewhere, or there's no earlier folder.
        case nothingToDo
        /// The earlier app runs: nothing moved; the next launch tries again.
        case earlierAppRuns
        /// The items moved, and those kept in the earlier folder because
        /// the support folder already has one of that name or the move
        /// failed, by name.
        case moved(moved: [String], kept: [String])
    }

    /// Moves the earlier folder's items into the support folder, for a
    /// launch with `environment`.
    ///
    /// - Parameters:
    ///   - applicationSupport: the folder both support folders are in;
    ///     tests give a temporary one.
    ///   - earlierAppRuns: whether the earlier app runs now.
    public static func move(
        environment: [String: String],
        applicationSupport: URL = SupportFolder.applicationSupport,
        earlierAppRuns: Bool
    ) -> Outcome {
        guard SupportFolder.moved(environment: environment) == nil else { return .nothingToDo }
        let files = FileManager.default
        let earlier = applicationSupport.appendingPathComponent(name, isDirectory: true)
        let support = SupportFolder.app(environment: environment, applicationSupport: applicationSupport)
        var isFolder: ObjCBool = false
        guard earlier.standardizedFileURL != support.standardizedFileURL,
              files.fileExists(atPath: earlier.path, isDirectory: &isFolder), isFolder.boolValue
        else { return .nothingToDo }
        guard !earlierAppRuns else { return .earlierAppRuns }
        guard let items = try? files.contentsOfDirectory(atPath: earlier.path) else {
            return .moved(moved: [], kept: [])
        }
        var moved: [String] = []
        var kept: [String] = []
        do {
            try files.createDirectory(at: support, withIntermediateDirectories: true)
        } catch {
            return .moved(moved: [], kept: items.filter { !leftBehind.contains($0) }.sorted())
        }
        for item in items.sorted() where !leftBehind.contains(item) {
            let target = support.appendingPathComponent(item)
            // Never over what the support folder has: `fileExists` follows a
            // link, so a dangling one is checked as itself.
            let taken = files.fileExists(atPath: target.path) || (try? files.destinationOfSymbolicLink(atPath: target.path)) != nil
            if !taken, (try? files.moveItem(at: earlier.appendingPathComponent(item), to: target)) != nil {
                moved.append(item)
            } else {
                kept.append(item)
            }
        }
        if kept.isEmpty {
            for item in leftBehind {
                try? files.removeItem(at: earlier.appendingPathComponent(item))
            }
            // Only an empty folder goes: whatever appeared meanwhile stays.
            if (try? files.contentsOfDirectory(atPath: earlier.path))?.isEmpty == true {
                try? files.removeItem(at: earlier)
            }
        }
        return .moved(moved: moved, kept: kept)
    }
}
