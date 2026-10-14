import AppKit
import ReviewCore
import ReviewWire
import SwiftUI

struct ThreadSummary: Hashable {
    var title: String
    var time: String?
    var version: String?
    var state: MessageState?
    var writer: String?
    var byAgent = false
    var writerAgent: KnownAgent?
    var words: String
    var lastAt: Date?
    var waitsForAnswer: Bool
    var isUnread: Bool
    private var agent: String

    init(_ thread: ReviewThread, agent: String, version: VersionTag? = nil) {
        self.agent = agent
        title = thread.isGeneral ? "General" : "#\(thread.number)"
        self.version = version?.label
        time = thread.time.map { TimeCode.text($0.rounded(.down)) }
        state = thread.state
        waitsForAnswer = thread.openQuestion != nil
        isUnread = thread.isUnread
        if let last = thread.messages.last {
            let lastWriter = MessageWriter(last, listener: agent)
            switch (last.author, last.kind) {
            case (.agent, .question): writer = "Asks"
            case (.agent, _): writer = lastWriter.name
            case (.person, _): writer = "You"
            }
            byAgent = last.author == .agent
            writerAgent = lastWriter.agent
            if byAgent { self.agent = lastWriter.name }
            words = last.text.split(whereSeparator: \.isNewline).joined(separator: " ")
            lastAt = last.at
        } else {
            words = thread.isGeneral ? "Talk with the agent about the whole video" : "No messages"
        }
    }

    var preview: String {
        writer.map { "\($0): \(words)" } ?? words
    }

    var text: String {
        let state = waitsForAnswer ? "waiting for your answer" : self.state.map(StateLook.name)
        let preview = writer == "Asks" ? "\(agent) asks: \(words)" : self.preview
        return [isUnread ? "Unread" : nil, title, version, time, state, preview].compactMap(\.self).joined(separator: ", ")
    }
}

enum RowAction: Identifiable {
    case open
    case showOnVideo
    case deleteQueued

    var id: Self { self }

    var title: String {
        switch self {
        case .open: "Open"
        case .showOnVideo: "Show on Video"
        case .deleteQueued: "Delete Queued Messages"
        }
    }

    var symbol: String {
        switch self {
        case .open: "arrow.right.circle"
        case .showOnVideo: "play.rectangle"
        case .deleteQueued: "trash"
        }
    }
}

enum RelativeTime {
    static func short(_ date: Date, now: Date) -> String {
        let seconds = max(now.timeIntervalSince(date), 0)
        switch seconds {
        case ..<45: return "now"
        case ..<3600: return "\(max(Int(seconds / 60), 1))m"
        case ..<86400: return "\(Int(seconds / 3600))h"
        default: return "\(Int(seconds / 86400))d"
        }
    }
}

struct ThreadRow: View {
    let model: WindowModel
    let thread: ReviewThread
    let isOnStage: Bool
    var showsVersion = true
    var isOffVersion = false

    @State private var isHovered = false
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    static let thumbnail = CGSize(width: 88, height: 50)
    static let spacing: CGFloat = 11
    static let padding: CGFloat = 10
    static let unreadDot: CGFloat = 8

    var body: some View {
        let summary = ThreadSummary(thread, agent: model.agentName, version: model.versionTag(of: thread))
        Button { model.perform(.open, on: thread.id) } label: {
            HStack(alignment: .top, spacing: Self.spacing) {
                picture
                    .opacity(isOffVersion ? 0.55 : 1)
                    .saturation(isOffVersion ? 0.3 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    firstLine(summary)
                    preview(summary)
                }
            }
            .padding(.horizontal, Self.padding)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: Self.shape)
            .overlay(alignment: .topLeading) {
                if summary.isUnread { unreadDot }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        .contentShape(.focusEffect, Self.shape)
        .pressedByKeys(in: model) { model.perform(.open, on: thread.id) }
        .animation(.smooth(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
        .contextMenu {
            ForEach(model.rowActions(for: thread)) { action in
                Button(action.title, systemImage: action.symbol, role: action == .deleteQueued ? .destructive : nil) {
                    model.perform(action, on: thread.id)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.text)
        .accessibilityHint("Shows the conversation")
        .accessibilityAddTraits(isOnStage ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.perform(.open, on: thread.id) }
        .accessibilityActions {
            ForEach(model.rowActions(for: thread).filter { $0 != .open }) { action in
                Button(action.title) { model.perform(action, on: thread.id) }
            }
        }
    }

    private static let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    private var fill: Color {
        if isOnStage { return palette[.well] }
        return isHovered ? palette[.controlHover] : .clear
    }

    private func firstLine(_ summary: ThreadSummary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(summary.title)
                .font(.body.weight(summary.isUnread ? .bold : .semibold).monospacedDigit())
                .foregroundStyle(palette[isOffVersion ? .textSecondary : .textPrimary])
            if showsVersion, let version = summary.version {
                Text(version)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(palette[.textSecondary])
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(palette[.well], in: Capsule())
                    .lineLimit(1)
                    .fixedSize()
            }
            if let time = summary.time {
                Text(time)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(palette[.textSecondary])
            }
            if summary.waitsForAnswer {
                Label("Answer", systemImage: "questionmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(palette[.question])
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .fixedSize()
            } else if let state = summary.state {
                StateChip(state: state)
            }
            Spacer(minLength: 4)
            if let at = summary.lastAt {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(RelativeTime.short(at, now: context.date))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(palette[summary.isUnread ? .accent : .textTertiary])
                        .fixedSize()
                }
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette[.textTertiary])
        }
        .frame(height: 18)
    }

    private func preview(_ summary: ThreadSummary) -> some View {
        let writer = summary.writer.map { Text("\($0): ").foregroundStyle(palette[.textTertiary]) } ?? Text("")
        let mark = summary.byAgent ? Text("\(agentMark(summary.writerAgent)) ") : Text("")
        return Text("\(mark)\(writer)\(summary.words)")
            .font(.callout)
            .foregroundStyle(palette[summary.isUnread ? .textPrimary : .textSecondary])
            .lineLimit(2, reservesSpace: false)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var unreadDot: some View {
        Circle()
            .fill(palette[.accent])
            .frame(width: Self.unreadDot, height: Self.unreadDot)
            .offset(x: -Self.unreadDot / 2 + 1, y: 8 + (18 - Self.unreadDot) / 2)
            .accessibilityHidden(true)
    }

    private func agentMark(_ agent: KnownAgent?) -> Text {
        guard let agent, let logo = AgentLogoImage.image(for: agent, dark: colorScheme == .dark),
              let small = logo.copy() as? NSImage
        else {
            return Text(Image(systemName: "sparkles")).foregroundStyle(palette[.agent])
        }
        small.size = NSSize(width: 11, height: 11)
        return Text(Image(nsImage: small)).baselineOffset(-1).foregroundStyle(palette[.textPrimary])
    }

    @ViewBuilder
    private var picture: some View {
        if thread.isGeneral {
            Image(systemName: "globe")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(palette[.textSecondary])
                .frame(width: Self.thumbnail.width, height: Self.thumbnail.height)
                .background(palette[.well], in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityHidden(true)
        } else {
            SidebarPicture(
                file: model.keyframe(of: thread), side: Self.thumbnail.width, regions: thread.messages.compactMap(\.region)
            )
            .frame(width: Self.thumbnail.width, height: Self.thumbnail.height)
        }
    }
}

private struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
