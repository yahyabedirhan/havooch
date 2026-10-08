import ReviewWire
import SwiftUI

/// What the stage shows: the player with a video open; with none, the home
/// screen when there are recent videos or projects, else the empty state.
enum StageContent: Equatable {
    case player, home, empty

    init(hasVideo: Bool, hasRecents: Bool) {
        self = hasVideo ? .player : hasRecents ? .home : .empty
    }

    /// What the stage of `model` shows now.
    init(_ model: WindowModel) {
        self.init(hasVideo: model.video != nil, hasRecents: !model.recents.isEmpty || !model.homeProjects.isEmpty)
    }

    /// The sidebar shows beside the player only: never on the home screen
    /// or the empty state.
    var showsSidebar: Bool { self == .player }

    /// The screen `state` reports: the player, or home for the home
    /// screen and the empty state alike, the screens with no video.
    var screen: StateReport.Screen { self == .player ? .player : .home }
}

/// No video is open and there are recent videos or projects: the cat mark
/// and the app's name, "Open a Video…" and "Try the Demo", then the
/// projects (story 48), the most recently opened first, then the recent
/// videos, each as a gallery of cards, the newest first, as Finder shows
/// files in icon view. The whole screen takes a dropped video, as the empty state does.
struct HomeScreen: View {
    let model: WindowModel
    @Environment(\.palette) private var palette

    /// Adaptive columns of 16:9 cards.
    private static let columns = [GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 20, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                top
                if !model.homeProjects.isEmpty { projects }
                if !model.recents.isEmpty { gallery }
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
                    .filledButton(palette)
                    .keyboardShortcut(.defaultAction)
                if DemoRun.video() != nil {
                    Button("Try the Demo") { model.tryDemo() }
                        .help("Open the launch video on demo data, apart from your own reviews")
                }
            }
            .padding(.top, 4)
        }
    }

    private var projects: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Projects")
                .font(.headline)
                .foregroundStyle(palette[.textSecondary])
                .accessibilityAddTraits(.isHeader)
            TimelineView(.periodic(from: .now, by: 60)) { context in
                LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 20) {
                    ForEach(model.homeProjects, id: \.slug) { project in
                        ProjectCard(model: model, project: project, now: context.date)
                    }
                }
            }
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
