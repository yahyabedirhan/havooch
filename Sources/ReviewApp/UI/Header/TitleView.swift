import Foundation
import ReviewWire
import SwiftUI

struct HeaderWords: Equatable {
    struct Project: Equatable {
        var title: String
        var version: String
    }

    var title: String
    var subtitle: String?
    var folder: String?
    var fullPath: String?
    var isProject = false
    var isShown: Bool

    static let subtitleLimit = 56
    static let projectFolderLimit = 40

    init(video: URL?, isDemo: Bool, project: Project? = nil, home: String = NSHomeDirectory()) {
        title = video?.lastPathComponent ?? AppIdentity.appName
        isShown = video != nil
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

    static func tilde(_ path: String, home: String) -> String {
        guard !home.isEmpty, home != "/" else { return path }
        if path == home { return "~" }
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    static func shortened(_ text: String, to limit: Int) -> String {
        guard text.count > limit, limit > 1 else { return text }
        let kept = limit - 1
        let head = (kept + 1) / 2
        let tail = kept - head
        return String(text.prefix(head)) + "…" + String(text.suffix(tail))
    }
}

struct TitleView: View {
    let words: HeaderWords
    let model: WindowModel
    @Environment(\.palette) private var palette

    var body: some View {
        if words.isShown {
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
    }

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
                if words.isProject, let session = model.compare, model.isComparing {
                    ComparingBadge(model: model, session: session)
                } else if words.isProject, let versions = model.versionSwitch {
                    VersionSwitcher(model: model, versions: versions)
                    if model.canCompare {
                        CompareButton(model: model)
                    }
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
