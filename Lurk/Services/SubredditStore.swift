import Foundation

@Observable
final class SubredditStore {
    private static let storageKey = "lurk.subreddits"
    private static let defaults = ["ClaudeAI", "ClaudeCode", "singularity"]

    private(set) var subreddits: [String] = []

    init() {
        load()
    }

    @discardableResult
    func addSubreddit(_ name: String) -> String? {
        guard let normalized = SubredditName.normalize(name) else { return nil }
        guard !subreddits.contains(where: { $0.lowercased() == normalized.lowercased() }) else { return normalized }
        subreddits.append(normalized)
        persist()
        return normalized
    }

    func removeSubreddit(_ name: String) {
        subreddits.removeAll { $0 == name }
        persist()
    }

    func removeSubreddit(matching name: String) {
        subreddits.removeAll { $0.lowercased() == name.lowercased() }
        persist()
    }

    func replaceAll(_ names: [String]) {
        var seen = Set<String>()
        let valid = names.compactMap { name -> String? in
            guard let normalized = SubredditName.normalize(name),
                  seen.insert(normalized.lowercased()).inserted
            else { return nil }
            return normalized
        }
        subreddits = valid.sorted { $0.lowercased() < $1.lowercased() }
        persist()
    }

    private func load() {
        if let stored = UserDefaults.standard.array(forKey: Self.storageKey) as? [String] {
            subreddits = stored
        } else {
            subreddits = Self.defaults
        }
    }

    private func persist() {
        UserDefaults.standard.set(subreddits, forKey: Self.storageKey)
    }
}
