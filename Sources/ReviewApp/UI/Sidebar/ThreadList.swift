import ReviewCore
import SwiftUI

struct ThreadList: View {
    let model: WindowModel

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading
            if let tree = model.versionTree {
                VersionList(model: model, tree: tree)
            } else {
                groups
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Threads")
    }

    private var groups: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(model.threadGroups) { section in
                    Section {
                        ThreadRows(model: model, threads: section.threads)
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

    private var heading: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Threads")
                .font(.title2.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Text(ThreadListSummary.line(
                threads: model.threads, queued: model.queuedCount, versions: model.projectOutline?.versions.count
            ))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(palette[.textTertiary])
        }
        .padding(.horizontal, Metrics.sidebarPadding + 2)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

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

struct ThreadRows: View {
    let model: WindowModel
    let threads: [ReviewThread]
    var showsVersion = true
    var isOffVersion = false

    var body: some View {
        let stageThread = model.stageThread
        let ringedThread = model.tourRings(.thread) ? model.tourReplyThread : nil
        ForEach(Array(threads.enumerated()), id: \.element.id) { index, thread in
            let isRinged = ringedThread == thread.id
            ThreadRow(
                model: model, thread: thread, isOnStage: thread.id == stageThread, showsVersion: showsVersion,
                isOffVersion: isOffVersion && !thread.isGeneral
            )
            .padding(.top, index > 0 ? Self.rowGap : 0)
            .overlay(alignment: .top) {
                if index > 0 { rowHairline }
            }
            .coachRing(isRinged, radius: 10, padding: CoachRing.tightPadding)
            .id(RowIdentity(
                thread: thread, agent: model.agentName, isOnStage: thread.id == stageThread, isRinged: isRinged
            ))
        }
    }

    static let rowGap: CGFloat = 2

    private var rowHairline: some View {
        Hairline(axis: .horizontal)
            .padding(.leading, ThreadRow.padding + ThreadRow.thumbnail.width + ThreadRow.spacing)
            .padding(.trailing, ThreadRow.padding)
    }
}

private struct RowIdentity: Hashable {
    var summary: ThreadSummary
    var regions: Int
    var isOnStage: Bool
    var isRinged: Bool

    init(thread: ReviewThread, agent: String, isOnStage: Bool, isRinged: Bool) {
        summary = ThreadSummary(thread, agent: agent)
        regions = thread.messages.count { $0.region != nil }
        self.isOnStage = isOnStage
        self.isRinged = isRinged
    }
}

private struct GroupHeader: View {
    let section: ThreadGroup.Section
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: section.group.glyph)
                .imageScale(.small)
                .foregroundStyle(section.group.color(palette))
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
}
