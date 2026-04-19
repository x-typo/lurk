import Foundation

enum SubredditName {
    static func normalize(_ name: String) -> String? {
        let cleaned = name
            .replacingOccurrences(of: "^r/", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty,
              cleaned.range(of: "^[A-Za-z0-9_]{2,21}$", options: .regularExpression) != nil
        else { return nil }
        return cleaned
    }

    static func canonicalKey(_ name: String) -> String? {
        normalize(name)?.lowercased()
    }
}
