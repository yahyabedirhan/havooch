import ReviewCore
import SwiftUI

struct SidebarView: View {
    let model: WindowModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shown = model.shown.flatMap { id in model.threads.first { $0.id == id } }
        ZStack {
            if model.connect != nil {
                ConnectView(model: model)
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing))
                    .zIndex(2)
            } else if let shown {
                ThreadView(model: model, thread: shown)
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing))
                    .zIndex(1)
            } else {
                ThreadList(model: model)
                    .transition(reduceMotion ? .opacity : .move(edge: .leading))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        .animation(SidebarColumn.animation(reduceMotion: reduceMotion), value: shown == nil)
        .animation(SidebarColumn.animation(reduceMotion: reduceMotion), value: model.connect == nil)
    }
}
