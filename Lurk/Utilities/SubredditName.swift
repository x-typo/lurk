import Foundation

enum SubredditName {
    nonisolated static func normalize(_ name: String) -> String? {
        let cleaned = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^r/", with: "", options: [.regularExpression, .caseInsensitive])
        guard !cleaned.isEmpty,
              cleaned.range(of: "^[A-Za-z0-9_]{2,21}$", options: .regularExpression) != nil
        else { return nil }
        return cleaned
    }

    nonisolated static func canonicalKey(_ name: String) -> String? {
        normalize(name)?.lowercased()
    }
}
