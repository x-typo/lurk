import Foundation
import Testing
@testable import Lurk

@MainActor
@Suite("Comment parsing")
struct CommentParsingTests {
    @Test("Reply placeholders keep their parent, count and loadable IDs")
    func replyPlaceholders() throws {
        let nodes = try parse([node("abc", children: [
            node("def"), more(count: 7, children: ["ghi", "jkl"]), ["kind": "unknown", "data": [:]],
        ])])
        let children = try #require(replies(of: nodes.first))
        #expect(children.count == 2)
        guard case .comment(let reply, _) = children[0], case .more(let placeholder) = children[1] else {
            Issue.record("Expected a comment followed by a placeholder")
            return
        }
        #expect(reply.id == "def")
        #expect(placeholder == CommentMore(parentID: "t1_abc", count: 7, childIDs: ["ghi", "jkl"]))
        #expect(!placeholder.continuesThread)
        #expect(CommentNode.rows(from: nodes, collapsed: []).map { depth($0) } == [0, 1, 1])
    }

    @Test("A zero count still reports the listed replies, and tree position sets the parent")
    func zeroCountPlaceholder() throws {
        let nodes = try parse([node("abc", children: [
            more(count: 0, children: ["omitted"], parentID: "t1_other"),
        ])])
        guard case .more(let placeholder)? = replies(of: nodes.first)?.first else {
            Issue.record("Expected a placeholder")
            return
        }
        #expect(placeholder.count == 1)
        #expect(placeholder.parentID == "t1_abc")
    }

    @Test("Continuation placeholders under a comment load that comment's thread")
    func continuationPlaceholder() throws {
        let nodes = try parse([node("abc", children: [more(count: 0, children: [])])])
        guard case .more(let placeholder)? = replies(of: nodes.first)?.first else {
            Issue.record("Expected a continuation placeholder")
            return
        }
        #expect(placeholder == CommentMore(parentID: "t1_abc", count: 0, childIDs: []))
        #expect(placeholder.continuesThread)
    }

    @Test("Post-level placeholders load only when they list replies")
    func postLevelPlaceholders() throws {
        #expect(try parse([more(count: 0, children: [], parentID: "t3_post")]).isEmpty)
        #expect(try parse([more(count: 3, children: ["abc"])]).isEmpty)
        guard case .more(let placeholder)? = try parse([more(count: 12, children: ["abc"], parentID: "t3_post")]).first else {
            Issue.record("Expected a post-level placeholder")
            return
        }
        #expect(placeholder == CommentMore(parentID: "t3_post", count: 12, childIDs: ["abc"]))
        #expect(placeholder.isTopLevel)
    }

    @Test("Placeholder IDs that are not Reddit IDs are discarded")
    func invalidPlaceholderIDs() throws {
        let nodes = try parse([node("abc", children: [
            more(count: 5, children: ["ok1", "../evil", "T1_ABC", "", "abc?x=1", "a,b"]),
        ])])
        guard case .more(let placeholder)? = replies(of: nodes.first)?.first else {
            Issue.record("Expected a placeholder")
            return
        }
        #expect(placeholder.childIDs == ["ok1"])
    }

    @Test("Deep threads are kept, with depth taken from tree position")
    func deepThreadsAreNotTruncated() throws {
        for serverDepth: Int? in [nil, 0, -1, 99] {
            var tree = node("leaf", depth: serverDepth)
            for index in (0..<11).reversed() {
                tree = node("c\(index)", depth: serverDepth, children: [tree])
            }
            let rows = CommentNode.rows(from: try parse([tree]), collapsed: [])
            #expect(rows.map { depth($0) } == Array(0..<12))
        }
    }

    @Test("Parsing keeps every author, so muting can change without reloading")
    func parsingKeepsAllAuthors() throws {
        let nodes = try parse([node("bot", author: "AutoModerator", children: [node("reply")]), node("human")])
        #expect(CommentNode.rowIDs(in: nodes) == ["bot", "reply", "human"])
    }

    @Test("Reddit's stickied flag marks a pinned comment")
    func pinnedFlag() throws {
        let nodes = try parse([
            node("pinned", author: "AutoModerator", stickied: true), node("unpinned", stickied: false), node("absent"),
        ])
        let pinned = nodes.compactMap { node -> Bool? in
            guard case .comment(let comment, _) = node else { return nil }
            return comment.isPinned
        }
        #expect(pinned == [true, false, false])
    }

    @Test("A comment carries Reddit's saved state, and a missing value means not saved")
    func viewerSave() throws {
        let nodes = try parse([node("saved", saved: true), node("unsaved", saved: false), node("unknown")])
        let comments = nodes.compactMap { node -> Lurk.Comment? in
            guard case .comment(let comment, _) = node else { return nil }
            return comment
        }
        #expect(comments.map(\.saved) == [true, false, false])
    }

    @Test("The viewer's vote seeds the displayed score without double counting")
    func viewerVote() throws {
        let nodes = try parse([
            node("up", score: 10, likes: true), node("down", score: 10, likes: false), node("none", score: 10),
        ])
        let comments = nodes.compactMap { node -> Lurk.Comment? in
            guard case .comment(let comment, _) = node else { return nil }
            return comment
        }
        #expect(comments.map(\.initialVote) == [1, -1, 0])
        #expect(comments[0].displayScore(vote: 1) == 10)
        #expect(comments[0].displayScore(vote: 0) == 9)
        #expect(comments[0].displayScore(vote: -1) == 8)
        #expect(comments[1].displayScore(vote: 1) == 12)
        #expect(comments[2].displayScore(vote: 1) == 11)
    }

    @Test("Flat morechildren results keep their parents and skip malformed things")
    func flatThings() throws {
        let loaded = CommentNode.loaded(fromFlat: try wrappers([
            thing("a", parent: "t1_root"), thing("b", parent: "t1_a"),
            ["kind": "more", "data": ["count": 4, "parent_id": "t1_b", "children": ["d"]]],
            ["kind": "t1", "data": ["id": "orphan", "author": "reader", "body": "body"]],
            ["kind": "t1", "data": ["id": "nobody", "parent_id": "t1_root", "body": "no author"]],
        ]))
        #expect(loaded.map(\.parentID) == ["t1_root", "t1_a", "t1_b"])
        guard case .more(let placeholder) = loaded[2].node else {
            Issue.record("Expected the nested placeholder")
            return
        }
        #expect(placeholder == CommentMore(parentID: "t1_b", count: 4, childIDs: ["d"]))
    }

    @Test("Flattening a nested tree pairs every node with its tree parent")
    func flattenTree() throws {
        let nodes = try parse([node("a", children: [node("b", children: [more(count: 2, children: ["c"])])])])
        let loaded = CommentNode.flatten(nodes, under: "t1_root")
        #expect(loaded.map(\.parentID) == ["t1_root", "t1_a", "t1_b"])
        #expect(loaded.allSatisfy { entry in
            guard case .comment(_, let replies) = entry.node else { return true }
            return replies.isEmpty
        })
    }

    @Test("Canonical relative and official absolute post permalinks produce the exact comment URL")
    func canonicalURLs() throws {
        let comment = try #require(firstComment(try parse([node("abc123")])))
        for path in [
            "/r/swift/comments/xyz123/post_title/",
            "/r/swift/comments/xyz123/post_title",
            "https://www.reddit.com/r/swift/comments/xyz123/post_title/",
            "https://old.reddit.com/r/swift/comments/xyz123/post_title/",
        ] {
            #expect(comment.permalinkURL(postPermalink: path)?.absoluteString
                == "https://www.reddit.com/r/swift/comments/xyz123/post_title/abc123/")
        }
    }

    @Test("Untrusted hosts, schemes, authorities, queries and injected path segments are rejected")
    func rejectsUnsafePermalinks() throws {
        let comment = try #require(firstComment(try parse([node("abc123")])))
        for path in [
            "http://www.reddit.com/r/swift/comments/xyz/title/",
            "javascript:alert(1)", "file:///r/swift/comments/xyz/title/",
            "https://reddit.com.evil.test/r/swift/comments/xyz/title/",
            "https://evil.test/r/swift/comments/xyz/title/",
            "https://user@www.reddit.com/r/swift/comments/xyz/title/",
            "https://www.reddit.com:443/r/swift/comments/xyz/title/",
            "//www.reddit.com/r/swift/comments/xyz/title/",
            "/r/swift/comments/xyz/title/?redirect=evil", "/r/swift/comments/xyz/title/#fragment",
            "/r/swift/comments/xyz/../", "/r/swift/comments/xyz/title/anothercomment/",
            "/r/swift/comments/xyz/title%2Fextra/", "/r/swift/comments/xyz/%252Fextra/",
            "/r/swift/comments/xyz/title\\extra/", "/r//comments/xyz/title/",
            "/r/swift/comments/not-an-id/title/", "r/swift/comments/xyz/title/",
        ] {
            #expect(comment.permalinkURL(postPermalink: path) == nil, "Accepted unsafe path: \(path)")
        }
    }

    @Test("Missing IDs and malformed IDs never create invented or injected deep links")
    func rejectsInvalidCommentIDs() throws {
        for id: String? in [nil, "", "../evil", "abc/def", "abc?x=1", "abc#fragment", "abc%2Fdef", "t1_abc"] {
            let comment = try #require(firstComment(try parse([node(id)])))
            #expect(comment.permalinkURL(postPermalink: "/r/swift/comments/xyz/title/") == nil)
        }
    }

    private func parse(_ children: [[String: Any]]) throws -> [CommentNode] {
        CommentNode.parse(from: try decode(CommentListing.self, ["data": ["children": children]]))
    }

    private func wrappers(_ things: [[String: Any]]) throws -> [CommentWrapper] {
        try decode([CommentWrapper].self, things)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ object: Any) throws -> T {
        try RedditAPI.decoder.decode(type, from: JSONSerialization.data(withJSONObject: object))
    }

    private func replies(of node: CommentNode?) -> [CommentNode]? {
        guard case .comment(_, let replies)? = node else { return nil }
        return replies
    }

    private func firstComment(_ nodes: [CommentNode]) -> Lurk.Comment? {
        guard case .comment(let comment, _)? = nodes.first else { return nil }
        return comment
    }

    private func depth(_ row: CommentRow) -> Int {
        switch row {
        case .comment(_, let depth, _, _): depth
        case .more(_, let depth): depth
        }
    }

    private func node(
        _ id: String?,
        author: String = "reader",
        depth: Int? = nil,
        score: Int = 1,
        likes: Bool? = nil,
        saved: Bool? = nil,
        stickied: Bool? = nil,
        children: [[String: Any]] = []
    ) -> [String: Any] {
        var data: [String: Any] = ["author": author, "body": "body", "score": score,
                                   "replies": ["data": ["children": children]]]
        if let id { data["id"] = id }
        if let depth { data["depth"] = depth }
        if let likes { data["likes"] = likes }
        if let saved { data["saved"] = saved }
        if let stickied { data["stickied"] = stickied }
        return ["kind": "t1", "data": data]
    }

    private func more(count: Int, children: [String], parentID: String? = nil) -> [String: Any] {
        var data: [String: Any] = ["count": count, "children": children]
        if let parentID { data["parent_id"] = parentID }
        return ["kind": "more", "data": data]
    }

    private func thing(_ id: String, parent: String, author: String = "reader") -> [String: Any] {
        ["kind": "t1", "data": ["id": id, "author": author, "body": "body", "score": 1,
                                "parent_id": parent, "replies": ""]]
    }
}
