import Foundation

nonisolated enum InboxFilter: String, CaseIterable {
    case unread = "Unread"
    case all = "All"
}

nonisolated struct InboxListing: Decodable {
    let data: InboxListingData

    func filtered(for filter: InboxFilter) -> InboxListing {
        guard filter == .unread else { return self }
        let replies = data.replies.compactMap { reply -> InboxReply? in
            guard reply.reportedUnread != false else { return nil }
            var unreadReply = reply
            unreadReply.isUnread = true
            return unreadReply
        }
        return InboxListing(data: InboxListingData(after: data.after, replies: replies))
    }
}

nonisolated struct InboxListingData: Decodable {
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

    init(after: String?, replies: [InboxReply]) {
        self.after = after
        self.replies = replies
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        after = try container.decodeIfPresent(String.self, forKey: .after)
        let lossy = try container.decode([LossyInboxWrapper].self, forKey: .children)
        replies = lossy.compactMap(\.reply)
    }
}

nonisolated struct InboxMessageWrapper: Decodable {
    let kind: String?
    let data: InboxMessageData

    var reply: InboxReply? {
        InboxReply(kind: kind, data: data)
    }
}

nonisolated struct InboxMessageData: Decodable {
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
    let new: Bool?
}

nonisolated struct InboxReply: Identifiable {
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
    var isUnread: Bool
    fileprivate let reportedUnread: Bool?

    init?(kind: String?, data: InboxMessageData) {
        // Unread mixes comment replies with post replies and mentions, unlike /message/comments.
        let subject = data.subject?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard subject == nil || subject == "" || subject == "comment reply",
              data.parentId?.hasPrefix("t3_") != true else { return nil }
        let isCommentReply = kind == "t1"
            || data.wasComment == true
            || (kind == nil && (
                data.subject?.localizedCaseInsensitiveContains("comment reply") == true
                    || data.parentId?.hasPrefix("t1_") == true
            ))

        guard isCommentReply,
              let rawID = data.id ?? data.name.map({ String($0.dropFirst(3)) }),
              let body = data.body,
              let createdUtc = data.createdUtc,
              let subreddit = data.subreddit else {
            return nil
        }

        let thingID = data.name ?? "t1_\(rawID)"
        // This fullname is also sent to the single-reply read and reply endpoints.
        guard thingID.hasPrefix("t1_"), !thingID.dropFirst(3).isEmpty,
              thingID.dropFirst(3).utf8.allSatisfy({ (48...57).contains($0) || (97...122).contains($0) })
        else { return nil }
        id = thingID
        self.thingID = thingID
        author = data.author ?? "[deleted]"
        self.body = body
        self.createdUtc = createdUtc
        self.subreddit = subreddit
        subredditNamePrefixed = data.subredditNamePrefixed ?? "r/\(subreddit)"
        linkTitle = data.linkTitle ?? "Comment reply"
        reportedUnread = data.new
        isUnread = data.new ?? false
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
