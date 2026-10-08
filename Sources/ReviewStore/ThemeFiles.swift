import Foundation
import ReviewCore

/// Reads theme files into `ThemeFile` values: the built-in ones shipped in
/// the app bundle (`Contents/Resources/Themes/`, from `Packaging/Themes/`),
/// and the person's own in `themes/` beside `config.toml`. A file that
/// doesn't read is skipped, with its reason.
public enum ThemeFiles {
    /// A theme file that read, and where it is.
    public struct Found: Equatable, Sendable {
        public var file: ThemeFile
        public var url: URL
    }

    /// What a folder of theme files gave.
    public struct Reading: Equatable, Sendable {
        /// In the order of their file names.
        public var found: [Found] = []
        /// One line per file that didn't read.
        public var problems: [String] = []

        public init(found: [Found] = [], problems: [String] = []) {
            self.found = found
            self.problems = problems
        }

        public var files: [ThemeFile] { found.map(\.file) }
    }

    /// The `.json` files in `folder`, in the order of their names. A
    /// folder that isn't there has none.
    public static func read(_ folder: URL) -> Reading {
        var reading = Reading()
        for url in jsonFiles(in: folder) {
            do throws(ThemeFile.Unreadable) {
                guard let data = try? Data(contentsOf: url) else { throw ThemeFile.Unreadable(reason: "it can't be read") }
                reading.found.append(Found(file: try ThemeFile.decode(data), url: url))
            } catch {
                reading.problems.append("\(url.path) is left out: \(error.reason)")
            }
        }
        return reading
    }

    /// The theme files directly in `folder`, sorted by name.
    public static func jsonFiles(in folder: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
