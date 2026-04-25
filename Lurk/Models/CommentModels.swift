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
    let moreCount: Int
    let isSubmitter: Bool

    nonisolated static let maxRenderDepth = 3

    nonisolated static let filteredBots: Set<String> = [
        "AutoModerator",
        "AnimeMod",
        "trendingtattler",
        "post-explainer",
        "ClaudeAI-mod-bot"
    ]
}

extension Comment {
    nonisolated static func parse(from listing: CommentListing) -> [Comment] {
        listing.data.children.compactMap { wrapper in
            guard wrapper.kind == "t1" else { return nil }
            let d = wrapper.data
            guard let author = d.author, let body = d.body,
                  !filteredBots.contains(author) else { return nil }
            let depth = d.depth ?? 0
            let withinDepth = depth < maxRenderDepth
            return Comment(
                id: d.id ?? UUID().uuidString,
                author: author,
                body: body,
                score: d.score ?? 0,
                createdUtc: d.createdUtc ?? 0,
                depth: depth,
                replies: withinDepth ? parseReplies(d.replies) : [],
                moreCount: withinDepth ? 0 : countReplies(d.replies),
                isSubmitter: d.isSubmitter ?? false
            )
        }
    }

    private nonisolated static func parseReplies(_ replies: CommentReplies?) -> [Comment] {
        guard case .listing(let listing) = replies else { return [] }
        return parse(from: listing)
    }

    private nonisolated static func countReplies(_ replies: CommentReplies?) -> Int {
        guard case .listing(let listing) = replies else { return 0 }
        return listing.data.children.reduce(0) { total, wrapper in
            guard wrapper.kind == "t1" else { return total }
            return total + 1 + countReplies(wrapper.data.replies)
        }
    }
}
