import ReviewCore
import SwiftUI

/// The sidebar's thread list (L38): the title "Threads" with a summary
/// line, then the threads in their groups (`ThreadGroup`) under headers
/// that stay at the top while the list scrolls. A click on a row shows the
/// thread's view.
struct ThreadList: View {
    let model: WindowModel

    @Environment(\.palette) private var palette

    var body: some View {
        let sections = model.threadGroups
        let stageThread = model.stageThread
        VStack(alignment: .leading, spacing: 0) {
            heading
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    ForEach(sections) { section in
                        Section {
                            ForEach(Array(section.threads.enumerated()), id: \.element.id) { index, thread in
                                ThreadRow(model: model, thread: thread, isOnStage: thread.id == stageThread)
                                    .overlay(alignment: .top) {
                                        if index > 0 { rowHairline }
                                    }
                                    // A lazy stack draws a row it made once again only when its
                                    // identity changes: a row whose thread changed is a new one.
                                    .id(RowIdentity(thread: thread, agent: model.agentName, isOnStage: thread.id == stageThread))
                            }
                        } header: {
                            GroupHeader(section: section)
                        }
                    }
                    if !model.threads.contains(where: { !$0.isGeneral }) {
                        empty
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Threads")
    }

    /// "Threads" and the summary line under it.
    private var heading: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Threads")
                .font(.title2.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Text(ThreadListSummary.line(threads: model.threads, queued: model.queuedCount))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(palette[.textTertiary])
        }
        .padding(.horizontal, Metrics.sidebarPadding + 2)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The hairline between two rows of a group, under the words only, as
    /// in Mail.
    private var rowHairline: some View {
        Hairline(axis: .horizontal)
            .padding(.leading, ThreadRow.padding + ThreadRow.thumbnail.width + ThreadRow.spacing)
            .padding(.trailing, ThreadRow.padding)
    }

    /// Under General while no frame has a thread: how one starts. The
    /// compact form of the native empty state (L42): a symbol, a headline
    /// and a callout, since `ContentUnavailableView`'s large title is too
    /// heavy for a narrow sidebar under a row.
    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "text.bubble")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(palette[.textTertiary])
                .padding(.bottom, 2)
                .accessibilityHidden(true)
            Text("No Threads Yet")
                .font(.headline)
                .foregroundStyle(palette[.textSecondary])
            Text("Press C to write on the frame you're watching, or drag on the frame to point at a part of it. Each frame gets its thread; your messages queue, then go to your agent at once.")
                .font(.callout)
                .foregroundStyle(palette[.textTertiary])
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .accessibilityElement(children: .combine)
    }
}

/// What a row shows, as one value: the row is drawn again when it changes.
private struct RowIdentity: Hashable {
    var summary: ThreadSummary
    var regions: Int
    var isOnStage: Bool

    init(thread: ReviewThread, agent: String, isOnStage: Bool) {
        summary = ThreadSummary(thread, agent: agent)
        regions = thread.messages.count { $0.region != nil }
        self.isOnStage = isOnStage
    }
}

/// A group's header in the thread list: its glyph, its name and its count,
/// on the window's surface so the rows scroll under it. Queued says how to
/// send them.
private struct GroupHeader: View {
    let section: ThreadGroup.Section
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: section.group.glyph)
                .imageScale(.small)
                .foregroundStyle(color)
            Text(section.group.title.uppercased())
                .fontWeight(.semibold)
                .tracking(0.2)
            Text("\(section.threads.count)")
                .monospacedDigit()
            Spacer(minLength: 4)
            if let hint = section.group.hint {
                Text(hint)
            }
        }
        .font(.subheadline)
        .foregroundStyle(section.group == .needsYou ? palette[.question] : palette[.textTertiary])
        .padding(.horizontal, ThreadRow.padding)
        .padding(.top, 12)
        .padding(.bottom, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette[.window])
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("\(section.group.title), \(section.threads.count)")
    }

    /// The glyph's colour: the state's that the group holds.
    private var color: Color {
        switch section.group {
        case .needsYou: palette[.question]
        case .withAgent: palette.state(.working)
        case .queued: palette.state(.queued)
        case .done: palette.state(.done)
        }
    }
}
