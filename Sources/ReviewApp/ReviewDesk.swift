import Foundation
import Observation
import ReviewCore
import ReviewStore

/// The one path for changing a review: take a review, run the change, save
/// it, publish it to the views. Every window on the data reads its review
/// here, by its key: a plain video's content hash, or a project's slug. A
/// refused change, and one that can't be saved, leaves the review as it
/// was, in memory and on disk.
///
/// A review is read from the `Library` the first time it's asked for and
/// kept in memory from then on, by key, so a send of a review that's not
/// open, or wasn't opened in this run, can still be delivered and answered.
@Observable
final class ReviewDesk {
    /// The reviews this run has read or made, by key. A view that shows
    /// one follows its changes.
    private var reviews: [ReviewKey: Review] = [:]
    @ObservationIgnored let library: Library

    init(library: Library) {
        self.library = library
    }

    /// The review `key` opens on with `video` on screen: the one kept, or a
    /// new one. A new review's id prefix is one no other review has.
    /// Refused when the kept one doesn't read; nothing changes, and nothing
    /// is written over it.
    func review(for video: VideoInfo, in key: ReviewKey) throws(AppRefusal) -> Review {
        if let kept = try kept(key) { return kept }
        switch key {
        case .video(let contentHash):
            return Review(video: video, hash8: freeHash8(ItemID.hash8(of: contentHash), seed: contentHash, for: key))
        case .project(let slug):
            return Review(project: slug, video: video, hash8: freeHash8(Self.hex8("project:\(slug)"), seed: slug, for: key))
        }
    }

    /// Keeps `review`, as `review(for:in:)` gave it, for a window that opens
    /// it. A review that's on disk is saved when its video moved, was
    /// renamed or is another version; a new one is first saved with its
    /// first change. It stays kept when its window closes, so a listener
    /// can still answer on it.
    func open(_ review: Review) {
        let isKept = FileManager.default.fileExists(atPath: library.layout.reviewFile(review.key).path)
        if isKept, reviews[review.key] != review {
            // Not being able to record the new path doesn't keep the video shut.
            try? library.save(review)
        }
        reviews[review.key] = review
    }

    /// The review `key` as this run keeps it, never read from disk: what a
    /// window that opened it shows.
    func opened(_ key: ReviewKey) -> Review? {
        reviews[key]
    }

    /// The review `key`, open or not; nil when there's none, or it doesn't
    /// read.
    func review(of key: ReviewKey) -> Review? {
        try? kept(key)
    }

    /// The review `key`, open or not; nil when there's none yet. Refused
    /// when it doesn't read, so a caller can stop before changing anything.
    func readable(_ key: ReviewKey) throws(AppRefusal) -> Review? {
        try kept(key)
    }

    /// The review the thread, message or send `id` is on, by its prefix;
    /// nil when no review has it. A listener's command names an id and no
    /// review.
    func key(of id: ItemID) -> ReviewKey? {
        library.key(of: id)
    }

    /// The thread a command names, and its review: a full id names its
    /// review by its prefix, a bare number is a thread of the review
    /// `open`, the window's (`0` is General). Refused for what isn't a
    /// thread of a review.
    func threadID(_ text: String, open: ReviewKey?) throws(AppRefusal) -> (ThreadID, ReviewKey) {
        let ref = ThreadRef(text)
        let key: ReviewKey? = switch ref {
        case .id(let id): self.key(of: id)
        case .number: open
        case nil: nil
        }
        guard let ref, let key, let review = review(of: key) else {
            throw AppRefusal(
                "no thread `\(text)`; give a thread id from the send `havooch wait` printed, or a number of the open video"
            )
        }
        do throws(ReviewRefusal) {
            return (try review.threadID(ref), key)
        } catch {
            throw AppRefusal(error.line)
        }
    }

    /// Runs `change` on the review `key`, open in a window or not, saves
    /// it, and publishes the result.
    func change<Result>(
        _ key: ReviewKey, _ change: (inout Review) throws(ReviewRefusal) -> Result
    ) throws(AppRefusal) -> Result {
        guard var changed = try kept(key) else {
            throw AppRefusal("there's no review of \(Self.name(key))")
        }
        let before = changed
        let result: Result
        do throws(ReviewRefusal) {
            result = try change(&changed)
        } catch {
            throw AppRefusal(error.line)
        }
        guard changed != before else { return result }
        do throws(Library.Failure) {
            try library.save(changed)
        } catch {
            throw AppRefusal("nothing changed: \(error.reason)")
        }
        reviews[key] = changed
        return result
    }

    /// Moves the plain video's review `old` into the project `slug`
    /// (`project new --from`): the same threads, messages,
    /// sends and ids, each thread on a frame anchored to `anchor`, v1. Nil
    /// when the video has no review yet: the project starts with a new one.
    /// Refused when the review doesn't read, or can't be written; nothing
    /// moves then.
    @discardableResult
    func adopt(_ old: ReviewKey, into slug: String, anchor: VersionAnchor) throws(AppRefusal) -> Review? {
        guard let review = try kept(old) else { return nil }
        let adopted = review.adoptedIntoProject(slug, anchor: anchor)
        do throws(Library.Failure) {
            try library.move(adopted, from: old)
        } catch {
            throw AppRefusal("the threads didn't move into the project: \(error.reason)")
        }
        reviews[old] = nil
        reviews[adopted.key] = adopted
        return adopted
    }

    /// The review `key`: this run's, else the one on disk, which this run
    /// then has.
    private func kept(_ key: ReviewKey) throws(AppRefusal) -> Review? {
        if let review = reviews[key] { return review }
        do throws(Library.Failure) {
            let review = try library.load(key)
            reviews[key] = review
            return review
        } catch {
            throw AppRefusal(error.reason)
        }
    }

    /// `preferred`, unless another review has it: then another eight hex
    /// digits from `seed`, so two reviews never share an id prefix. A plain
    /// video whose content a project adopted gets a new prefix this way.
    private func freeHash8(_ preferred: String, seed: String, for key: ReviewKey) -> String {
        var candidate = preferred
        var attempt = 1
        while library.isTaken(candidate, by: key) || reviews.values.contains(where: { $0.hash8 == candidate && $0.key != key }) {
            candidate = Self.hex8("\(seed)#\(attempt)")
            attempt += 1
        }
        return candidate
    }

    /// Eight lowercase hex digits from `text`: the first half of its 64-bit
    /// FNV-1a hash.
    static func hex8(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
        let digits = String(hash, radix: 16)
        return String((String(repeating: "0", count: 16 - digits.count) + digits).prefix(8))
    }

    /// `the video <hash>` or `the project <slug>`.
    static func name(_ key: ReviewKey) -> String {
        switch key {
        case .video(let contentHash): "the video \(contentHash)"
        case .project(let slug): "the project \(slug)"
        }
    }
}
