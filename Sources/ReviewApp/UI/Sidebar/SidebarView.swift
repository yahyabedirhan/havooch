import ReviewCore
import SwiftUI

/// The sidebar's two views (L38), above the footer (`SidebarFooter`): the
/// thread list (`ThreadList`), or the view of one thread (`ThreadView`)
/// while `WindowModel.shown` names one. A thread view slides in from the
/// trailing edge over the list and back out, with the sidebar's own
/// spring; with Reduce Motion the two fade.
///
/// The sidebar is on the window's one surface: a row under the pointer
/// takes `controlHover`, the row of the thread on the stage sits in a
/// `well`, and only the messages are in bubbles. Its column
/// (`SidebarColumn`) keeps the width the person gives it (D 5.10).
struct SidebarView: View {
    let model: WindowModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shown = model.shown.flatMap { id in model.threads.first { $0.id == id } }
        ZStack {
            if let shown {
                ThreadView(model: model, thread: shown)
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing))
                    .zIndex(1)
            } else {
                ThreadList(model: model)
                    .transition(reduceMotion ? .opacity : .move(edge: .leading))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The view sliding out never draws over the stage.
        .clipped()
        .animation(SidebarColumn.animation(reduceMotion: reduceMotion), value: shown == nil)
    }
}
