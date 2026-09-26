import Foundation

@Observable
final class MuteStore {
    private static let usersKey = "lurk.mutedUsers"
    private static let keywordsKey = "lurk.mutedKeywords"
    private static let hidesPinnedKey = "lurk.hidePinnedModComments"
    // Bots that were hard-coded before muting moved to Settings.
    private static let seedUsers = [
        "AutoModerator",
        "AnimeMod",
        "flairassistant",
        "trendingtattler",
        "post-explainer",
        "ClaudeAI-mod-bot",
        "WithoutReason1729",
        "dexterthebot",
        "PCMRBot",
        "BeAmazed-ModBot"
    ]

    private(set) var users: [String] = []
    private(set) var keywords: [String] = []
    // Lowercased, for case-insensitive lookups.
    private(set) var mutedUserKeys: Set<String> = []
    // On unless turned off in Settings. Pinned comments are mostly moderator bots.
    var hidesPinnedModComments: Bool {
        didSet { defaults.set(hidesPinnedModComments, forKey: Self.hidesPinnedKey) }
    }

    // Observed, so feeds re-filter when keywords change.
    private var keywordPattern: NSRegularExpression?
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hidesPinnedModComments = defaults.object(forKey: Self.hidesPinnedKey) as? Bool ?? true
        load()
    }

    func isMuted(user name: String) -> Bool {
        mutedUserKeys.contains(name.lowercased())
    }

    func matchesKeyword(in text: String) -> Bool {
        guard let keywordPattern else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return keywordPattern.firstMatch(in: text, range: range) != nil
    }

    @discardableResult
    func muteUser(_ name: String) -> String? {
        guard let normalized = Self.normalizedUser(name) else { return nil }
        if !isMuted(user: normalized) {
            users = Self.sorted(users + [normalized])
            usersChanged()
        }
        return normalized
    }

    func unmuteUser(_ name: String) {
        let key = name.lowercased()
        users.removeAll { $0.lowercased() == key }
        usersChanged()
    }

    @discardableResult
    func muteKeyword(_ keyword: String) -> String? {
        guard let normalized = Self.normalizedKeyword(keyword) else { return nil }
        if !keywords.contains(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) {
            keywords = Self.sorted(keywords + [normalized])
            keywordsChanged()
        }
        return normalized
    }

    func unmuteKeyword(_ keyword: String) {
        keywords.removeAll { $0.caseInsensitiveCompare(keyword) == .orderedSame }
        keywordsChanged()
    }

    static func normalizedUser(_ name: String) -> String? {
        let cleaned = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^(/?u/|@)", with: "", options: [.regularExpression, .caseInsensitive])
        guard cleaned.range(of: "^[A-Za-z0-9_-]{1,32}$", options: .regularExpression) != nil else { return nil }
        return cleaned
    }

    static func normalizedKeyword(_ keyword: String) -> String? {
        let cleaned = keyword
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !cleaned.isEmpty, cleaned.count <= 60,
              cleaned.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
        return cleaned
    }

    private static func sorted(_ values: [String]) -> [String] {
        values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func usersChanged() {
        mutedUserKeys = Set(users.map { $0.lowercased() })
        defaults.set(users, forKey: Self.usersKey)
    }

    private func keywordsChanged() {
        keywordPattern = Self.pattern(for: keywords)
        defaults.set(keywords, forKey: Self.keywordsKey)
    }

    // Whole words or phrases, so "AI" doesn't hide "said".
    private static func pattern(for keywords: [String]) -> NSRegularExpression? {
        guard !keywords.isEmpty else { return nil }
        let alternatives = keywords.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        return try? NSRegularExpression(
            pattern: "(?<![\\p{L}\\p{N}])(?:\(alternatives))(?![\\p{L}\\p{N}])",
            options: [.caseInsensitive]
        )
    }

    private func load() {
        switch defaults.object(forKey: Self.usersKey) {
        case nil:
            users = Self.sorted(Self.seedUsers)
            usersChanged()
        case let stored as [String]:
            users = Self.sorted(Self.unique(stored.compactMap(Self.normalizedUser)))
            mutedUserKeys = Set(users.map { $0.lowercased() })
        case let other?:
            assertionFailure("MuteStore: unexpected type \(type(of: other)) at key \(Self.usersKey)")
            users = []
            usersChanged()
        }

        let storedKeywords = defaults.stringArray(forKey: Self.keywordsKey) ?? []
        keywords = Self.sorted(Self.unique(storedKeywords.compactMap(Self.normalizedKeyword)))
        keywordPattern = Self.pattern(for: keywords)
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.lowercased()).inserted }
    }
}
