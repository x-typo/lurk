import Foundation

// MARK: - API Response Types (separate from post listings)

struct CommentListing: Decodable {
    let data: CommentListingData
}

struct CommentListingData: Decodable {
    let children: [CommentWrapper]
}

struct CommentWrapper: Decodable {
    let kind: String
    let data: CommentData
}

struct CommentData: Decodable {
    let author: String?
    let body: String?
    let score: Int?
    let createdUtc: TimeInterval?
    let replies: CommentReplies?
    let id: String?
    let depth: Int?
    let isSubmitter: Bool?
}

enum CommentReplies: Decodable {
    case listing(CommentListing)
    case empty

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let listing = try? container.decode(CommentListing.self) {
            self = .listing(listing)
        } else {
            self = .empty
        }
    }
}

// MARK: - Parsed Comment

struct Comment: Identifiable {
    let id: String
    let author: String
    let body: String
    let score: Int
    let createdUtc: TimeInterval
    let depth: Int
    let replies: [Comment]
    let isSubmitter: Bool
    var hasMoreReplies = false

    nonisolated static let maxRenderDepth = 3

    nonisolated static let filteredBots: Set<String> = [
        "AutoModerator",
        "AnimeMod",
        "flairassistant",
        "trendingtattler",
        "post-explainer",
        "ClaudeAI-mod-bot",
        "WithoutReason1729",
        "dexterthebot"
    ]
}

extension Comment {
    nonisolated static func parse(from listing: CommentListing) -> [Comment] {
        parse(from: listing, renderDepth: 0)
    }

    private nonisolated static func parse(from listing: CommentListing, renderDepth: Int) -> [Comment] {
        listing.data.children.compactMap { wrapper in
            guard wrapper.kind == "t1" else { return nil }
            let d = wrapper.data
            guard let author = d.author, let body = d.body,
                  !filteredBots.contains(author) else { return nil }
            let depth = max(renderDepth, d.depth ?? 0)
            let withinDepth = depth < maxRenderDepth
            let children = replyChildren(d.replies)
            return Comment(
                id: d.id ?? UUID().uuidString,
                author: author,
                body: body,
                score: d.score ?? 0,
                createdUtc: d.createdUtc ?? 0,
                depth: depth,
                replies: withinDepth ? parseReplies(d.replies, renderDepth: depth + 1) : [],
                isSubmitter: d.isSubmitter ?? false,
                hasMoreReplies: children.contains { $0.kind == "more" || (!withinDepth && $0.kind == "t1") }
            )
        }
    }

    private nonisolated static func parseReplies(_ replies: CommentReplies?, renderDepth: Int) -> [Comment] {
        guard case .listing(let listing) = replies else { return [] }
        return parse(from: listing, renderDepth: renderDepth)
    }

    private nonisolated static func replyChildren(_ replies: CommentReplies?) -> [CommentWrapper] {
        guard case .listing(let listing) = replies else { return [] }
        return listing.data.children
    }

    func continuationURL(postPermalink: String) -> URL? {
        guard Self.isRedditID(id), let source = URLComponents(string: postPermalink),
              source.user == nil, source.password == nil, source.port == nil,
              source.query == nil, source.fragment == nil else { return nil }

        if let scheme = source.scheme {
            guard scheme.lowercased() == "https",
                  let host = source.host?.lowercased(),
                  ["reddit.com", "www.reddit.com", "old.reddit.com"].contains(host) else { return nil }
        } else {
            guard source.host == nil, postPermalink.hasPrefix("/"),
                  !postPermalink.hasPrefix("//") else { return nil }
        }

        let path = source.path.hasSuffix("/") ? String(source.path.dropLast()) : source.path
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 6, parts[0].isEmpty, parts[1] == "r", parts[3] == "comments",
              !parts[2].isEmpty, parts[2].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }),
              Self.isRedditID(String(parts[4])), !parts[5].isEmpty,
              parts[5].allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else { return nil }

        var destination = URLComponents()
        destination.scheme = "https"
        destination.host = "www.reddit.com"
        destination.path = "\(path)/\(id)/"
        return destination.url
    }

    private static func isRedditID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) || (97...122).contains($0) }
    }
}
