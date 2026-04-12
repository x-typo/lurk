import Foundation

@Observable
final class SubredditStore {
    private static let storageKey = "lurk.subreddits"
    private static let defaults = ["ClaudeAI", "ClaudeCode", "singularity"]

    private(set) var subreddits: [String] = []

    init() {
        load()
    }

    func addSubreddit(_ name: String) {
        let normalized = name
            .replacingOccurrences(of: "^r/", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              normalized.range(of: "^[A-Za-z0-9_]{2,21}$", options: .regularExpression) != nil
        else { return }
        guard !subreddits.contains(where: { $0.lowercased() == normalized.lowercased() }) else { return }
        subreddits.append(normalized)
        persist()
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
        subreddits = names.sorted { $0.lowercased() < $1.lowercased() }
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
