import AppKit
import SwiftUI

/// One project on the home screen (story 48): its latest version's
/// thumbnail at 16:9 with the version's number on it, the project's title,
/// and how many versions it has and when it was last opened. A click opens
/// the latest version in the project, as `havooch open <path> --project
/// <slug>` does. A project whose latest file isn't there is dimmed and
/// does nothing.
struct ProjectCard: View {
    let model: WindowModel
    let project: StateReport.HomeProject
    let now: Date
    @State private var isHovered = false
    @Environment(\.palette) private var palette

    /// `3 versions, opened 2 hours ago`, or `1 version` before it was opened.
    nonisolated static func detail(_ project: StateReport.HomeProject, now: Date) -> String {
        let count = "\(project.versions) version\(project.versions == 1 ? "" : "s")"
        guard project.available else { return "\(count), unavailable" }
        guard let opened = project.openedAt else { return count }
        return "\(count), opened \(RecentCard.openedLabel(opened, now: now).lowercased())"
    }

    var body: some View {
        Button { model.openProject(project.slug) } label: { card }
            .buttonStyle(.plain)
            .disabled(!project.available)
            .help(project.latestPath ?? project.title)
            .onHover { isHovered = $0 }
            .task(id: Thumbnails.key(of: project)) { await model.thumbnails.load(project) }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 6) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(project.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(Self.detail(project, now: now))
                    .font(.callout)
                    .foregroundStyle(palette[.textSecondary])
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
            .opacity(project.available ? 1 : 0.6)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(project.title), project, \(Self.detail(project, now: now))")
    }

    private var thumbnail: some View {
        let shape = RoundedRectangle(cornerRadius: RecentCard.corner, style: .continuous)
        return ZStack(alignment: .bottomLeading) {
            palette[.well]
            if project.available, let image = model.thumbnails.image(for: project) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                Image(systemName: project.available ? "film" : "video.slash")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(palette[.textTertiary])
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if project.versions > 0 {
                Text("v\(project.versions)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(palette[.popover], in: Capsule())
                    .padding(8)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(shape)
        .overlay {
            let picked = isHovered && project.available
            shape.strokeBorder(picked ? palette[.accent] : palette[.separator], lineWidth: picked ? 2 : 1)
        }
        .opacity(project.available ? 1 : 0.5)
        .animation(.smooth(duration: 0.15), value: isHovered)
    }
}
