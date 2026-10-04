import SwiftUI

/// What the window shows with no video open: the button, and a word about
/// the other two ways in (a drop, Cmd+O).
struct EmptyState: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "play.rectangle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("Open a video")
                .font(.title2.weight(.semibold))
            Text("Drop an mp4, mov or m4v file here, or choose one.")
                .foregroundStyle(.secondary)
            Button("Choose a Video…") { model.chooseVideo() }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
