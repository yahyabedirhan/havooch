import Foundation
import Observation
import ReviewCore
import ReviewStore

@Observable
final class ReviewDesk {
    private var reviews: [ReviewKey: Review] = [:]
    @ObservationIgnored let library: Library

    init(library: Library) {
        self.library = library
    }

    func review(for video: VideoInfo, in key: ReviewKey) throws(AppRefusal) -> Review {
        if let kept = try kept(key) { return kept }
        switch key {
        case .video(let contentHash):
            return Review(video: video, hash8: freeHash8(ItemID.hash8(of: contentHash), seed: contentHash, for: key))
        case .project(let slug):
            return Review(project: slug, video: video, hash8: freeHash8(Self.hex8("project:\(slug)"), seed: slug, for: key))
        }
    }

    func open(_ review: Review) {
        let isKept = FileManager.default.fileExists(atPath: library.layout.reviewFile(review.key).path)
        if isKept, reviews[review.key] != review {
            try? library.save(review)
        }
        reviews[review.key] = review
    }

    func opened(_ key: ReviewKey) -> Review? {
        reviews[key]
    }

    func review(of key: ReviewKey) -> Review? {
        try? kept(key)
    }

    func readable(_ key: ReviewKey) throws(AppRefusal) -> Review? {
        try kept(key)
    }

    func key(of id: ItemID) -> ReviewKey? {
        library.key(of: id)
    }

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

    private func freeHash8(_ preferred: String, seed: String, for key: ReviewKey) -> String {
        var candidate = preferred
        var attempt = 1
        while library.isTaken(candidate, by: key) || reviews.values.contains(where: { $0.hash8 == candidate && $0.key != key }) {
            candidate = Self.hex8("\(seed)#\(attempt)")
            attempt += 1
        }
        return candidate
    }

    static func hex8(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
        let digits = String(hash, radix: 16)
        return String((String(repeating: "0", count: 16 - digits.count) + digits).prefix(8))
    }

    static func name(_ key: ReviewKey) -> String {
        switch key {
        case .video(let contentHash): "the video \(contentHash)"
        case .project(let slug): "the project \(slug)"
        }
    }
}
