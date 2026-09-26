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
    let saved: Bool?
    let parentId: String?
    let count: Int?
    let children: [String]?
    let stickied: Bool?
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
    let isSubmitter: Bool
    var likes: Bool? = nil
    var saved = false
    // Reddit's `stickied`: a moderator pinned it to the top of the thread.
    var isPinned = false

    // Deeper replies still render; indentation and rails stop growing here.
    nonisolated static let maxIndentDepth = 10

    var initialVote: Int { likes.voteDirection }

    // Reddit's score already includes the viewer's original vote.
    func displayScore(vote: Int) -> Int {
        score - initialVote + vote
    }
}

// A Reddit "more" placeholder: unloaded replies listed in `childIDs`, or, when
// `childIDs` is empty, a thread that continues below `parentID`.
nonisolated struct CommentMore: Identifiable, Equatable {
    let parentID: String
    let count: Int
    let childIDs: [String]

    var id: String { "more:\(parentID):\(childIDs.first ?? "continue")" }
    var continuesThread: Bool { childIDs.isEmpty }
    var isTopLevel: Bool { parentID.hasPrefix("t3_") }
}

// Depth is never stored: it comes from tree position, so merged and re-rooted replies cannot misplace rows.
nonisolated enum CommentNode {
    case comment(Comment, replies: [CommentNode])
    case more(CommentMore)
}

// A loaded comment (without replies) or placeholder, and the fullname of the parent it belongs under.
nonisolated struct LoadedCommentNode {
    let parentID: String
    let node: CommentNode
}

enum CommentRow: Identifiable {
    case comment(Comment, depth: Int, isCollapsed: Bool, hiddenReplyCount: Int)
    case more(CommentMore, depth: Int)

    var id: String {
        switch self {
        case .comment(let comment, _, _, _): comment.id
        case .more(let more, _): more.id
        }
    }
}

// MARK: - Parsing

extension CommentNode {
    nonisolated static func parse(from listing: CommentListing) -> [CommentNode] {
        parse(listing.data.children, parentID: nil)
    }

    nonisolated static func parse(_ children: [CommentWrapper], parentID: String?) -> [CommentNode] {
        children.compactMap { node(from: $0, parentID: parentID) }
    }

    // `api/morechildren` returns comments flat, linked to their parents by `parent_id`.
    nonisolated static func loaded(fromFlat things: [CommentWrapper]) -> [LoadedCommentNode] {
        things.flatMap { thing -> [LoadedCommentNode] in
            guard let parentID = thing.data.parentId,
                  let node = node(from: thing, parentID: parentID) else { return [] }
            return flatten([node], under: parentID)
        }
    }

    nonisolated static func flatten(_ nodes: [CommentNode], under parentID: String) -> [LoadedCommentNode] {
        nodes.flatMap { node -> [LoadedCommentNode] in
            guard case .comment(let comment, let replies) = node else {
                return [LoadedCommentNode(parentID: parentID, node: node)]
            }
            return [LoadedCommentNode(parentID: parentID, node: .comment(comment, replies: []))]
                + flatten(replies, under: "t1_\(comment.id)")
        }
    }

    private nonisolated static func node(from wrapper: CommentWrapper, parentID: String?) -> CommentNode? {
        let data = wrapper.data
        switch wrapper.kind {
        case "t1":
            guard let author = data.author, let body = data.body else { return nil }
            let id = data.id ?? UUID().uuidString
            let comment = Comment(
                id: id,
                author: author,
                body: body,
                score: data.score ?? 0,
                createdUtc: data.createdUtc ?? 0,
                isSubmitter: data.isSubmitter ?? false,
                likes: data.likes,
                saved: data.saved ?? false,
                isPinned: data.stickied ?? false
            )
            var replies: [CommentNode] = []
            if case .listing(let listing) = data.replies {
                replies = parse(listing.data.children, parentID: "t1_\(id)")
            }
            return .comment(comment, replies: replies)
        case "more":
            guard let parent = parentID ?? data.parentId else { return nil }
            let childIDs = (data.children ?? []).filter(Comment.isRedditID)
            // Only a comment can continue deeper; an empty post-level placeholder has nothing to load.
            guard !childIDs.isEmpty || parent.hasPrefix("t1_") else { return nil }
            return .more(CommentMore(
                parentID: parent,
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
    static func comments(in nodes: [CommentNode]) -> [Comment] {
        nodes.flatMap { node -> [Comment] in
            guard case .comment(let comment, let replies) = node else { return [] }
            return [comment] + comments(in: replies)
        }
    }

    // `mutedUsers` holds lowercased usernames. A muted comment, or a pinned one when
    // `hidesPinned` is on, hides with its replies.
    static func rows(
        from nodes: [CommentNode],
        collapsed: Set<String>,
        mutedUsers: Set<String> = [],
        hidesPinned: Bool = false
    ) -> [CommentRow] {
        var rows: [CommentRow] = []
        func append(_ nodes: [CommentNode], depth: Int) {
            for node in nodes {
                switch node {
                case .comment(let comment, let replies):
                    guard !isHidden(comment, mutedUsers: mutedUsers, hidesPinned: hidesPinned) else { continue }
                    let isCollapsed = collapsed.contains(comment.id)
                    rows.append(.comment(
                        comment,
                        depth: depth,
                        isCollapsed: isCollapsed,
                        hiddenReplyCount: isCollapsed
                            ? replyCount(in: replies, mutedUsers: mutedUsers, hidesPinned: hidesPinned)
                            : 0
                    ))
                    if !isCollapsed { append(replies, depth: depth + 1) }
                case .more(let more):
                    rows.append(.more(more, depth: depth))
                }
            }
        }
        append(nodes, depth: 0)
        return rows
    }

    static func replyCount(in nodes: [CommentNode], mutedUsers: Set<String> = [], hidesPinned: Bool = false) -> Int {
        nodes.reduce(0) { total, node in
            switch node {
            case .comment(let comment, let replies):
                isHidden(comment, mutedUsers: mutedUsers, hidesPinned: hidesPinned)
                    ? total
                    : total + 1 + replyCount(in: replies, mutedUsers: mutedUsers, hidesPinned: hidesPinned)
            case .more(let more): total + more.count
            }
        }
    }

    private static func isHidden(_ comment: Comment, mutedUsers: Set<String>, hidesPinned: Bool) -> Bool {
        (hidesPinned && comment.isPinned) || mutedUsers.contains(comment.author.lowercased())
    }

    // Replaces `more` with the loaded nodes. A loaded node whose parent is anywhere in the
    // tree attaches under that parent, so replies split across requests stay together.
    // Comments and placeholders already in the tree are skipped, keeping their new replies.
    static func merging(_ loaded: [LoadedCommentNode], replacing more: CommentMore, in nodes: [CommentNode]) -> [CommentNode] {
        var seen = rowIDs(in: nodes)
        var childrenByParent: [String: [CommentNode]] = [:]
        for entry in loaded {
            let id = switch entry.node {
            case .comment(let comment, _): comment.id
            case .more(let placeholder): placeholder.id
            }
            guard seen.insert(id).inserted else { continue }
            childrenByParent[entry.parentID, default: []].append(entry.node)
        }

        var attachedParents = Set<String>()
        func take(_ parentID: String) -> [CommentNode] {
            guard attachedParents.insert(parentID).inserted else { return [] }
            return (childrenByParent[parentID] ?? []).map { node in
                guard case .comment(let comment, let replies) = node else { return node }
                return .comment(comment, replies: replies + take("t1_\(comment.id)"))
            }
        }

        func merge(_ nodes: [CommentNode], parentID: String?) -> [CommentNode] {
            var merged = nodes.flatMap { node -> [CommentNode] in
                switch node {
                case .more(let placeholder):
                    placeholder.id == more.id ? take(parentID ?? more.parentID) : [node]
                case .comment(let comment, let replies):
                    [.comment(comment, replies: merge(replies, parentID: "t1_\(comment.id)"))]
                }
            }
            if let parentID { merged += take(parentID) }
            return merged
        }
        return merge(nodes, parentID: nil)
    }

    static func rowIDs(in nodes: [CommentNode]) -> Set<String> {
        var ids = Set<String>()
        func collect(_ nodes: [CommentNode]) {
            for node in nodes {
                switch node {
                case .comment(let comment, let replies):
                    ids.insert(comment.id)
                    collect(replies)
                case .more(let more):
                    ids.insert(more.id)
                }
            }
        }
        collect(nodes)
        return ids
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
