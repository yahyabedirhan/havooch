import Foundation
import ReviewWire
import SwiftUI

/// The words of the window's header: the video's file name with its
/// extension, and under it the folder it is in, shortened in the middle,
/// or "Demo" on demo data. In a project (version-switcher V5): the
/// project's title, and under it the version on screen, then the folder.
/// Pure, so the words are tested without a window.
struct HeaderWords: Equatable {
    /// A project's words: its title, and the version on screen as the
    /// line under it says it (`v2 · tighter intro`, or `a removed version`).
    struct Project: Equatable {
        var title: String
        var version: String
    }

    /// `sample.mp4`, or the project's title; the app's name while no
    /// video is open.
    var title: String
    /// `~/Movies/…/Reviews`, or `Demo`, or in a project the version on
    /// screen; nil while no video is open on the person's own data.
    var subtitle: String?
    /// In a project, the folder (or `Demo`) after the version, quieter;
    /// nil otherwise.
    var folder: String?
    /// The folder's full path, shown on hover; nil while no video is open.
    var fullPath: String?
    /// Whether the window holds a project: the title's icon is the
    /// project's, and the switcher follows the title.
    var isProject = false

    /// The longest subtitle, in characters, before its middle is cut out.
    static let subtitleLimit = 56
    /// The longest folder after a project's version, in characters.
    static let projectFolderLimit = 40

    /// - Parameters:
    ///   - video: the open video's file, if any.
    ///   - isDemo: whether this run is on demo data.
    ///   - project: in a project, its title and the version on screen,
    ///     which take the file name's and the folder's places; the folder
    ///     follows the version.
    ///   - home: the home folder, written as `~`.
    init(video: URL?, isDemo: Bool, project: Project? = nil, home: String = NSHomeDirectory()) {
        title = video?.lastPathComponent ?? AppIdentity.appName
        let folder = video.map { $0.deletingLastPathComponent().path }
        fullPath = folder
        if let project, video != nil {
            isProject = true
            title = project.title
            subtitle = project.version
            self.folder = isDemo ? "Demo" : folder.map { Self.shortened(Self.tilde($0, home: home), to: Self.projectFolderLimit) }
        } else if isDemo {
            subtitle = "Demo"
        } else if let folder {
            subtitle = Self.shortened(Self.tilde(folder, home: home), to: Self.subtitleLimit)
        } else {
            subtitle = nil
        }
    }

    /// `path` with the home folder written as `~`.
    static func tilde(_ path: String, home: String) -> String {
        guard !home.isEmpty, home != "/" else { return path }
        if path == home { return "~" }
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    /// `text` with its middle replaced by `…` so it is at most `limit`
    /// characters long: the start and the end of a path say the most.
    static func shortened(_ text: String, to limit: Int) -> String {
        guard text.count > limit, limit > 1 else { return text }
        let kept = limit - 1
        let head = (kept + 1) / 2
        let tail = kept - head
        return String(text.prefix(head)) + "…" + String(text.suffix(tail))
    }
}

/// The header's title, at the window's leading edge beside the traffic
/// lights: the cat mark, which goes home, a video icon and the file name,
/// and under it a folder icon and the folder, with the full path on hover.
/// In a project: the project's title with the version switcher after it,
/// and under it the version on screen, then the folder.
struct TitleView: View {
    let words: HeaderWords
    /// A click on the cat mark goes home on it (`WindowModel.goHome`).
    let model: WindowModel
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            Button {
                model.goHomeForPerson()
            } label: {
                HavoochMark(size: 22)
            }
            .buttonStyle(.plain)
            .pressedByKeys(in: model) { model.goHomeForPerson() }
            .help("Home")
            .accessibilityLabel("Home")
            lines
        }
        .padding(.leading, 4)
    }

    /// The file name, and under it the folder; in a project, the title
    /// with the switcher after it, and under them the version and the
    /// folder.
    private var lines: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 10) {
                Label {
                    Text(words.title)
                        .font(.headline)
                        .foregroundStyle(palette[.textPrimary])
                } icon: {
                    Image(systemName: words.isProject ? "film.stack" : "film")
                        .foregroundStyle(palette[.textSecondary])
                }
                .labelStyle(HeaderLabelStyle())
                .accessibilityElement(children: .combine)
                if words.isProject, let versions = model.versionSwitch {
                    VersionSwitcher(model: model, versions: versions)
                }
            }
            if let subtitle = words.subtitle {
                Label {
                    HStack(spacing: 0) {
                        Text(subtitle)
                            .foregroundStyle(palette[.textSecondary])
                        if let folder = words.folder {
                            Text("  ·  \(folder)")
                                .foregroundStyle(palette[.textTertiary])
                        }
                    }
                    .font(.subheadline)
                } icon: {
                    Image(systemName: "folder")
                        .foregroundStyle(palette[.textTertiary])
                }
                .labelStyle(HeaderLabelStyle())
                .help(words.fullPath ?? "")
                .accessibilityElement(children: .combine)
            }
        }
        .lineLimit(1)
        .truncationMode(.middle)
    }
}

/// An icon and its words on one line, with a small gap and the icon
/// sized to the words.
private struct HeaderLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon
                .imageScale(.small)
                .frame(width: 14)
                .accessibilityHidden(true)
            configuration.title
        }
    }
}
