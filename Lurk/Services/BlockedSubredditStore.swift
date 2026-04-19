import Foundation

@Observable
final class BlockedSubredditStore {
    private static let storageKey = "lurk.blockedSubreddits"
    private static let seedDefaults = ["bald", "spaceporn"]

    private(set) var blockedNames: Set<String> = []

    init() {
        load()
    }

    var sortedNames: [String] {
        blockedNames.sorted { $0.lowercased() < $1.lowercased() }
    }

    func block(_ name: String) {
        blockedNames.insert(name.lowercased())
        persist()
    }

    func unblock(_ name: String) {
        blockedNames.remove(name.lowercased())
        persist()
    }

    func isBlocked(_ name: String) -> Bool {
        blockedNames.contains(name.lowercased())
    }

    private func load() {
        if let stored = UserDefaults.standard.array(forKey: Self.storageKey) as? [String] {
            blockedNames = Set(stored)
        } else {
            blockedNames = Set(Self.seedDefaults)
            persist()
        }
    }

    private func persist() {
        UserDefaults.standard.set(Array(blockedNames), forKey: Self.storageKey)
    }
}
