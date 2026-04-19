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
        blockedNames.sorted()
    }

    func block(_ name: String) {
        blockedNames.insert(Self.canonicalize(name))
        persist()
    }

    func unblock(_ name: String) {
        blockedNames.remove(Self.canonicalize(name))
        persist()
    }

    func isBlocked(_ name: String) -> Bool {
        blockedNames.contains(Self.canonicalize(name))
    }

    func clearAll() {
        blockedNames.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }

    private static func canonicalize(_ name: String) -> String {
        SubredditName.canonicalKey(name) ?? name.lowercased()
    }

    private func load() {
        let raw = UserDefaults.standard.object(forKey: Self.storageKey)
        if raw == nil {
            blockedNames = Set(Self.seedDefaults)
            persist()
        } else if let stored = raw as? [String] {
            blockedNames = Set(stored.map { $0.lowercased() })
        } else {
            assertionFailure("BlockedSubredditStore: unexpected type \(type(of: raw)) at key \(Self.storageKey)")
            blockedNames = []
        }
    }

    private func persist() {
        UserDefaults.standard.set(Array(blockedNames), forKey: Self.storageKey)
    }
}
