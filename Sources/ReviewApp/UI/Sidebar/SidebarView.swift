import ReviewCore
import SwiftUI

/// The sidebar of threads (D 3.2 to D 3.7): General first, then each
/// thread in time order, above the footer (`SidebarFooter`). No batches. Each thread is a
/// collapsed row; the one the person picked shows expanded, with its
/// conversation and its field (L33).
///
/// Background colour segments the sidebar, not bordered cards: a header
/// band over the expanded thread, its own fill under it, and only the
/// messages in bubbles (D 5.9). Its column (`SidebarColumn`) keeps the
/// width the person gives it (D 5.10).
struct SidebarView: View {
    let model: AppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.palette) private var palette

    var body: some View {
        let threads = model.threads
        return ScrollViewReader { scroll in
            ScrollView {
                // Not lazy: a review has tens of threads, not thousands,
                // and a row that changes state must be drawn again.
                VStack(spacing: 0) {
                    ForEach(threads) { thread in
                        Group {
                            if model.expanded == thread.id {
                                ThreadConversation(model: model, thread: thread)
                            } else {
                                ThreadRow(model: model, thread: thread)
                            }
                        }
                        .id(thread.id)
                        .transition(.opacity)
                    }
                    if !threads.contains(where: { !$0.isGeneral }) {
                        empty
                    }
                }
                .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: model.expanded)
                .padding(.bottom, 12)
            }
            .onChange(of: model.expanded) { _, expanded in
                // The expanded thread reads from its header down; the list
                // opens at the top (General) and moves only on an expansion.
                guard let expanded else { return }
                if reduceMotion {
                    scroll.scrollTo(expanded, anchor: .top)
                } else {
                    withAnimation(.smooth(duration: 0.35)) { scroll.scrollTo(expanded, anchor: .top) }
                }
            }
        }
    }

    /// Under General while no frame has a thread: how one starts.
    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(palette[.textTertiary])
                .padding(.bottom, 2)
            Text("No threads yet")
                .font(.headline)
            Text("Press C to write on the frame you're watching, or drag on the frame to point at a part of it. Each frame gets its thread; your messages queue, then go to your agent at once.")
                .font(.callout)
                .foregroundStyle(palette[.textSecondary])
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
        .padding(.top, 48)
        .frame(maxWidth: .infinity)
    }
}
