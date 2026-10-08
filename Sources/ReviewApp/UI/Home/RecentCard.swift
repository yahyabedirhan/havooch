import AppKit
import SwiftUI

/// One recent video on the home screen: its thumbnail at 16:9, the file's
/// name without its extension and when it was last opened. Hover shows the
/// full path. A click opens the video; the context menu shows it in Finder
/// or removes it from the recent videos. A video that is not on the disk
/// any more is dimmed, with an "unavailable" symbol and a trash button
/// that removes it; a click on the rest of it does nothing.
struct RecentCard: View {
    let model: WindowModel
    let recent: StateReport.Recent
    let now: Date
    @State private var isHovered = false
    @Environment(\.palette) private var palette

    static let corner: CGFloat = 10

    /// Where a thumbnail is taken, in seconds: the saved position, or 1
    /// second when the video has none.
    nonisolated static func thumbnailTime(position: Double) -> Double {
        position > 0 ? position : 1
    }

    /// When the video was last opened, as the card says it: "Just now"
    /// under a minute, else relative to `now` ("2 hours ago").
    nonisolated static func openedLabel(_ opened: Date, now: Date, locale: Locale = .current) -> String {
        guard now.timeIntervalSince(opened) >= 60 else { return "Just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .numeric
        return formatter.localizedString(for: opened, relativeTo: now)
    }

    var body: some View {
        Group {
            if recent.available {
                Button { model.openRecent(recent) } label: { card }
                    .buttonStyle(CardButtonStyle())
                    .contextMenu {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([recent.url]) }
                        Divider()
                        Button("Remove from Recents") { model.removeRecent(recent.contentHash) }
                    }
            } else {
                card
                    .overlay(alignment: .topTrailing) { trash }
            }
        }
        .help(recent.path)
        .onHover { isHovered = $0 }
        .task(id: Thumbnails.key(of: recent)) { await model.thumbnails.load(recent) }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 6) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(recent.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(recent.available ? Self.openedLabel(recent.openedAt, now: now) : "Unavailable")
                    .font(.callout)
                    .foregroundStyle(palette[.textSecondary])
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
            .opacity(recent.available ? 1 : 0.6)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(recent.available ? recent.title : "\(recent.title), unavailable")
    }

    private var thumbnail: some View {
        let shape = RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
        return ZStack {
            palette[.well]
            if recent.available, let image = model.thumbnails.image(for: recent) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                Image(systemName: recent.available ? "film" : "video.slash")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(palette[.textTertiary])
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(shape)
        .overlay {
            // Hover picks out a card that opens.
            let picked = isHovered && recent.available
            shape.strokeBorder(picked ? palette[.accent] : palette[.separator], lineWidth: picked ? 2 : 1)
        }
        .opacity(recent.available ? 1 : 0.5)
        .animation(.smooth(duration: 0.15), value: isHovered)
    }

    /// Removes an unavailable video from the recent videos.
    private var trash: some View {
        Button { model.removeRecent(recent.contentHash) } label: {
            Image(systemName: "trash")
                .padding(6)
                .background(palette[.popover], in: Circle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(palette[.textSecondary])
        .padding(8)
        .help("Remove from Recents")
        .accessibilityLabel("Remove \(recent.title) from Recents")
    }
}

/// A card's button: the card as it is drawn, a little dimmed while
/// pressed. The system focus ring still goes around it under keyboard
/// navigation.
private struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
