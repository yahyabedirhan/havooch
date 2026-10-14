import Foundation
import ReviewStore
import ReviewTranscript

struct DataFolder {
    let support: URL
    let layout: SupportLayout
    let desk: ReviewDesk
    let listeners: ListenerHub
    let transcripts: TranscriptDesk

    init(support: URL, speech: any SpeechRecognizing) {
        self.support = support
        layout = SupportLayout(root: support)
        desk = ReviewDesk(library: Library(layout: layout))
        listeners = ListenerHub(desk: desk, layout: layout)
        transcripts = TranscriptDesk(layout: layout, speech: speech)
    }
}
