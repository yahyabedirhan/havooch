import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// No video open: where to drop one, a button to choose one, and in a demo
/// run the demo folder's videos, one click each.
struct EmptyState: View {
    let demoFolder: URL?
    let open: (URL) -> Void

    var body: some View {
        VStack(spacing: Theme.gap) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("Open a video to review")
                .font(.title2.weight(.semibold))
            Text("Drop an mp4, mov or m4v file here, or choose one.")
                .foregroundStyle(.secondary)
            Button("Open…") {
                if let url = VideoPicker.choose() { open(url) }
            }
            .controlSize(.large)
            .padding(.top, 4)
            if let demoFolder {
                demoVideos(in: demoFolder)
            }
        }
        .padding(Theme.edge * 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func demoVideos(in folder: URL) -> some View {
        let videos = VideoPicker.videos(in: folder)
        if !videos.isEmpty {
            VStack(spacing: 6) {
                Text("In the demo folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(videos, id: \.self) { video in
                    Button {
                        open(video)
                    } label: {
                        Label(video.lastPathComponent, systemImage: "film")
                    }
                    .buttonStyle(.link)
                }
            }
            .padding(.top, Theme.gap)
        }
    }
}

/// The video files a person can choose: the kinds the spec names.
@MainActor
enum VideoPicker {
    static let extensions = ["mp4", "mov", "m4v"]

    /// The standard open panel, for one video file; nil when cancelled.
    static func choose() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie, UTType("com.apple.m4v-video") ?? .movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// The video files directly in `folder`, by name.
    static func videos(in folder: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { extensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
