import Foundation

nonisolated struct InboxListing: Decodable {
    let data: InboxListingData
}

struct InboxListingData: Decodable {
    let after: String?
    let replies: [InboxReply]

    private struct LossyInboxWrapper: Decodable {
        let reply: InboxReply?

        init(from decoder: Decoder) throws {
            reply = try? InboxMessageWrapper(from: decoder).reply
        }
    }

    enum CodingKeys: String, CodingKey {
        case after, children
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        after = try container.decodeIfPresent(String.self, forKey: .after)
        let lossy = try container.decode([LossyInboxWrapper].self, forKey: .children)
        replies = lossy.compactMap(\.reply)
    }
}

struct InboxMessageWrapper: Decodable {
    let kind: String?
    let data: InboxMessageData

    var reply: InboxReply? {
        InboxReply(kind: kind, data: data)
    }
}

struct InboxMessageData: Decodable {
    let id: String?
    let name: String?
    let author: String?
    let body: String?
    let createdUtc: TimeInterval?
    let subreddit: String?
    let subredditNamePrefixed: String?
    let linkTitle: String?
    let linkPermalink: String?
    let context: String?
    let permalink: String?
    let parentId: String?
    let wasComment: Bool?
    let subject: String?
}

struct InboxReply: Identifiable {
    let id: String
    let thingID: String
    let author: String
    let body: String
    let createdUtc: TimeInterval
    let subreddit: String
    let subredditNamePrefixed: String
    let linkTitle: String
    let contextURL: URL?
    let fullCommentsURL: URL?

    init?(kind: String?, data: InboxMessageData) {
        let isCommentReply = kind == "t1"
            || data.wasComment == true
            || data.subject?.localizedCaseInsensitiveContains("comment reply") == true
            || data.parentId?.hasPrefix("t1_") == true

        guard isCommentReply,
              let rawID = data.id ?? data.name?.replacingOccurrences(of: "t1_", with: ""),
              let author = data.author,
              let body = data.body,
              let createdUtc = data.createdUtc,
              let subreddit = data.subreddit,
              let linkTitle = data.linkTitle else {
            return nil
        }

        id = data.name ?? "t1_\(rawID)"
        thingID = data.name ?? "t1_\(rawID)"
        self.author = author
        self.body = body
        self.createdUtc = createdUtc
        self.subreddit = subreddit
        subredditNamePrefixed = data.subredditNamePrefixed ?? "r/\(subreddit)"
        self.linkTitle = linkTitle
        contextURL = Self.redditURL(from: data.context ?? data.permalink)
        fullCommentsURL = Self.fullCommentsURL(
            linkPermalink: data.linkPermalink,
            context: data.context ?? data.permalink
        )
    }

    private static func redditURL(from rawValue: String?) -> URL? {
        guard let rawValue, !rawValue.isEmpty else { return nil }
        if let url = URL(string: rawValue), let scheme = url.scheme, !scheme.isEmpty {
            return url
        }
        return URL(string: "https://www.reddit.com\(normalizedPath(rawValue))")
    }

    private static func fullCommentsURL(linkPermalink: String?, context: String?) -> URL? {
        if let url = redditURL(from: linkPermalink) {
            return url
        }

        guard let context, !context.isEmpty else { return nil }
        let components = normalizedPath(context)
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard let commentsIndex = components.firstIndex(of: "comments"),
              components.count > commentsIndex + 2 else {
            return redditURL(from: context)
        }

        let postComponentEnd = min(commentsIndex + 3, components.count)
        let postPath = "/" + components[0..<postComponentEnd].joined(separator: "/") + "/"
        return URL(string: "https://www.reddit.com\(postPath)")
    }

    private static func normalizedPath(_ rawPath: String) -> String {
        rawPath.hasPrefix("/") ? rawPath : "/\(rawPath)"
    }
}
