import Foundation
import Testing
@testable import Lurk

@MainActor
@Suite("Comment continuation")
struct CommentContinuationTests {
    @Test("Mixed replies retain comments and expose Reddit more placeholders even with zero count")
    func mixedReplies() throws {
        let comments = try parse([node("abc", children: [
            node("def"), more(count: 0), ["kind": "unknown", "data": [:]],
        ])])
        let parent = try #require(comments.first)
        #expect(parent.replies.map(\.id) == ["def"])
        #expect(parent.hasMoreReplies)
        #expect(parent.replies.first?.hasMoreReplies == false)
    }

    @Test("Depth cap retains the exact parent for continuation when only an API placeholder remains")
    func placeholderAtDepthCap() throws {
        let comments = try parse([node("abc", depth: 3, children: [more(count: 17)])])
        let parent = try #require(comments.first)
        #expect(Lurk.Comment.maxRenderDepth == 3)
        #expect(parent.replies.isEmpty)
        #expect(parent.hasMoreReplies)
        #expect(parent.continuationURL(postPermalink: "/r/swift/comments/123/title/")?.absoluteString
            == "https://www.reddit.com/r/swift/comments/123/title/abc/")
    }

    @Test("Depth cap offers continuation without constructing deeper comment rows")
    func omittedDescendants() throws {
        let parent = try #require(parse([node("abc", depth: 3, children: [
            node("def", depth: 4, children: [node("ghi", depth: 5)]), more(count: 8),
        ])]).first)
        #expect(parent.replies.isEmpty)
        #expect(parent.hasMoreReplies)
    }

    @Test("Missing or underreported server depth cannot expand the rendered tree beyond the cap")
    func malformedDepthRemainsBounded() throws {
        for depth: Int? in [nil, 0, -1] {
            var tree = node("leaf", depth: depth)
            for index in (0..<8).reversed() {
                tree = node("c\(index)", depth: depth, children: [tree])
            }
            var current = try #require(parse([tree]).first)
            for expectedDepth in 0..<Lurk.Comment.maxRenderDepth {
                #expect(current.depth == expectedDepth)
                current = try #require(current.replies.first)
            }
            #expect(current.depth == Lurk.Comment.maxRenderDepth)
            #expect(current.replies.isEmpty)
            #expect(current.hasMoreReplies)
        }
    }

    @Test("Leaf and unknown child types do not advertise omitted replies")
    func noFalseContinuation() throws {
        let comments = try parse([
            node("abc"), node("def", depth: 3),
            node("ghi", children: [["kind": "unknown", "data": [:]]]),
        ])
        #expect(comments.allSatisfy { !$0.hasMoreReplies })
    }

    @Test("Canonical relative and official absolute post permalinks produce the exact comment URL")
    func canonicalURLs() throws {
        let comment = try #require(parse([node("abc123")]).first)
        for path in [
            "/r/swift/comments/xyz123/post_title/",
            "/r/swift/comments/xyz123/post_title",
            "https://www.reddit.com/r/swift/comments/xyz123/post_title/",
            "https://old.reddit.com/r/swift/comments/xyz123/post_title/",
        ] {
            #expect(comment.continuationURL(postPermalink: path)?.absoluteString
                == "https://www.reddit.com/r/swift/comments/xyz123/post_title/abc123/")
        }
    }

    @Test("Untrusted hosts, schemes, authorities, queries and injected path segments are rejected")
    func rejectsUnsafePermalinks() throws {
        let comment = try #require(parse([node("abc123")]).first)
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
            #expect(comment.continuationURL(postPermalink: path) == nil, "Accepted unsafe path: \(path)")
        }
    }

    @Test("Missing IDs and malformed IDs never create invented or injected deep links")
    func rejectsInvalidCommentIDs() throws {
        for id: String? in [nil, "", "../evil", "abc/def", "abc?x=1", "abc#fragment", "abc%2Fdef", "t1_abc"] {
            let comment = try #require(parse([node(id)]).first)
            #expect(comment.continuationURL(postPermalink: "/r/swift/comments/xyz/title/") == nil)
        }
    }

    private func parse(_ children: [[String: Any]]) throws -> [Lurk.Comment] {
        let data = try JSONSerialization.data(withJSONObject: ["data": ["children": children]])
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return Lurk.Comment.parse(from: try decoder.decode(CommentListing.self, from: data))
    }

    private func node(_ id: String?, depth: Int? = nil, children: [[String: Any]] = []) -> [String: Any] {
        var data: [String: Any] = ["author": "reader", "body": "body", "score": 1,
                                   "replies": ["data": ["children": children]]]
        if let id { data["id"] = id }
        if let depth { data["depth"] = depth }
        return ["kind": "t1", "data": data]
    }

    private func more(count: Int) -> [String: Any] {
        ["kind": "more", "data": ["count": count, "children": ["omitted"]]]
    }
}
