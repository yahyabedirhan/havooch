import Foundation

/// Where the settings file and the person's themes are (ADR 0002): the one
/// definition, so the `havooch` command and the app can't disagree.
///
///     <folder>/config.toml          the settings: the theme, the projects
///     <folder>/themes/<name>.json   the person's own themes
///
/// The folder is, in this order:
///
/// 1. `<support>/config/` when `HAVOOCH_SUPPORT_DIR` moves the support
///    folder, so a check, a test or a demo run on a scratch folder never
///    reads or writes the person's settings;
/// 2. `$XDG_CONFIG_HOME/havooch/` when that variable holds an absolute path;
/// 3. `~/.config/havooch/`.
///
/// A pure value: it touches no file.
public struct ConfigLocation: Equatable, Sendable {
    public static let folderName = "havooch"
    public static let fileName = "config.toml"
    public static let themesFolderName = "themes"
    /// The folder's name inside a support folder `HAVOOCH_SUPPORT_DIR` moved.
    public static let movedFolderName = "config"

    /// The folder of the file and the themes.
    public let folder: URL
    /// The person's home folder: a leading `~` in the file's paths stands
    /// for it.
    public let home: URL

    public init(folder: URL, home: URL) {
        self.folder = folder
        self.home = home
    }

    /// The location `variables` give. `movedSupport` is the support folder
    /// `HAVOOCH_SUPPORT_DIR` names, when it names one
    /// (`SupportFolder.moved`). The home folder is `HOME` when it is an
    /// absolute path, else the user's.
    public init(variables: [String: String], movedSupport: URL?) {
        let home = variables["HOME"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0, isDirectory: true) : nil }
            ?? FileManager.default.homeDirectoryForCurrentUser
        let folder: URL
        if let movedSupport {
            folder = movedSupport.appendingPathComponent(Self.movedFolderName, isDirectory: true)
        } else if let xdg = variables["XDG_CONFIG_HOME"], xdg.hasPrefix("/") {
            folder = URL(fileURLWithPath: xdg, isDirectory: true).appendingPathComponent(Self.folderName, isDirectory: true)
        } else {
            folder = home.appendingPathComponent(".config", isDirectory: true).appendingPathComponent(Self.folderName, isDirectory: true)
        }
        self.init(folder: folder, home: home)
    }

    /// `config.toml`.
    public var file: URL { folder.appendingPathComponent(Self.fileName, isDirectory: false) }
    /// The person's own themes.
    public var themesFolder: URL { folder.appendingPathComponent(Self.themesFolderName, isDirectory: true) }

    /// `path` with a leading `~` standing for the home folder, as a file URL.
    public func expand(_ path: String) -> URL {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home.appendingPathComponent(String(path.dropFirst(2))) }
        return URL(fileURLWithPath: path)
    }
}
