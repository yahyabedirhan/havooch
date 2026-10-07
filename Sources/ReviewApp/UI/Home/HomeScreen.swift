import ReviewWire
import SwiftUI

/// What the stage shows: the player with a video open; with none, the home
/// screen when there are recent videos, else the empty state.
enum StageContent: Equatable {
    case player, home, empty

    init(hasVideo: Bool, hasRecents: Bool) {
        self = hasVideo ? .player : hasRecents ? .home : .empty
    }

    /// What the stage of `model` shows now.
    init(_ model: AppModel) {
        self.init(hasVideo: model.video != nil, hasRecents: !model.recents.isEmpty)
    }

    /// The sidebar shows beside the player only: never on the home screen
    /// or the empty state.
    var showsSidebar: Bool { self == .player }

    /// The screen `state` reports: the player, or home for the home
    /// screen and the empty state alike, the screens with no video.
    var screen: StateReport.Screen { self == .player ? .player : .home }
}

/// No video is open and there are recent videos: the cat mark and the
/// app's name, "Open a Video…" and "Try the Demo", then the recent videos
/// as a gallery of cards, the newest first, as Finder shows files in icon
/// view. The whole screen takes a dropped video, as the empty state does.
struct HomeScreen: View {
    let model: AppModel
    @Environment(\.palette) private var palette

    /// Adaptive columns of 16:9 cards.
    private static let columns = [GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 20, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                top
                gallery
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 36)
            .frame(maxWidth: 1040)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .videoDropTarget(model)
    }

    private var top: some View {
        VStack(spacing: 14) {
            HavoochMark(size: 64)
            Text(AppIdentity.appName)
                .font(.largeTitle.weight(.semibold))
            HStack(spacing: 10) {
                Button("Open a Video…") { model.openFromPanel() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                if DemoRun.video() != nil {
                    Button("Try the Demo") { model.tryDemo() }
                        .help("Open the launch video on demo data, apart from your own reviews")
                }
            }
            .padding(.top, 4)
        }
    }

    private var gallery: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Videos")
                .font(.headline)
                .foregroundStyle(palette[.textSecondary])
                .accessibilityAddTraits(.isHeader)
            // The relative times move on with the clock.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 20) {
                    ForEach(model.recents, id: \.contentHash) { recent in
                        RecentCard(model: model, recent: recent, now: context.date)
                    }
                }
            }
        }
    }
}
