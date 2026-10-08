import AppKit
import Observation
import ReviewCore

/// The app's windows (ADR 0003): which window holds which video, which
/// one is key, and the windows made for a scene that hasn't shown yet.
/// No two windows hold the same video: `holding` finds the one that does,
/// so an open of it brings that window forward.
@Observable
final class WindowRegistry {
    /// The open windows, in the order they were made.
    private(set) var windows: [WindowModel] = []
    /// The windows' ids, the one key or made last first: the key window
    /// is the first of them while the app is in the back, and no window
    /// is key.
    @ObservationIgnored private var recency: [String] = []
    /// How many windows this run has made: ids are never used twice.
    @ObservationIgnored private var made = 0
    /// Windows made for a scene that hasn't appeared yet, oldest first:
    /// a new window's scene takes one as it appears (`place`).
    @ObservationIgnored private var unplaced: [WindowModel] = []
    /// Opens a scene for a window, with what it holds; nil holds nothing.
    /// The app sets it from a view's `openWindow`, so it's nil before a
    /// window has shown, and in tests.
    @ObservationIgnored var openScene: ((WindowTarget?) -> Void)?

    /// The id the next window takes: `w1`, `w2`…
    func nextID() -> String {
        made += 1
        return "w\(made)"
    }

    /// Adds `window` as the latest, key until another one is.
    func add(_ window: WindowModel) {
        windows.append(window)
        recency.insert(window.id, at: 0)
    }

    /// Adds `window` and opens a scene for it: the scene takes it as it
    /// appears. False when no scene can be opened yet.
    @discardableResult
    func show(_ window: WindowModel) -> Bool {
        if !windows.contains(where: { $0 === window }) { add(window) }
        guard let openScene else { return false }
        unplaced.append(window)
        openScene(window.target)
        return true
    }

    /// The window a scene that appeared with `target` shows: the one made
    /// for it, else the oldest one waiting for a scene; nil when none
    /// waits, and the scene needs a new window.
    func place(_ target: WindowTarget?) -> WindowModel? {
        let index = target.flatMap { target in unplaced.firstIndex { $0.target == target } } ?? unplaced.indices.first
        return index.map { unplaced.remove(at: $0) }
    }

    /// The window `id` names; nil for none.
    func window(_ id: String) -> WindowModel? {
        windows.first { $0.id == id }
    }

    /// The window that holds the review `key`: a plain video, or a
    /// project whichever version is on screen. Its listener's notices show
    /// there; nil when none does, and nobody sees them.
    func holding(_ key: ReviewKey) -> WindowModel? {
        windows.first { $0.reviewKey == key }
    }

    /// The window `nsWindow` shows; nil for another window (Settings, a panel).
    func window(showing nsWindow: NSWindow?) -> WindowModel? {
        guard let nsWindow else { return nil }
        return windows.first { $0.nsWindow === nsWindow }
    }

    /// The key window: the one that has the keys, else the one that had
    /// them last, else the one made last. Nil with no window.
    var key: WindowModel? {
        windows.first { $0.nsWindow?.isKeyWindow == true } ?? recency.lazy.compactMap { self.window($0) }.first
    }

    /// `window` became key.
    func becameKey(_ window: WindowModel) {
        recency.removeAll { $0 == window.id }
        recency.insert(window.id, at: 0)
    }

    /// `window` closed: it's no longer one of the app's windows.
    func remove(_ window: WindowModel) {
        windows.removeAll { $0 === window }
        unplaced.removeAll { $0 === window }
        recency.removeAll { $0 == window.id }
    }

    /// The windows' ids, for a refusal: `w1, w2`, or `none`.
    var names: String {
        windows.isEmpty ? "none" : windows.map(\.id).joined(separator: ", ")
    }
}
