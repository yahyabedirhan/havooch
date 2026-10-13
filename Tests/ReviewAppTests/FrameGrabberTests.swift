import AVFoundation
@testable import ReviewApp
import Testing

/// Reading a frame tries again when the decoder fails for a moment, and
/// gives up on any other error at once.
@Suite("A frame read tries again when the decoder fails")
struct FrameGrabberTests {
    @Test("a decode failure is read again until the last try")
    func decodeFailureReadsAgain() {
        let error = AVError(.decodeFailed)
        #expect(FrameGrabber.readsAgain(after: error, attempt: 1))
        #expect(FrameGrabber.readsAgain(after: error, attempt: FrameGrabber.readAttempts - 1))
        #expect(!FrameGrabber.readsAgain(after: error, attempt: FrameGrabber.readAttempts))
    }

    @Test("any other error ends the read at once")
    func otherErrorEndsAtOnce() {
        #expect(!FrameGrabber.readsAgain(after: AVError(.fileFormatNotRecognized), attempt: 1))
        #expect(!FrameGrabber.readsAgain(after: CancellationError(), attempt: 1))
    }
}
