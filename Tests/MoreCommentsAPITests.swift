import Foundation
import Testing
@testable import Lurk

@Suite("More comments API", .serialized)
@MainActor
struct MoreCommentsAPITests {
    @Test("Hidden replies load from their parent's thread, without the replies already showing")
    func hiddenRepliesFromParentThread() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        MoreCommentsURLProtocol.stub(data: try thread(node("a", parent: "t3_post1", replies: [
            node("s", parent: "t1_a", replies: [node("s2", parent: "t1_s")]),
            node("x", parent: "t1_a", replies: [node("y", parent: "t1_x")]),
            placeholder(parent: "t1_a", children: ["z"], count: 1),
        ])))
        let client = RedditClient(session: session)

        let more = CommentMore(parentID: "t1_a", count: 3, childIDs: ["x", "y"])
        let loaded = try await client.fetchMoreComments(postID: "post1", more: more)
        let rows = CommentNode.rows(
            from: CommentNode.merging(loaded, replacing: more, in: [comment("a", [comment("s"), .more(more)])]),
            collapsed: []
        )

        let url = try #require(MoreCommentsURLProtocol.requests.first?.url)
        #expect(MoreCommentsURLProtocol.requests.count == 1)
        #expect(url.host == "www.reddit.com")
        #expect(url.path == "/comments/post1.json")
        #expect(query(url, "comment") == "a")
        #expect(query(url, "raw_json") == "1")
        #expect(rows.map(\.id) == ["a", "s", "x", "y", "more:t1_a:z"])
        #expect(rows.map { depth($0) } == [0, 1, 1, 2, 1])
    }

    @Test("A placeholder that comes back under the same ID keeps its replies reachable")
    func returnedPlaceholderWithSameID() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        MoreCommentsURLProtocol.stub(data: try thread(node("a", parent: "t3_post1", replies: [
            node("y", parent: "t1_a"),
            placeholder(parent: "t1_a", children: ["x"], count: 1),
        ])))
        let client = RedditClient(session: session)

        let more = CommentMore(parentID: "t1_a", count: 2, childIDs: ["x", "y"])
        let loaded = try await client.fetchMoreComments(postID: "post1", more: more)
        let rows = CommentNode.rows(from: CommentNode.merging(loaded, replacing: more, in: [comment("a", [.more(more)])]), collapsed: [])

        #expect(rows.map(\.id) == ["a", "y", "more:t1_a:x"])
    }

    @Test("Replies the parent's thread leaves out load from their own threads")
    func hiddenRepliesMissingFromParentThread() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        MoreCommentsURLProtocol.stub { url in
            switch self.query(url, "comment") {
            case "a": (200, try! self.thread(node("a", parent: "t3_post1", replies: [node("s", parent: "t1_a")])))
            case "x": (200, try! self.thread(node("x", parent: "t1_a")))
            default: (404, Data())
            }
        }
        let client = RedditClient(session: session)

        let more = CommentMore(parentID: "t1_a", count: 1, childIDs: ["x"])
        let loaded = try await client.fetchMoreComments(postID: "post1", more: more)
        let rows = CommentNode.rows(
            from: CommentNode.merging(loaded, replacing: more, in: [comment("a", [comment("s"), .more(more)])]),
            collapsed: []
        )

        #expect(MoreCommentsURLProtocol.requests.compactMap { $0.url.flatMap { query($0, "comment") } } == ["a", "x"])
        #expect(rows.map(\.id) == ["a", "s", "x"])
        #expect(rows.map { depth($0) } == [0, 1, 1])
    }

    @Test("Top-level placeholders load their next 10 comments from their own threads and keep the rest")
    func topLevelBatch() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        MoreCommentsURLProtocol.stub { url in
            (200, try! self.thread(node(self.query(url, "comment") ?? "", parent: "t3_post1")))
        }
        let client = RedditClient(session: session)
        let childIDs = (0..<13).map { "c\($0)" }

        let more = CommentMore(parentID: "t3_post1", count: 15, childIDs: childIDs)
        let loaded = try await client.fetchMoreComments(postID: "post1", more: more)

        let urls = MoreCommentsURLProtocol.requests.compactMap(\.url)
        #expect(urls.count == 10)
        #expect(Set(urls.compactMap { query($0, "comment") }) == Set(childIDs.prefix(10)))
        #expect(urls.allSatisfy { $0.host == "www.reddit.com" && $0.path == "/comments/post1.json" })
        let rows = CommentNode.rows(from: CommentNode.merging(loaded, replacing: more, in: [.more(more)]), collapsed: [])
        #expect(rows.map(\.id) == Array(childIDs.prefix(10)) + ["more:t3_post1:c10"])
        guard let entry = loaded.last, case .more(let remaining) = entry.node else {
            Issue.record("Expected a placeholder for the remaining comments")
            return
        }
        #expect(entry.parentID == "t3_post1")
        #expect(remaining == CommentMore(parentID: "t3_post1", count: 5, childIDs: ["c10", "c11", "c12"]))
    }

    @Test("A reply loaded on its own lands under its parent, once")
    func separateReplyUnderParent() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        MoreCommentsURLProtocol.stub { url in
            switch self.query(url, "comment") {
            case "p": (200, try! self.thread(node("p", parent: "t3_post1", replies: [node("c", parent: "t1_p")])))
            case "c": (200, try! self.thread(node("c", parent: "t1_p", replies: [node("d", parent: "t1_c")])))
            default: (404, Data())
            }
        }
        let client = RedditClient(session: session)

        let more = CommentMore(parentID: "t3_post1", count: 2, childIDs: ["p", "c"])
        let loaded = try await client.fetchMoreComments(postID: "post1", more: more)
        let rows = CommentNode.rows(from: CommentNode.merging(loaded, replacing: more, in: [comment("t"), .more(more)]), collapsed: [])

        #expect(rows.map(\.id) == ["t", "p", "c", "d"])
        #expect(rows.map { depth($0) } == [0, 0, 1, 2])
    }

    @Test("A refused thread request fails the whole load")
    func refusedThreadRequest() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        MoreCommentsURLProtocol.stub { url in
            self.query(url, "comment") == "c1"
                ? (403, Data("You've been blocked by network security".utf8))
                : (200, try! self.thread(node(self.query(url, "comment") ?? "", parent: "t3_post1")))
        }
        let client = RedditClient(session: session)

        let error = await #expect(throws: RedditClientError.self) {
            try await client.fetchMoreComments(
                postID: "post1",
                more: CommentMore(parentID: "t3_post1", count: 3, childIDs: ["c0", "c1", "c2"])
            )
        }
        #expect(error?.deniesAccess == true)
    }

    @Test("Continuations load the parent comment's thread and keep its depth")
    func continuation() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let parent: [String: Any] = ["kind": "t1", "data": [
            "id": "a", "author": "reader", "body": "parent", "score": 1, "depth": 0,
            "replies": ["data": ["children": [
                ["kind": "t1", "data": [
                    "id": "x", "author": "reader", "body": "reply", "score": 1, "depth": 1,
                    "replies": ["data": ["children": [thing("y", parent: "t1_x")]]],
                ]],
            ]]],
        ]]
        MoreCommentsURLProtocol.stub(data: try json([
            ["data": ["children": []]],
            ["data": ["children": [parent]]],
        ]))
        let client = RedditClient(session: session)

        let more = CommentMore(parentID: "t1_a", count: 0, childIDs: [])
        let loaded = try await client.fetchMoreComments(postID: "post1", more: more)

        let url = try #require(MoreCommentsURLProtocol.requests.first?.url)
        #expect(url.path == "/comments/post1.json")
        #expect(query(url, "comment") == "a")
        #expect(query(url, "raw_json") == "1")
        #expect(loaded.map(\.parentID) == ["t1_a", "t1_x"])
        let rows = CommentNode.rows(from: CommentNode.merging(loaded, replacing: more, in: [comment("a", [.more(more)])]), collapsed: [])
        #expect(rows.map(\.id) == ["a", "x", "y"])
        #expect(rows.map { depth($0) } == [0, 1, 2])
    }

    @Test("A comment's context loads through the thread endpoint with three parents")
    func commentContextRequest() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        MoreCommentsURLProtocol.stub(data: try json([
            ["kind": "Listing", "data": ["children": []]],
            ["kind": "Listing", "data": ["children": [
                ["kind": "t1", "data": ["id": "top", "author": "reader", "body": "body", "score": 1,
                                        "replies": ["data": ["children": [thing("focus", parent: "t1_top")]]]]],
            ]]],
        ]))
        let client = RedditClient(session: session)

        let nodes = try await client.fetchCommentContext(postID: "post1", commentID: "focus")

        let url = try #require(MoreCommentsURLProtocol.requests.first?.url)
        #expect(url.path == "/comments/post1.json")
        #expect(query(url, "comment") == "focus")
        #expect(query(url, "context") == "3")
        #expect(query(url, "raw_json") == "1")
        #expect(CommentNode.rows(from: nodes, collapsed: []).map(\.id) == ["top", "focus"])
    }

    @Test("A linked post loads from the head of its comments page")
    func postByIDRequest() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        MoreCommentsURLProtocol.stub(data: try json([
            ["kind": "Listing", "data": ["after": NSNull(), "children": [["kind": "t3", "data": [
                "id": "post1", "title": "A post", "author": "reader", "subreddit": "swift",
                "subreddit_name_prefixed": "r/swift", "score": 5, "num_comments": 2, "created_utc": 0,
                "permalink": "/r/swift/comments/post1/a_post/", "url": "https://example.com", "selftext": "",
                "is_self": true, "is_video": false, "stickied": false, "over_18": false,
            ]]]]],
            ["kind": "Listing", "data": ["children": [thing("x", parent: "t3_post1")]]],
        ]))
        let client = RedditClient(session: session)

        let post = try await client.fetchPost(id: "post1")

        let url = try #require(MoreCommentsURLProtocol.requests.first?.url)
        #expect(url.host == "www.reddit.com")
        #expect(url.path == "/comments/post1.json")
        #expect(query(url, "limit") == "1")
        #expect(query(url, "raw_json") == "1")
        #expect(post.id == "post1")
        #expect(post.permalink == "/r/swift/comments/post1/a_post/")
    }

    @Test("Thread links with invalid IDs never reach the network")
    func threadRequestsRejectInvalidIDs() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        MoreCommentsURLProtocol.stub(data: Data())
        let client = RedditClient(session: session)

        await #expect(throws: URLError.self) { try await client.fetchPost(id: "../evil") }
        await #expect(throws: URLError.self) { try await client.fetchCommentContext(postID: "post1", commentID: "Bad") }
        #expect(MoreCommentsURLProtocol.requests.isEmpty)
    }

    @Test("Invalid post or comment IDs never reach the network")
    func rejectsInvalidIDs() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        MoreCommentsURLProtocol.stub(data: Data())
        let client = RedditClient(session: session)
        let valid = CommentMore(parentID: "t1_a", count: 1, childIDs: ["x"])

        for (postID, more) in [
            ("../evil", valid),
            ("POST1", valid),
            ("post1", CommentMore(parentID: "t1_../x", count: 0, childIDs: [])),
            ("post1", CommentMore(parentID: "t3_post1", count: 0, childIDs: [])),
            ("post1", CommentMore(parentID: "t3_post1", count: 1, childIDs: ["../x"])),
        ] {
            await #expect(throws: URLError.self) {
                try await client.fetchMoreComments(postID: postID, more: more)
            }
        }
        #expect(MoreCommentsURLProtocol.requests.isEmpty)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MoreCommentsURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    nonisolated private func query(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == name })?.value
    }

    nonisolated private func json(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    // A `?comment=` thread response focused on `focus`.
    nonisolated private func thread(_ focus: [String: Any]) throws -> Data {
        try json([
            ["kind": "Listing", "data": ["children": []]],
            ["kind": "Listing", "data": ["children": [focus]]],
        ])
    }

    nonisolated private func node(_ id: String, parent: String, replies: [[String: Any]] = []) -> [String: Any] {
        ["kind": "t1", "data": ["id": id, "author": "reader", "body": "body", "score": 1, "parent_id": parent,
                                "replies": replies.isEmpty ? "" as Any : ["kind": "Listing", "data": ["children": replies]] as Any]]
    }

    nonisolated private func placeholder(parent: String, children: [String], count: Int) -> [String: Any] {
        ["kind": "more", "data": ["id": children[0], "count": count, "parent_id": parent, "children": children]]
    }

    private func thing(_ id: String, parent: String) -> [String: Any] {
        ["kind": "t1", "data": ["id": id, "author": "reader", "body": "body", "score": 1,
                                "parent_id": parent, "replies": ""]]
    }

    private func depth(_ row: CommentRow) -> Int {
        switch row {
        case .comment(_, let depth, _, _): depth
        case .more(_, let depth): depth
        }
    }

    private func comment(_ id: String, _ replies: [CommentNode] = []) -> CommentNode {
        .comment(Lurk.Comment(id: id, author: "reader", body: "body", score: 1, createdUtc: 0,
                              isSubmitter: false), replies: replies)
    }
}

private nonisolated final class MoreCommentsURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var respond: @Sendable (URL) -> (status: Int, data: Data) = { _ in (200, Data()) }
    nonisolated(unsafe) private static var recordedRequests: [URLRequest] = []

    static var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests
    }

    static func stub(data: Data) {
        stub { _ in (200, data) }
    }

    static func stub(_ respond: @escaping @Sendable (URL) -> (status: Int, data: Data)) {
        lock.lock()
        defer { lock.unlock() }
        self.respond = respond
        recordedRequests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.recordedRequests.append(request)
        let respond = Self.respond
        Self.lock.unlock()
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, data) = respond(url)
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
