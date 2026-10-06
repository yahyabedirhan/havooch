import Foundation
import ReviewWire
import SwiftUI

/// The words of the window's header: the video's file name with its
/// extension, and under it the folder it is in, shortened in the middle,
/// or "Demo" on demo data. Pure, so the words are tested without a window.
struct HeaderWords: Equatable {
    /// `sample.mp4`; the app's name while no video is open.
    var title: String
    /// `~/Movies/…/Reviews`, or `Demo`; nil while no video is open on the
    /// person's own data.
    var subtitle: String?
    /// The folder's full path, shown on hover; nil while no video is open.
    var fullPath: String?

    /// The longest subtitle, in characters, before its middle is cut out.
    static let subtitleLimit = 56

    /// - Parameters:
    ///   - video: the open video's file, if any.
    ///   - isDemo: whether this run is on demo data.
    ///   - home: the home folder, written as `~`.
    init(video: URL?, isDemo: Bool, home: String = NSHomeDirectory()) {
        title = video?.lastPathComponent ?? AppIdentity.appName
        let folder = video.map { $0.deletingLastPathComponent().path }
        fullPath = folder
        if isDemo {
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
struct TitleView: View {
    let words: HeaderWords
    /// A click on the cat mark goes home on it (`AppModel.goHome`).
    let model: AppModel
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
                .accessibilityElement(children: .combine)
        }
        .padding(.leading, 4)
    }

    /// The file name, and under it the folder.
    private var lines: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label {
                Text(words.title)
                    .font(.headline)
                    .foregroundStyle(palette[.textPrimary])
            } icon: {
                Image(systemName: "film")
                    .foregroundStyle(palette[.textSecondary])
            }
            .labelStyle(HeaderLabelStyle())
            if let subtitle = words.subtitle {
                Label {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(palette[.textSecondary])
                } icon: {
                    Image(systemName: "folder")
                        .foregroundStyle(palette[.textTertiary])
                }
                .labelStyle(HeaderLabelStyle())
                .help(words.fullPath ?? "")
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
