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
    let likes: Bool?
    let parentId: String?
    let count: Int?
    let children: [String]?
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

// `api/morechildren` returns loaded comments flat, linked to their parents by `parent_id`.
nonisolated struct MoreChildrenResponse: Decodable {
    let json: Envelope

    struct Envelope: Decodable {
        let data: Things?
    }

    struct Things: Decodable {
        let things: [CommentWrapper]
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
    let isSubmitter: Bool
    var likes: Bool? = nil

    // Deeper replies still render; indentation and rails stop growing here.
    nonisolated static let maxIndentDepth = 10

    nonisolated static let filteredBots: Set<String> = [
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

    var initialVote: Int {
        switch likes {
        case true?: 1
        case false?: -1
        case nil: 0
        }
    }

    // Reddit's score already includes the viewer's original vote.
    func displayScore(vote: Int) -> Int {
        score - initialVote + vote
    }
}

// A Reddit "more" placeholder: unloaded replies listed in `childIDs`, or, when
// `childIDs` is empty, a thread that continues below `parentID`.
nonisolated struct CommentMore: Identifiable, Equatable {
    let parentID: String
    let depth: Int
    let count: Int
    let childIDs: [String]

    var id: String { "more:\(parentID):\(childIDs.first ?? "continue")" }
    var continuesThread: Bool { childIDs.isEmpty }
}

nonisolated enum CommentNode {
    case comment(Comment, replies: [CommentNode])
    case more(CommentMore)
}

enum CommentRow: Identifiable {
    case comment(Comment, isCollapsed: Bool, hiddenReplyCount: Int)
    case more(CommentMore)

    var id: String {
        switch self {
        case .comment(let comment, _, _): comment.id
        case .more(let more): more.id
        }
    }
}

// MARK: - Parsing

extension CommentNode {
    nonisolated static func parse(from listing: CommentListing) -> [CommentNode] {
        parse(listing.data.children, parentID: nil, depth: 0)
    }

    // Depth comes from tree position, so server depth values and re-rooted
    // continuation responses cannot misplace rows.
    nonisolated static func parse(_ children: [CommentWrapper], parentID: String?, depth: Int) -> [CommentNode] {
        children.compactMap { node(from: $0, parentID: parentID, depth: depth) }
    }

    nonisolated static func tree(fromFlat things: [CommentWrapper], parentID: String, depth: Int) -> [CommentNode] {
        var childrenByParent: [String: [CommentWrapper]] = [:]
        for thing in things {
            guard let parent = thing.data.parentId else { continue }
            childrenByParent[parent, default: []].append(thing)
        }

        var visitedParents = Set<String>()
        func build(under parent: String, depth: Int) -> [CommentNode] {
            guard visitedParents.insert(parent).inserted else { return [] }
            return (childrenByParent[parent] ?? []).compactMap { thing in
                guard let node = node(from: thing, parentID: parent, depth: depth) else { return nil }
                guard case .comment(let comment, let nested) = node else { return node }
                return .comment(comment, replies: nested + build(under: "t1_\(comment.id)", depth: depth + 1))
            }
        }
        return build(under: parentID, depth: depth)
    }

    private nonisolated static func node(from wrapper: CommentWrapper, parentID: String?, depth: Int) -> CommentNode? {
        let data = wrapper.data
        switch wrapper.kind {
        case "t1":
            guard let author = data.author, let body = data.body,
                  !Comment.filteredBots.contains(author) else { return nil }
            let id = data.id ?? UUID().uuidString
            let comment = Comment(
                id: id,
                author: author,
                body: body,
                score: data.score ?? 0,
                createdUtc: data.createdUtc ?? 0,
                depth: depth,
                isSubmitter: data.isSubmitter ?? false,
                likes: data.likes
            )
            var replies: [CommentNode] = []
            if case .listing(let listing) = data.replies {
                replies = parse(listing.data.children, parentID: "t1_\(id)", depth: depth + 1)
            }
            return .comment(comment, replies: replies)
        case "more":
            guard let parent = data.parentId ?? parentID else { return nil }
            let childIDs = (data.children ?? []).filter(Comment.isRedditID)
            // Only a comment can continue deeper; an empty post-level placeholder has nothing to load.
            guard !childIDs.isEmpty || parent.hasPrefix("t1_") else { return nil }
            return .more(CommentMore(
                parentID: parent,
                depth: depth,
                count: max(data.count ?? 0, childIDs.count),
                childIDs: childIDs
            ))
        default:
            return nil
        }
    }
}

// MARK: - Tree Operations

extension CommentNode {
    static func rows(from nodes: [CommentNode], collapsed: Set<String>) -> [CommentRow] {
        var rows: [CommentRow] = []
        func append(_ nodes: [CommentNode]) {
            for node in nodes {
                switch node {
                case .comment(let comment, let replies):
                    let isCollapsed = collapsed.contains(comment.id)
                    rows.append(.comment(
                        comment,
                        isCollapsed: isCollapsed,
                        hiddenReplyCount: isCollapsed ? replyCount(in: replies) : 0
                    ))
                    if !isCollapsed { append(replies) }
                case .more(let more):
                    rows.append(.more(more))
                }
            }
        }
        append(nodes)
        return rows
    }

    static func replyCount(in nodes: [CommentNode]) -> Int {
        nodes.reduce(0) { total, node in
            switch node {
            case .comment(_, let replies): total + 1 + replyCount(in: replies)
            case .more(let more): total + more.count
            }
        }
    }

    static func replacing(moreID: String, with replacement: [CommentNode], in nodes: [CommentNode]) -> [CommentNode] {
        nodes.flatMap { node -> [CommentNode] in
            switch node {
            case .more(let more):
                more.id == moreID ? replacement : [node]
            case .comment(let comment, let replies):
                [.comment(comment, replies: replacing(moreID: moreID, with: replacement, in: replies))]
            }
        }
    }

    static func commentIDs(in nodes: [CommentNode]) -> Set<String> {
        var ids = Set<String>()
        func collect(_ nodes: [CommentNode]) {
            for case .comment(let comment, let replies) in nodes {
                ids.insert(comment.id)
                collect(replies)
            }
        }
        collect(nodes)
        return ids
    }

    static func removingComments(_ ids: Set<String>, from nodes: [CommentNode]) -> [CommentNode] {
        nodes.compactMap { node in
            guard case .comment(let comment, let replies) = node else { return node }
            guard !ids.contains(comment.id) else { return nil }
            return .comment(comment, replies: removingComments(ids, from: replies))
        }
    }
}

// MARK: - Links

extension Comment {
    func permalinkURL(postPermalink: String) -> URL? {
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

    nonisolated static func isRedditID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) || (97...122).contains($0) }
    }
}
