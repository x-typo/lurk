import Foundation
import Testing
@testable import Lurk

@Suite("More comments API", .serialized)
@MainActor
struct MoreCommentsAPITests {
    @Test("Placeholders load through morechildren and nest under their parent")
    func moreChildrenRequest() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        MoreCommentsURLProtocol.stub(data: try json(["json": ["errors": [], "data": ["things": [
            thing("x", parent: "t1_a"), thing("y", parent: "t1_x"),
        ]]]]))
        let client = RedditClient(session: session)

        let more = CommentMore(parentID: "t1_a", count: 2, childIDs: ["x", "y"])
        let loaded = try await client.fetchMoreComments(postID: "post1", more: more)
        let rows = CommentNode.rows(from: CommentNode.merging(loaded, replacing: more, in: [comment("a", [.more(more)])]), collapsed: [])

        let url = try #require(MoreCommentsURLProtocol.requests.first?.url)
        #expect(MoreCommentsURLProtocol.requests.count == 1)
        #expect(url.host == "www.reddit.com")
        #expect(url.path == "/api/morechildren.json")
        #expect(query(url, "api_type") == "json")
        #expect(query(url, "link_id") == "t3_post1")
        #expect(query(url, "children") == "x,y")
        #expect(query(url, "raw_json") == "1")
        #expect(rows.map(\.id) == ["a", "x", "y"])
        #expect(rows.map { depth($0) } == [0, 1, 2])
    }

    @Test("Large placeholders load 100 replies and keep the rest for later")
    func batchesLargePlaceholders() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        MoreCommentsURLProtocol.stub(data: try json(["json": ["errors": [], "data": ["things": []]]]))
        let client = RedditClient(session: session)
        let childIDs = (0..<130).map { "c\($0)" }

        let loaded = try await client.fetchMoreComments(
            postID: "post1",
            more: CommentMore(parentID: "t3_post1", count: 150, childIDs: childIDs)
        )

        let url = try #require(MoreCommentsURLProtocol.requests.first?.url)
        #expect(query(url, "children")?.split(separator: ",").map(String.init) == Array(childIDs.prefix(100)))
        guard let entry = loaded.last, case .more(let remaining) = entry.node else {
            Issue.record("Expected a placeholder for the remaining replies")
            return
        }
        #expect(entry.parentID == "t3_post1")
        #expect(remaining == CommentMore(parentID: "t3_post1", count: 50, childIDs: Array(childIDs.dropFirst(100))))
    }

    @Test("A child in the second batch stays under its parent from the first batch")
    func batchedParentAndChild() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let client = RedditClient(session: session)
        let childIDs = ["p"] + (0..<99).map { "f\($0)" } + ["c"]
        let first = CommentMore(parentID: "t1_root", count: childIDs.count, childIDs: childIDs)
        var nodes = [comment("root", [.more(first)])]

        MoreCommentsURLProtocol.stub(data: try json(["json": ["errors": [], "data": ["things": [
            thing("p", parent: "t1_root"),
        ]]]]))
        nodes = CommentNode.merging(try await client.fetchMoreComments(postID: "post1", more: first), replacing: first, in: nodes)
        let second = try #require(CommentNode.rows(from: nodes, collapsed: []).compactMap { row -> CommentMore? in
            guard case .more(let more, _) = row else { return nil }
            return more
        }.last)
        #expect(second.childIDs == ["c"])

        MoreCommentsURLProtocol.stub(data: try json(["json": ["errors": [], "data": ["things": [
            thing("c", parent: "t1_p"),
        ]]]]))
        nodes = CommentNode.merging(try await client.fetchMoreComments(postID: "post1", more: second), replacing: second, in: nodes)

        let rows = CommentNode.rows(from: nodes, collapsed: [])
        #expect(rows.map(\.id) == ["root", "p", "c"])
        #expect(rows.map { depth($0) } == [0, 1, 2])
    }

    @Test("Reddit errors in the morechildren envelope surface as failures")
    func moreChildrenErrors() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        MoreCommentsURLProtocol.stub(data: try json(["json": ["errors": [
            ["RATELIMIT", "You are doing that too much.", "ratelimit"],
        ]]]))
        let client = RedditClient(session: session)

        await #expect(throws: RedditClientError.self) {
            try await client.fetchMoreComments(
                postID: "post1",
                more: CommentMore(parentID: "t1_a", count: 1, childIDs: ["x"])
            )
        }
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

    @Test("A linked post loads by its ID")
    func postByIDRequest() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        MoreCommentsURLProtocol.stub(data: try json(["data": ["after": NSNull(), "children": [["data": [
            "id": "post1", "title": "A post", "author": "reader", "subreddit": "swift",
            "subreddit_name_prefixed": "r/swift", "score": 5, "num_comments": 2, "created_utc": 0,
            "permalink": "/r/swift/comments/post1/a_post/", "url": "https://example.com", "selftext": "",
            "is_self": true, "is_video": false, "stickied": false, "over_18": false,
        ]]]]]))
        let client = RedditClient(session: session)

        let post = try await client.fetchPost(id: "post1")

        let url = try #require(MoreCommentsURLProtocol.requests.first?.url)
        #expect(url.path == "/by_id/t3_post1.json")
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

    private func query(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == name })?.value
    }

    private func json(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
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
    nonisolated(unsafe) private static var responseData = Data()
    nonisolated(unsafe) private static var recordedRequests: [URLRequest] = []

    static var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests
    }

    static func stub(data: Data) {
        lock.lock()
        defer { lock.unlock() }
        responseData = data
        recordedRequests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.recordedRequests.append(request)
        let data = Self.responseData
        Self.lock.unlock()
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
