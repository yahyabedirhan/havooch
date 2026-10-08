import Foundation
import ReviewStore
import ReviewTranscript

/// The data a run works on: a support folder and what reads and writes the
/// reviews in it, the listeners' lines and the transcripts. `AppModel` holds
/// one and replaces it to switch to the demo folder and back (L27). The
/// theme is a preference, not review data, so it isn't in it.
struct DataFolder {
    /// The support folder.
    let support: URL
    /// Every path under the support folder.
    let layout: SupportLayout
    /// The reviews in this folder, and the one path for changing them.
    let desk: ReviewDesk
    /// The listeners, one per review, on this folder's outboxes.
    let listeners: ListenerHub
    /// The transcripts, with speech kept in this folder.
    let transcripts: TranscriptDesk

    /// The data in `support`, read from what the folder holds; `speech`
    /// turns a video's sound into lines when it has no sidecar.
    init(support: URL, speech: any SpeechRecognizing) {
        self.support = support
        layout = SupportLayout(root: support)
        desk = ReviewDesk(library: Library(layout: layout))
        listeners = ListenerHub(desk: desk, layout: layout)
        transcripts = TranscriptDesk(layout: layout, speech: speech)
    }
}
