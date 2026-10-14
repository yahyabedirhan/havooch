import AppKit
import Observation
import ReviewCore

@Observable
final class WindowRegistry {
    private(set) var windows: [WindowModel] = []
    @ObservationIgnored private var recency: [String] = []
    @ObservationIgnored private var made = 0
    @ObservationIgnored private var unplaced: [WindowModel] = []
    @ObservationIgnored var openScene: ((WindowTarget?) -> Void)?

    func nextID() -> String {
        made += 1
        return "w\(made)"
    }

    func add(_ window: WindowModel) {
        windows.append(window)
        recency.insert(window.id, at: 0)
    }

    @discardableResult
    func show(_ window: WindowModel) -> Bool {
        if !windows.contains(where: { $0 === window }) { add(window) }
        guard let openScene else { return false }
        unplaced.append(window)
        openScene(window.target)
        return true
    }

    func place(_ target: WindowTarget?) -> WindowModel? {
        let index = target.flatMap { target in unplaced.firstIndex { $0.target == target } } ?? unplaced.indices.first
        return index.map { unplaced.remove(at: $0) }
    }

    func window(_ id: String) -> WindowModel? {
        windows.first { $0.id == id }
    }

    func holding(_ key: ReviewKey) -> WindowModel? {
        windows.first { $0.reviewKey == key }
    }

    func window(showing nsWindow: NSWindow?) -> WindowModel? {
        guard let nsWindow else { return nil }
        return windows.first { $0.nsWindow === nsWindow }
    }

    var key: WindowModel? {
        windows.first { $0.nsWindow?.isKeyWindow == true } ?? recency.lazy.compactMap { self.window($0) }.first
    }

    func becameKey(_ window: WindowModel) {
        recency.removeAll { $0 == window.id }
        recency.insert(window.id, at: 0)
    }

    func remove(_ window: WindowModel) {
        windows.removeAll { $0 === window }
        unplaced.removeAll { $0 === window }
        recency.removeAll { $0 == window.id }
    }

    var names: String {
        windows.isEmpty ? "none" : windows.map(\.id).joined(separator: ", ")
    }
}
